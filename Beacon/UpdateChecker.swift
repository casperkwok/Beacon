//
//  UpdateChecker.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//
//  Sparkle-based auto-updater. Checks the appcast on a schedule and lets the user
//  check on demand; Sparkle handles download + install of the signed, notarized build.
//

import SwiftUI
import Sparkle

@Observable
final class Updater {
    static let shared = Updater()

    @ObservationIgnored let controller: SPUStandardUpdaterController
    var canCheck = true

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // Mirror Sparkle's readiness into an observable flag for the menu state.
        canCheck = controller.updater.canCheckForUpdates
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.canCheck = self?.controller.updater.canCheckForUpdates ?? true
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
