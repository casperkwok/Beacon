//
//  TranslationProxy.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//
//  A localhost HTTP server that bridges Codex's Responses API to a Chat Completions
//  upstream. Codex talks to `http://127.0.0.1:<port>/v1/responses`; this proxy
//  translates each request, streams it to the provider's `/chat/completions`, and
//  translates the SSE response back.
//

import Foundation
import Network

final class TranslationProxy {
    static let shared = TranslationProxy()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.casperkwok.beacon.proxy", attributes: .concurrent)
    private let session = URLSession(configuration: .default)

    private var upstreamBaseURL = ""
    private var upstreamKey = ""
    private var overrideModel: String?

    private(set) var port: UInt16 = 0
    var isRunning: Bool { listener != nil }

    private init() {}

    @discardableResult
    func start(upstream baseURL: String, apiKey: String, model: String?) -> UInt16? {
        stop()
        upstreamBaseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        upstreamKey = apiKey
        overrideModel = (model?.isEmpty == false) ? model : nil

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .loopback
        guard let l = try? NWListener(using: params, on: .any) else { return nil }
        listener = l

        let ready = DispatchSemaphore(value: 0)
        l.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.start(queue: queue)
        _ = ready.wait(timeout: .now() + 3)

        if case .ready = l.state, let p = l.port?.rawValue {
            port = p
            return p
        }
        stop()
        return nil
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        readRequest(conn, buffer: Data())
    }

    private func readRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            let sep = Data("\r\n\r\n".utf8)
            if let headerEnd = buf.firstRange(of: sep) {
                let headerText = String(decoding: buf[buf.startIndex..<headerEnd.lowerBound], as: UTF8.self)
                let contentLength = Self.contentLength(in: headerText)
                let bodyData = buf[headerEnd.upperBound...]
                if bodyData.count >= contentLength {
                    self.handle(conn, headerText: headerText, body: Data(bodyData.prefix(contentLength)))
                } else if error == nil && !isComplete {
                    self.readRequest(conn, buffer: buf)
                } else { conn.cancel() }
            } else if error == nil && !isComplete {
                self.readRequest(conn, buffer: buf)
            } else { conn.cancel() }
        }
    }

    private func handle(_ conn: NWConnection, headerText: String, body: Data) {
        let requestLine = headerText.split(separator: "\r\n").first.map(String.init) ?? ""
        guard requestLine.contains("/responses") else {
            send(conn, raw: "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", thenClose: true)
            return
        }
        send(conn, raw: "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n")

        let responseId = "resp_" + ResponsesStreamEncoder.simpleUUID()
        guard let reqObj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            let enc = ResponsesStreamEncoder(responseId: responseId, model: overrideModel ?? "")
            send(conn, raw: enc.created())
            send(conn, raw: enc.failed(code: "bad_request", message: "invalid JSON body"), thenClose: true)
            return
        }

        let model = overrideModel ?? (reqObj["model"] as? String ?? "")
        let encoder = ResponsesStreamEncoder(responseId: responseId, model: model)
        send(conn, raw: encoder.created())

        let chatBody = ResponsesTranslator.chatRequest(fromResponses: reqObj, overrideModel: overrideModel)
        guard let url = URL(string: upstreamBaseURL + "/chat/completions"),
              let payload = try? JSONSerialization.data(withJSONObject: chatBody) else {
            send(conn, raw: encoder.failed(code: "config_error", message: "bad upstream URL or body"), thenClose: true)
            return
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !upstreamKey.isEmpty { req.setValue("Bearer \(upstreamKey)", forHTTPHeaderField: "Authorization") }
        req.httpBody = payload

        relayUpstream(req, encoder: encoder, to: conn)
    }

    private func relayUpstream(_ req: URLRequest, encoder: ResponsesStreamEncoder, to conn: NWConnection) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let (bytes, response) = try await self.session.bytes(for: req)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    var errData = Data()
                    for try await b in bytes { errData.append(b) }
                    self.send(conn, raw: encoder.failed(code: "\(http.statusCode)", message: String(decoding: errData, as: UTF8.self)), thenClose: true)
                    return
                }
                var streamDone = false
                for try await line in bytes.lines {
                    guard line.hasPrefix("data:") else { continue }
                    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                    if payload == "[DONE]" { streamDone = true; break }
                    if payload.isEmpty { continue }
                    guard let chunkData = payload.data(using: .utf8),
                          let chunk = (try? JSONSerialization.jsonObject(with: chunkData)) as? [String: Any] else { continue }
                    for frame in encoder.consume(chatChunk: chunk) { self.send(conn, raw: frame) }
                }
                if streamDone {
                    for frame in encoder.finish() { self.send(conn, raw: frame) }
                } else {
                    self.send(conn, raw: encoder.failed(code: "stream_incomplete", message: "stream disconnected before completion"))
                }
                self.send(conn, raw: "", thenClose: true)
            } catch {
                self.send(conn, raw: encoder.failed(code: "connection_error", message: "\(error)"), thenClose: true)
            }
        }
    }

    private func send(_ conn: NWConnection, raw string: String, thenClose: Bool = false) {
        let data = Data(string.utf8)
        conn.send(content: data.isEmpty ? nil : data, completion: .contentProcessed { _ in
            if thenClose { conn.cancel() }
        })
    }

    private static func contentLength(in header: String) -> Int {
        for line in header.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2, parts[0].lowercased().trimmingCharacters(in: .whitespaces) == "content-length" {
                return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return 0
    }
}
