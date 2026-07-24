//
//  BeaconApp.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//

import SwiftUI
import AppKit

@main
struct BeaconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBar = StatusBarController()

        // If the active provider uses the bridge, bring the proxy back up (port changes per launch).
        if let active = ProviderStore.shared.activeProvider, active.bridged {
            if !ConfigManager.shared.activate(active) {
                presentBridgeFailureAlert()
            }
        }

        // Start Sparkle (schedules background update checks per Info.plist settings).
        _ = Updater.shared
    }
}
