//
//  ContentView.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var store = ProviderStore.shared
    private let config = ConfigManager.shared

    enum Screen: Equatable { case list, add, edit(Provider) }
    @State private var screen: Screen = .list
    @State private var showQuit = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    /// Routes the user can switch to (Default when a provider is active, plus inactive providers).
    private var switchable: [Provider?] {
        var out: [Provider?] = []
        if !store.isDefaultActive { out.append(nil) }
        out.append(contentsOf: store.providers.filter { !$0.isActive }.map { Optional($0) })
        return out
    }

    var body: some View {
        ZStack {
            list.opacity(screen == .list ? 1 : 0)

            if screen == .add {
                EditProviderView(provider: nil, onSave: { add($0) }, onCancel: { screen = .list })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if case .edit(let p) = screen {
                EditProviderView(provider: p, onSave: { update($0) }, onCancel: { screen = .list })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(width: 360, height: 400)
        .animation(.easeInOut(duration: 0.25), value: screen)
    }

    // MARK: - List screen

    private var list: some View {
        VStack(spacing: 0) {
            RouteHero(provider: store.activeProvider,
                      onEdit: { p in screen = .edit(p) },
                      onDelete: { p in delete(p) })
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)

            if !switchable.isEmpty {
                HStack {
                    Text("SWITCH TO").font(.system(size: 9.5, weight: .bold)).tracking(1.3).foregroundStyle(.tertiary)
                    Spacer()
                }
                .padding(.horizontal, 18).padding(.bottom, 4)
            }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(switchable.enumerated()), id: \.offset) { _, p in
                        RouteRow(provider: p,
                                 onTap: { activate(p) },
                                 onEdit: { screen = .edit($0) },
                                 onDelete: { delete($0) },
                                 onDuplicate: { screen = .edit(store.duplicate($0)) })
                    }
                    if store.isDefaultActive && store.providers.isEmpty {
                        Text("Add a provider with the + button below.")
                            .font(.caption).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity).padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)
            Divider().opacity(0.4)
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Beacon").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Button(action: { Updater.shared.checkForUpdates() }) {
                Text("v\(appVersion)").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Check for updates")
            Spacer()
            Menu {
                ForEach(ProviderTemplate.all) { t in
                    Button(t.name) { screen = .edit(prefilled(from: t)) }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            Button(action: { showQuit = true }) {
                Image(systemName: "power").font(.system(size: 12)).foregroundStyle(.tertiary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showQuit) {
                VStack(spacing: 10) {
                    Text("Quit Beacon?").font(.caption)
                    HStack(spacing: 12) {
                        Button("No") { showQuit = false }.controlSize(.small)
                        Button("Yes") { NSApp.terminate(nil) }.controlSize(.small)
                    }
                }.padding(16)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    /// A fresh provider seeded from a template (so + menu jumps straight into editing).
    private func prefilled(from t: ProviderTemplate) -> Provider {
        t.makeProvider()
    }

    // MARK: - Actions

    private func activate(_ p: Provider?) {
        let previous = store.activeProvider
        store.setActive(p)
        let ok = (p != nil) ? config.activate(p!) : config.activateDefault()
        if !ok {
            store.setActive(previous)   // roll back so the UI reflects the real state
            presentBridgeFailureAlert()
        }
    }
    private func add(_ p: Provider) {
        store.add(p); screen = .list
    }
    private func update(_ p: Provider) {
        let wasActive = store.providers.first { $0.id == p.id }?.isActive ?? false
        // New providers coming from the + template menu aren't in the store yet.
        if store.providers.contains(where: { $0.id == p.id }) {
            store.update(p)
            if wasActive && !config.activate(p) { presentBridgeFailureAlert() }
        } else {
            store.add(p)
        }
        screen = .list
    }
    private func delete(_ p: Provider) {
        let wasActive = p.isActive
        store.delete(p); config.removeBlock(p)
        if wasActive { activate(nil) }
        screen = .list
    }
}

/// Shown when activation can't bring up the local translation bridge (loopback port bind failed).
@MainActor
func presentBridgeFailureAlert() {
    let alert = NSAlert()
    alert.messageText = "Couldn't start the local bridge"
    alert.informativeText = "Beacon couldn't open a local port for the Chat ↔ Responses bridge, so the provider wasn't activated. Try again — if it keeps failing, another app may be blocking loopback connections."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
}

// MARK: - Logo / monogram avatar

struct LogoMark: View {
    let name: String
    let logo: String       // brand asset name, or "" for monogram
    let size: CGFloat

    var body: some View {
        ZStack {
            if logo == "BeaconGlyph" {
                // Beacon's own mark, in brand gold on a white chip.
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(.white)
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).strokeBorder(.black.opacity(0.07), lineWidth: 0.5)
                Image(logo).renderingMode(.template).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.58, height: size * 0.58)
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "#FFD27A"), Theme.accent], startPoint: .top, endPoint: .bottom))
            } else if !logo.isEmpty {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(.white)
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).strokeBorder(.black.opacity(0.07), lineWidth: 0.5)
                Image(logo).renderingMode(.original).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.6, height: size * 0.6)
            } else {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(LinearGradient(colors: Theme.monogramColors(name), startPoint: .top, endPoint: .bottom))
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.10), radius: size * 0.07, y: 1)
    }
}

// MARK: - Active route hero

struct RouteHero: View {
    let provider: Provider?
    let onEdit: (Provider) -> Void
    let onDelete: (Provider) -> Void
    @State private var showDelete = false

    private var isDefault: Bool { provider == nil }
    private var name: String { provider?.name ?? "Codex Default" }
    private var detail: String {
        if isDefault { return "Built-in OpenAI" }
        return provider!.model.isEmpty ? displayHost(provider!.baseURL) : provider!.model
    }

    var body: some View {
        HStack(spacing: 13) {
            LogoMark(name: name, logo: isDefault ? "OpenAILogo" : (provider!.logoAsset), size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 18, weight: .bold)).lineLimit(1).truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if provider?.bridged == true {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 8, weight: .bold))
                            Text("Bridged").font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(.secondary).padding(.vertical, 2).padding(.horizontal, 6)
                        .background(Capsule().fill(.primary.opacity(0.07)))
                    }
                }
            }
            Spacer(minLength: 6)
            if let provider {
                Button(action: { onEdit(provider) }) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(width: 30, height: 30).background(Circle().fill(.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
        .contextMenu {
            if let provider {
                Button("Edit") { onEdit(provider) }
                Button("Delete", role: .destructive) { showDelete = true }
            }
        }
        .popover(isPresented: $showDelete) {
            DeleteConfirm(name: name, onConfirm: { if let p = provider { onDelete(p) }; showDelete = false }, onCancel: { showDelete = false })
        }
    }
}

// MARK: - Switchable row

struct RouteRow: View {
    let provider: Provider?
    let onTap: () -> Void
    let onEdit: (Provider) -> Void
    let onDelete: (Provider) -> Void
    let onDuplicate: (Provider) -> Void

    @State private var hovering = false
    @State private var showDelete = false

    private var isDefault: Bool { provider == nil }
    private var name: String { provider?.name ?? "Codex Default" }
    private var detail: String {
        if isDefault { return "Built-in OpenAI" }
        return provider!.model.isEmpty ? displayHost(provider!.baseURL) : provider!.model
    }

    var body: some View {
        HStack(spacing: 11) {
            LogoMark(name: name, logo: isDefault ? "OpenAILogo" : (provider!.logoAsset), size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if hovering, let provider {
                Button(action: { onEdit(provider) }) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).background(Circle().fill(.primary.opacity(0.06)))
                }.buttonStyle(.plain)
                Button(action: { showDelete = true }) {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 22, height: 22).background(Circle().fill(.primary.opacity(0.06)))
                }.buttonStyle(.plain)
                .popover(isPresented: $showDelete) {
                    DeleteConfirm(name: name, onConfirm: { onDelete(provider); showDelete = false }, onCancel: { showDelete = false })
                }
            } else {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.primary.opacity(hovering ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Select") { onTap() }
            if let provider {
                Button("Edit") { onEdit(provider) }
                Button("Duplicate") { onDuplicate(provider) }
                Button("Delete", role: .destructive) { showDelete = true }
            }
        }
    }
}

struct DeleteConfirm: View {
    let name: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Text("Delete \"\(name)\"?").font(.headline)
            Text("This can't be undone.").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }.controlSize(.small)
                Button("Delete", role: .destructive) { onConfirm() }.controlSize(.small)
            }
        }
        .padding(16).frame(width: 220)
    }
}
