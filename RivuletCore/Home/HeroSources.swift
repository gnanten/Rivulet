// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley
//
//  What Home's hero shows: any mix of trending, Home's lists and favorites, plus the
//  playlists pinned to it (`HomePlaylistPins`, `.hero`). None at all turns the hero off.
//  Per Plex Home profile, as the hero's playlists are.
//

import Foundation

nonisolated enum HeroSources {

    enum Source: String, CaseIterable, Sendable {
        case trending, continueWatching, recentlyAdded, watchlist, favoriteMovies, favoriteShows
    }

    /// Posted after any change, the hero playlists' included.
    static let changedNotification = Notification.Name("heroSourcesChanged")

    private static var key: String { HomeSettingsScope.key("homeHeroSources") }

    /// A profile that never chose gets the device-wide choice from before sources could be
    /// mixed: one list (`homeHeroContent`), or none (`showHomeHero` off).
    static var sources: Set<Source> {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: key) { return Set(saved.compactMap(Source.init)) }
        guard defaults.object(forKey: "showHomeHero") == nil || defaults.bool(forKey: "showHomeHero") else { return [] }
        return [defaults.string(forKey: "homeHeroContent").flatMap(Source.init) ?? .trending]
    }

    static func isOn(_ source: Source) -> Bool { sources.contains(source) }

    /// The hero shows something: a source or a playlist.
    static var isEnabled: Bool { !sources.isEmpty || !HomePlaylistPins.pins(in: .hero).isEmpty }

    /// Only trending: the hero Home has always had, with no list to build.
    static var isTrendingOnly: Bool { sources == [.trending] && HomePlaylistPins.pins(in: .hero).isEmpty }

    static func set(_ source: Source, on: Bool) {
        let defaults = UserDefaults.standard
        // First explicit choice after the single-value era: replace the migrated pick
        // instead of stacking (Watchlist + Trending was the common upgrade footgun).
        if on, defaults.object(forKey: key) == nil {
            write([source])
            return
        }
        var current = sources
        if on { current.insert(source) } else { current.remove(source) }
        write(current)
    }

    /// Trending only, no playlists.
    static func reset() {
        write([.trending])
        HomePlaylistPins.removeAll(in: .hero)
    }

    private static func write(_ sources: Set<Source>) {
        let defaults = UserDefaults.standard
        defaults.set(Source.allCases.filter(sources.contains).map(\.rawValue), forKey: key)
        // Keep the pre-mix keys honest so iCloud / a profile without homeHeroSources
        // cannot revive an old single pick (e.g. Watchlist) after Trending was chosen.
        if sources.count == 1, let only = sources.first {
            defaults.set(only.rawValue, forKey: "homeHeroContent")
            defaults.set(true, forKey: "showHomeHero")
        } else if sources.isEmpty && HomePlaylistPins.pins(in: .hero).isEmpty {
            defaults.set(false, forKey: "showHomeHero")
        } else {
            defaults.set(true, forKey: "showHomeHero")
            defaults.removeObject(forKey: "homeHeroContent")
        }
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
}
