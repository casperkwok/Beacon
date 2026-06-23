//
//  ProviderStore.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//

import SwiftUI

/// Persists the user's provider list and which one is active.
@Observable
final class ProviderStore {
    static let shared = ProviderStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "beacon.providers"

    private(set) var providers: [Provider] = []

    private init() {
        load()
    }

    var activeProvider: Provider? { providers.first { $0.isActive } }
    var isDefaultActive: Bool { activeProvider == nil }

    // MARK: - Mutations

    func add(_ provider: Provider) {
        var p = provider
        p.isActive = false
        providers.append(p)
        save()
    }

    func update(_ provider: Provider) {
        guard let idx = providers.firstIndex(where: { $0.id == provider.id }) else { return }
        let wasActive = providers[idx].isActive
        var p = provider
        p.isActive = wasActive
        providers[idx] = p
        save()
    }

    func delete(_ provider: Provider) {
        providers.removeAll { $0.id == provider.id }
        save()
    }

    func setActive(_ provider: Provider?) {
        for i in providers.indices {
            providers[i].isActive = (provider != nil && providers[i].id == provider!.id)
        }
        save()
    }

    func duplicate(_ provider: Provider) -> Provider {
        var copy = provider
        copy = Provider(name: "\(provider.name) Copy", baseURL: provider.baseURL, model: provider.model,
                        apiKey: provider.apiKey, reasoningEffort: provider.reasoningEffort,
                        bridged: provider.bridged, logo: provider.logo)
        providers.append(copy)
        save()
        return copy
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Provider].self, from: data) else { return }
        providers = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(providers) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
