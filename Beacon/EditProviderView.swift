//
//  EditProviderView.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//

import SwiftUI
import AppKit

struct EditProviderView: View {
    let onSave: (Provider) -> Void
    let onCancel: () -> Void
    let isNew: Bool

    @State private var draft: Provider
    @State private var showBridgeTip = false

    init(provider: Provider?, onSave: @escaping (Provider) -> Void, onCancel: @escaping () -> Void) {
        self.onSave = onSave
        self.onCancel = onCancel
        self.isNew = provider == nil
        _draft = State(initialValue: provider ?? ProviderTemplate.all.first!.makeProvider())
    }

    private var canSave: Bool {
        !draft.name.isEmpty && !draft.baseURL.isEmpty && !draft.model.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Nav bar
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "chevron.backward").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28).background(Circle().fill(.primary.opacity(0.06)))
                }.buttonStyle(.plain)
                Spacer()
                Text(isNew ? "Add Provider" : "Edit Provider").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { onSave(cleaned()) }) {
                    Text("Save").font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(canSave ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(Color.secondary))
                        .padding(.vertical, 5).padding(.horizontal, 14)
                        .background(Capsule().fill(canSave ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.primary.opacity(0.08))))
                }.buttonStyle(.plain).disabled(!canSave)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Brand hero + name
                    HStack(spacing: 12) {
                        LogoMark(name: draft.name.isEmpty ? "P" : draft.name, logo: draft.logoAsset, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PROVIDER NAME").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(.tertiary)
                            TextField("Name", text: $draft.name).textFieldStyle(.plain).font(.system(size: 16, weight: .semibold))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)

                    field("Base URL", text: $draft.baseURL, placeholder: "https://api.openai.com/v1")
                    field("Model", text: $draft.model, placeholder: "gpt-5.5")
                    secureField("API Key", text: $draft.apiKey, placeholder: "Enter your API key")
                    field("Reasoning Effort", text: $draft.reasoningEffort, placeholder: "medium")

                    HStack(spacing: 6) {
                        Text("Translate Chat ↔ Responses").font(.system(size: 13, weight: .medium))
                        Button(action: { showBridgeTip.toggle() }) {
                            Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showBridgeTip, arrowEdge: .bottom) {
                            Text("Run a local bridge for chat-only providers (DeepSeek, GLM, Kimi…). Enable if Codex returns 404 on /responses.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(12).frame(width: 240)
                        }
                        Spacer()
                        Toggle("", isOn: $draft.bridged).labelsHidden().toggleStyle(.switch).tint(Theme.accent)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
        }
        .frame(width: 360, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func cleaned() -> Provider {
        var p = draft
        p.name = p.name.isEmpty ? "Untitled" : p.name
        p.apiKey = p.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return p
    }

    @ViewBuilder
    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(1).foregroundStyle(.tertiary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.05)))
        }
    }

    @ViewBuilder
    private func secureField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(1).foregroundStyle(.tertiary)
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.05)))
        }
    }
}
