<h1 align="center">Beacon</h1>

<p align="center">
  Run <b>OpenAI Codex CLI</b> on DeepSeek, GLM, Kimi, Qwen &amp; more — one-click provider
  switching with a built-in Chat&nbsp;↔&nbsp;Responses bridge.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="License: Apache 2.0">
  <img src="https://img.shields.io/badge/Swift-5-orange.svg" alt="Swift 5">
  <img src="https://img.shields.io/badge/Platform-macOS%2014%2B-lightgrey.svg" alt="macOS 14+">
</p>

<p align="center">
  <img src="docs/hero.png" width="380" alt="Beacon menu-bar panel">
</p>

## Why Beacon?

OpenAI's Codex CLI speaks only the **Responses API**. But almost every third-party
provider — DeepSeek, Zhipu GLM, Moonshot Kimi, Qwen, MiniMax… — only offers
**Chat Completions**. Point Codex at one directly and you get:

```text
■ unexpected status 404 Not Found, url: https://api.deepseek.com/v1/responses
```

The usual workaround is to stand up an external translation gateway (LiteLLM, a
proxy, …). **Beacon does it for you, locally, with zero setup.** Pick a provider,
flip one switch, and Codex just works — Beacon runs a tiny on-device bridge that
translates Responses ⇄ Chat Completions on the fly.

## Features

- 🧭 **One-click switching** — writes `~/.codex/config.toml`, upserting a
  `[model_providers.<id>]` block and repointing `model` / `model_provider`, while
  preserving everything else in your config.
- 🌉 **Built-in Chat↔Responses bridge** — no external gateway; chat-only providers
  work out of the box.
- 🪪 **Provider profiles** — keep many providers, each with its own model, key and
  reasoning effort; switch instantly.
- 🎯 **Clean menu-bar UI** — the active provider front-and-center; switch from a tidy list.
- 🔒 **Local & private** — runs entirely on your Mac; keys live only in your Codex config.

## Supported providers

Built-in templates (you can add any OpenAI-compatible endpoint as **Custom**):

| Native Responses API | Bridged (Chat Completions) |
| --- | --- |
| OpenAI · Azure OpenAI | DeepSeek · Zhipu GLM · z.ai · Moonshot (Kimi) · MiniMax · Qwen (DashScope) · ModelScope · OpenRouter · Ollama |

## How it works

Activating a bridged provider writes something like:

```toml
model = "deepseek-v4-flash"
model_provider = "deepseek"

[model_providers.deepseek]
name = "DeepSeek"
base_url = "http://127.0.0.1:51900/v1"   # Beacon's local bridge
wire_api = "responses"
experimental_bearer_token = "beacon-bridge"
```

```
Codex ──/responses──▶  Beacon bridge (localhost)  ──/chat/completions──▶  DeepSeek
        ◀───────────  translate SSE back  ◀───────────────────────────
```

The **Default** entry returns Codex to its built-in `openai` provider (sign in
separately with `codex login`). Native providers (OpenAI / Azure) skip the bridge.

## Install

Beacon is built from source with [XcodeGen](https://github.com/yonsm/XcodeGen)
and [TOMLKit](https://github.com/LebJe/TOMLKit).

```bash
brew install xcodegen     # if needed
git clone https://github.com/casperkwok/Beacon.git
cd Beacon
xcodegen generate         # produces Beacon.xcodeproj
open Beacon.xcodeproj      # build & run the "Beacon" scheme (Xcode 16+)
```

Beacon runs unsandboxed so it can read/write `~/.codex/config.toml` and run the
local bridge.

## Usage

1. Click the Beacon icon in the menu bar.
2. Hit **+**, pick a provider template, paste your API key, **Save**.
3. Click a route to activate it — Codex picks it up on its next launch.
4. For chat-only providers, leave **Translate Chat ↔ Responses** on (it is by
   default for bridged templates).

## FAQ

**`Model metadata for … not found` warning in Codex** — Codex only ships metadata
for OpenAI's own models, so it shows this for any custom model id. It's cosmetic;
the model works fine. There's no clean way to suppress it for arbitrary models.

**Gatekeeper blocks the app** — for now Beacon is built from source. Signed,
notarized release builds may come later.

## License

[Apache License 2.0](LICENSE). Provider names and logos are trademarks of their
respective owners, used here only to identify each service.
