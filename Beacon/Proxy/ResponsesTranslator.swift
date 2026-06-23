//
//  ResponsesTranslator.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//
//  Translates between OpenAI Codex's Responses API and the Chat Completions API so
//  chat-only providers (DeepSeek, GLM, Kimi, …) work behind Codex's Responses client.
//

import Foundation

enum ResponsesTranslator {

    // MARK: Request: Responses → Chat

    static func chatRequest(fromResponses body: [String: Any], overrideModel: String?) -> [String: Any] {
        var messages: [[String: Any]] = []

        let systemText = (body["instructions"] as? String) ?? (body["system"] as? String)
        if let systemText, !systemText.isEmpty {
            messages.append(["role": "system", "content": systemText])
        }

        if let text = body["input"] as? String {
            messages.append(["role": "user", "content": text])
        } else if let items = body["input"] as? [[String: Any]] {
            appendInputItems(items, into: &messages)
        }

        var chat: [String: Any] = [
            "model": overrideModel ?? (body["model"] as? String ?? ""),
            "messages": messages,
        ]
        let stream = (body["stream"] as? Bool) ?? true
        chat["stream"] = stream
        if stream { chat["stream_options"] = ["include_usage": true] }
        if let tools = body["tools"] as? [[String: Any]] {
            let converted = convertTools(tools)
            if !converted.isEmpty { chat["tools"] = converted }
        }
        if let temperature = body["temperature"] { chat["temperature"] = temperature }
        if let maxOut = body["max_output_tokens"] { chat["max_tokens"] = maxOut }
        return chat
    }

    private static func appendInputItems(_ items: [[String: Any]], into messages: inout [[String: Any]]) {
        var i = 0
        while i < items.count {
            let item = items[i]
            let type = item["type"] as? String ?? ""

            if type == "function_call" {
                var toolCalls: [[String: Any]] = []
                while i < items.count, (items[i]["type"] as? String) == "function_call" {
                    let cur = items[i]
                    toolCalls.append([
                        "id": cur["call_id"] as? String ?? "",
                        "type": "function",
                        "function": ["name": cur["name"] as? String ?? "", "arguments": cur["arguments"] as? String ?? "{}"],
                    ])
                    i += 1
                }
                messages.append(["role": "assistant", "tool_calls": toolCalls])
                continue
            }

            switch type {
            case "function_call_output":
                messages.append(["role": "tool", "tool_call_id": item["call_id"] as? String ?? "", "content": item["output"] as? String ?? ""])
            case "reasoning":
                break
            default:
                var role = item["role"] as? String ?? "user"
                if role == "developer" { role = "system" }
                var msg: [String: Any] = ["role": role]
                if let content = flattenContent(item["content"]) { msg["content"] = content }
                if role == "system" {
                    if let first = messages.first, (first["role"] as? String) == "system" { messages[0] = msg }
                    else { messages.insert(msg, at: 0) }
                } else {
                    messages.append(msg)
                }
            }
            i += 1
        }
    }

    private static func flattenContent(_ value: Any?) -> Any? {
        if let s = value as? String { return s }
        guard let parts = value as? [[String: Any]] else { return value }
        let textKinds: Set<String> = ["input_text", "text", "output_text"]
        if parts.allSatisfy({ textKinds.contains($0["type"] as? String ?? "") }) {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return parts.map { part -> [String: Any] in
            if (part["type"] as? String) == "input_image" {
                return ["type": "image_url", "image_url": ["url": part["image_url"] as? String ?? ""]]
            }
            return ["type": "text", "text": part["text"] as? String ?? ""]
        }
    }

    private static func convertTools(_ tools: [[String: Any]]) -> [[String: Any]] {
        tools.compactMap { tool in
            guard (tool["type"] as? String) == "function" else { return nil }
            if tool["function"] is [String: Any] { return tool }
            var function: [String: Any] = ["name": tool["name"] as? String ?? ""]
            if let desc = tool["description"] { function["description"] = desc }
            if let params = tool["parameters"] { function["parameters"] = params }
            return ["type": "function", "function": function]
        }
    }
}

/// Streams an upstream Chat Completions SSE response, emitting Responses API SSE frames.
final class ResponsesStreamEncoder {
    let responseId: String
    let model: String

    private(set) var accumulatedText = ""
    private var emittedMessageItem = false
    private let msgItemId = "msg_" + ResponsesStreamEncoder.simpleUUID()
    private struct ToolAccum { var id = ""; var name = ""; var arguments = "" }
    private var toolCalls: [Int: ToolAccum] = [:]
    private var usage: [String: Any]?

    init(responseId: String, model: String) {
        self.responseId = responseId
        self.model = model
    }

    func created() -> String {
        sse("response.created", ["type": "response.created", "response": ["id": responseId, "status": "in_progress", "model": model]])
    }

    func consume(chatChunk chunk: [String: Any]) -> [String] {
        var out: [String] = []
        if let u = chunk["usage"] as? [String: Any] { usage = u }
        guard let choices = chunk["choices"] as? [[String: Any]] else { return out }
        for choice in choices {
            let delta = choice["delta"] as? [String: Any] ?? [:]
            if let content = delta["content"] as? String, !content.isEmpty {
                if !emittedMessageItem {
                    out.append(sse("response.output_item.added", [
                        "type": "response.output_item.added", "output_index": 0,
                        "item": ["type": "message", "id": msgItemId, "role": "assistant", "status": "in_progress", "content": []],
                    ]))
                    emittedMessageItem = true
                }
                accumulatedText += content
                out.append(sse("response.output_text.delta", [
                    "type": "response.output_text.delta", "item_id": msgItemId, "output_index": 0, "delta": content,
                ]))
            }
            if let tcs = delta["tool_calls"] as? [[String: Any]] {
                for tc in tcs {
                    let idx = tc["index"] as? Int ?? 0
                    var acc = toolCalls[idx] ?? ToolAccum()
                    if let id = tc["id"] as? String, !id.isEmpty { acc.id = id }
                    if let f = tc["function"] as? [String: Any] {
                        if let n = f["name"] as? String, !n.isEmpty { acc.name += n }
                        if let a = f["arguments"] as? String { acc.arguments += a }
                    }
                    toolCalls[idx] = acc
                }
            }
        }
        return out
    }

    func finish() -> [String] {
        var out: [String] = []
        if emittedMessageItem {
            out.append(sse("response.output_item.done", [
                "type": "response.output_item.done", "output_index": 0,
                "item": ["type": "message", "id": msgItemId, "role": "assistant", "status": "completed",
                         "content": [["type": "output_text", "text": accumulatedText]]],
            ]))
        }
        let baseIndex = emittedMessageItem ? 1 : 0
        var fcItems: [[String: Any]] = []
        for (rel, key) in toolCalls.keys.sorted().enumerated() {
            let tc = toolCalls[key]!
            let fcId = "fc_" + Self.simpleUUID()
            let outputIndex = baseIndex + rel
            out.append(sse("response.output_item.added", [
                "type": "response.output_item.added", "output_index": outputIndex,
                "item": ["type": "function_call", "id": fcId, "call_id": tc.id, "name": tc.name, "arguments": "", "status": "in_progress"],
            ]))
            if !tc.arguments.isEmpty {
                out.append(sse("response.function_call_arguments.delta", [
                    "type": "response.function_call_arguments.delta", "item_id": fcId, "output_index": outputIndex, "delta": tc.arguments,
                ]))
            }
            let doneItem: [String: Any] = ["type": "function_call", "id": fcId, "call_id": tc.id, "name": tc.name, "arguments": tc.arguments, "status": "completed"]
            out.append(sse("response.output_item.done", ["type": "response.output_item.done", "output_index": outputIndex, "item": doneItem]))
            fcItems.append(doneItem)
        }
        var outputItems: [[String: Any]] = []
        if emittedMessageItem {
            outputItems.append(["type": "message", "id": msgItemId, "role": "assistant", "status": "completed",
                                "content": [["type": "output_text", "text": accumulatedText]]])
        }
        outputItems.append(contentsOf: fcItems)
        let u = usage ?? [:]
        out.append(sse("response.completed", [
            "type": "response.completed",
            "response": ["id": responseId, "status": "completed", "model": model, "output": outputItems,
                         "usage": ["input_tokens": u["prompt_tokens"] as? Int ?? 0,
                                   "output_tokens": u["completion_tokens"] as? Int ?? 0,
                                   "total_tokens": u["total_tokens"] as? Int ?? 0]],
        ]))
        return out
    }

    func failed(code: String, message: String) -> String {
        sse("response.failed", ["type": "response.failed", "response": ["id": responseId, "status": "failed", "error": ["code": code, "message": message]]])
    }

    private func sse(_ event: String, _ payload: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes])) ?? Data()
        return "event: \(event)\ndata: \(String(data: data, encoding: .utf8) ?? "{}")\n\n"
    }

    static func simpleUUID() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
}
