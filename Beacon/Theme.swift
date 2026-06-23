//
//  Theme.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//

import SwiftUI

extension Color {
    /// Create a color from a `#RRGGBB` hex string.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0
        self = Color(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum Theme {
    static let accent = Color(hex: "#E39A3C")

    /// Muted gradients used for monogram avatars (chosen deterministically by name).
    static let monogramGradients: [[Color]] = [
        [Color(hex: "#6D7C9C"), Color(hex: "#4A5677")],
        [Color(hex: "#4FA3A0"), Color(hex: "#356E73")],
        [Color(hex: "#8A7CB8"), Color(hex: "#5E5191")],
        [Color(hex: "#C07C8E"), Color(hex: "#8E5567")],
        [Color(hex: "#6FA98A"), Color(hex: "#47785F")],
        [Color(hex: "#C9954A"), Color(hex: "#9A6B22")],
    ]

    static func monogramColors(_ seed: String) -> [Color] {
        let idx = abs(seed.hashValue) % monogramGradients.count
        return monogramGradients[idx]
    }
}

/// Extract a clean host from a URL string for compact display.
func displayHost(_ urlString: String?) -> String {
    guard let urlString, !urlString.isEmpty else { return "" }
    guard let host = URL(string: urlString)?.host else { return urlString }
    return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
}
