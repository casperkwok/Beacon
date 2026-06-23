//
//  Models.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//

import Foundation

/// A configurable field of a Codex provider.
enum ProviderField: String, CaseIterable, Identifiable {
    case baseURL = "base_url"
    case model = "model"
    case apiKey = "api_key"
    case reasoningEffort = "reasoning_effort"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .baseURL: return "Base URL"
        case .model: return "Model"
        case .apiKey: return "API Key"
        case .reasoningEffort: return "Reasoning Effort"
        }
    }

    var placeholder: String {
        switch self {
        case .baseURL: return "https://api.openai.com/v1"
        case .model: return "gpt-5.5"
        case .apiKey: return "Enter your API key"
        case .reasoningEffort: return "medium (minimal/low/medium/high/xhigh)"
        }
    }

    var isSecure: Bool { self == .apiKey }
}

/// A single saved Codex provider profile.
struct Provider: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var baseURL: String
    var model: String
    var apiKey: String
    var reasoningEffort: String
    /// Route through the local Chat↔Responses bridge (for chat-only providers).
    var bridged: Bool
    /// Brand logo asset name, or empty for a monogram avatar.
    var logo: String
    var isActive: Bool = false

    init(id: UUID = UUID(), name: String, baseURL: String, model: String, apiKey: String = "",
         reasoningEffort: String = "medium", bridged: Bool = false, logo: String = "", isActive: Bool = false) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.reasoningEffort = reasoningEffort
        self.bridged = bridged
        self.logo = logo
        self.isActive = isActive
    }

    /// Brand logo asset name, inferred from the host when not set explicitly.
    var logoAsset: String {
        if !logo.isEmpty { return logo }
        let host = URL(string: baseURL)?.host ?? ""
        if baseURL.contains("11434") { return "OllamaLogo" }
        if host.contains("deepseek.com") { return "DeepSeekLogo" }
        if host.contains("bigmodel.cn") { return "ZhipuLogo" }
        if host.contains("z.ai") { return "ZaiLogo" }
        if host.contains("moonshot.cn") || host.contains("kimi.com") { return "MoonshotLogo" }
        if host.contains("minimax") { return "MiniMaxLogo" }
        if host.contains("modelscope") { return "ModelScopeLogo" }
        if host.contains("longcat") { return "LongCatLogo" }
        if host.contains("openrouter") { return "AnyRouterLogo" }
        if host.contains("dashscope") || host.contains("aliyuncs") { return "QwenLogo" }
        if host.contains("openai.com") || host.contains("azure") { return "OpenAILogo" }
        return ""
    }

    /// A TOML-safe slug derived from the name, falling back to the id.
    var slug: String {
        var out = ""
        var lastUnderscore = false
        for scalar in name.lowercased().unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                out.unicodeScalars.append(scalar); lastUnderscore = false
            } else if !lastUnderscore {
                out.append("_"); lastUnderscore = true
            }
        }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let reserved: Set<String> = ["openai", "ollama", "lmstudio"]
        if out.isEmpty || reserved.contains(out) {
            let suffix = id.uuidString.prefix(8).lowercased()
            out = out.isEmpty ? "beacon_\(suffix)" : "\(out)_\(suffix)"
        }
        return out
    }
}

/// A starting-point preset for a provider.
struct ProviderTemplate: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let baseURL: String
    let model: String
    let bridged: Bool
    let logo: String
    let docLink: String?

    func makeProvider() -> Provider {
        Provider(name: name, baseURL: baseURL, model: model,
                 reasoningEffort: "medium", bridged: bridged, logo: logo)
    }

    static let all: [ProviderTemplate] = [
        // Native Responses API — no bridge.
        ProviderTemplate(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-5.5",
                         bridged: false, logo: "OpenAILogo", docLink: "https://developers.openai.com/codex/config-reference"),
        ProviderTemplate(name: "Azure OpenAI", baseURL: "https://YOUR-RESOURCE.openai.azure.com/openai/v1", model: "gpt-5.5",
                         bridged: false, logo: "OpenAILogo", docLink: "https://learn.microsoft.com/azure/ai-services/openai/"),
        // Chat-only providers (OpenAI-compatible) — bridged.
        ProviderTemplate(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-v4-flash",
                         bridged: true, logo: "DeepSeekLogo", docLink: "https://api-docs.deepseek.com/"),
        ProviderTemplate(name: "Zhipu GLM", baseURL: "https://open.bigmodel.cn/api/paas/v4", model: "glm-4.6",
                         bridged: true, logo: "ZhipuLogo", docLink: "https://docs.bigmodel.cn/"),
        ProviderTemplate(name: "z.ai", baseURL: "https://api.z.ai/api/paas/v4", model: "glm-4.6",
                         bridged: true, logo: "ZaiLogo", docLink: "https://docs.z.ai/"),
        ProviderTemplate(name: "Moonshot (Kimi)", baseURL: "https://api.moonshot.cn/v1", model: "kimi-k2-0905-preview",
                         bridged: true, logo: "MoonshotLogo", docLink: "https://platform.moonshot.cn/docs"),
        ProviderTemplate(name: "MiniMax", baseURL: "https://api.minimaxi.com/v1", model: "MiniMax-M2",
                         bridged: true, logo: "MiniMaxLogo", docLink: "https://platform.minimaxi.com/"),
        ProviderTemplate(name: "Qwen (DashScope)", baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", model: "qwen-max",
                         bridged: true, logo: "QwenLogo", docLink: "https://help.aliyun.com/zh/model-studio/"),
        ProviderTemplate(name: "ModelScope", baseURL: "https://api-inference.modelscope.cn/v1", model: "Qwen/Qwen3-Coder-480B-A35B-Instruct",
                         bridged: true, logo: "ModelScopeLogo", docLink: "https://modelscope.cn/docs"),
        ProviderTemplate(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1", model: "openai/gpt-5.5",
                         bridged: true, logo: "AnyRouterLogo", docLink: "https://openrouter.ai/docs"),
        ProviderTemplate(name: "Ollama (Local)", baseURL: "http://localhost:11434/v1", model: "qwen3-coder",
                         bridged: true, logo: "OllamaLogo", docLink: "https://github.com/ollama/ollama"),
        ProviderTemplate(name: "Custom", baseURL: "", model: "", bridged: false, logo: "BeaconGlyph", docLink: nil),
    ]
}
