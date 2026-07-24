//
//  ConfigManager.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//
//  Reads and writes OpenAI Codex CLI configuration (`~/.codex/config.toml`).
//  Activating a provider upserts a `[model_providers.<slug>]` block and repoints the
//  top-level `model` / `model_provider`, preserving all unrelated configuration.
//

import Foundation
import TOMLKit

@Observable
final class ConfigManager {
    static let shared = ConfigManager()

    static let reservedSlugs: Set<String> = ["openai", "ollama", "lmstudio"]

    private var dir: URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
    private var configURL: URL { dir.appendingPathComponent("config.toml") }
    private var backupURL: URL { dir.appendingPathComponent("config.toml.backup") }

    private init() {}

    // MARK: - Public API

    /// Upsert the provider block and point Codex at it. Returns false on write failure.
    @discardableResult
    func activate(_ provider: Provider) -> Bool {
        let table = readTable()

        var effectiveBaseURL = provider.baseURL
        if provider.bridged {
            // If the bridge can't bind a loopback port, bail out rather than writing a
            // broken config (upstream URL + wire_api=responses + fake token → 404s in Codex).
            guard let port = TranslationProxy.shared.start(upstream: provider.baseURL, apiKey: provider.apiKey, model: provider.model) else {
                return false
            }
            effectiveBaseURL = "http://127.0.0.1:\(port)/v1"
        } else {
            TranslationProxy.shared.stop()
        }

        let block = TOMLTable()
        block["name"] = provider.name
        block["base_url"] = effectiveBaseURL
        block["wire_api"] = "responses"
        if provider.bridged {
            block["experimental_bearer_token"] = "beacon-bridge"
        } else if !provider.apiKey.isEmpty {
            block["experimental_bearer_token"] = provider.apiKey
        }

        let providers = subtable(table, "model_providers")
        providers[provider.slug] = block

        table["model_provider"] = provider.slug
        if !provider.model.isEmpty { table["model"] = provider.model }
        if !provider.reasoningEffort.isEmpty { table["model_reasoning_effort"] = provider.reasoningEffort }

        return write(table)
    }

    /// Return Codex to its built-in `openai` provider (Beacon's "Default").
    @discardableResult
    func activateDefault() -> Bool {
        TranslationProxy.shared.stop()
        let table = readTable()
        table["model_provider"] = "openai"
        table.remove(at: "model")
        table.remove(at: "model_reasoning_effort")
        return write(table)
    }

    /// Remove a provider's block (when deleted in the app).
    @discardableResult
    func removeBlock(_ provider: Provider) -> Bool {
        let table = readTable()
        table["model_providers"]?.table?.remove(at: provider.slug)
        return write(table)
    }

    // MARK: - Internals

    private func ensureExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: configURL.path) {
            try? Data().write(to: configURL)
        }
    }

    private func readTable() -> TOMLTable {
        ensureExists()
        let text = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return TOMLTable() }
        return (try? TOMLTable(string: text)) ?? TOMLTable()
    }

    @discardableResult
    private func write(_ table: TOMLTable) -> Bool {
        ensureExists()
        backup()
        do {
            try table.convert(to: .toml).data(using: .utf8)?.write(to: configURL)
            return true
        } catch {
            restore()
            return false
        }
    }

    private func subtable(_ parent: TOMLTable, _ key: String) -> TOMLTable {
        if let existing = parent[key]?.table { return existing }
        parent[key] = TOMLTable()
        return parent[key]?.table ?? TOMLTable()
    }

    private func backup() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: configURL.path) else { return }
        try? fm.removeItem(at: backupURL)
        try? fm.copyItem(at: configURL, to: backupURL)
    }

    private func restore() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backupURL.path) else { return }
        try? fm.removeItem(at: configURL)
        try? fm.copyItem(at: backupURL, to: configURL)
        try? fm.removeItem(at: backupURL)
    }
}
