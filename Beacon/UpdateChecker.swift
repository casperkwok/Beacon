//
//  UpdateChecker.swift
//  Beacon
//
//  Copyright © 2026 casperkwok. Licensed under the Apache License, Version 2.0.
//
//  Lightweight "is there a newer release?" check against the GitHub Releases API.
//  No auto-install (that needs code signing) — just surfaces a link to the release.
//

import SwiftUI

@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// Set this to your GitHub `owner/repo`.
    static let repo = "casperkwok/Beacon"

    var available = false
    var latestVersion = ""
    var releaseURL: URL?

    private init() {}

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func check() {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let urlString = json["html_url"] as? String
            DispatchQueue.main.async {
                guard Self.isNewer(latest, than: self.currentVersion) else { return }
                self.latestVersion = latest
                self.releaseURL = urlString.flatMap { URL(string: $0) }
                self.available = true
            }
        }.resume()
    }

    /// Semantic-ish comparison of dotted version strings.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
