// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

import XCTest
@testable import Rivulet

final class FolderRoutingTests: XCTestCase {
    private func plex(_ type: String, agent: String?) -> MediaLibrary {
        let section = PlexLibrary(key: "1", type: type, title: "L", agent: agent, scanner: nil, language: nil,
                                  uuid: "u", updatedAt: nil, createdAt: nil, scannedAt: nil, Location: nil)
        return PlexMediaMapper.library(section, providerID: "plex")
    }

    private func jellyfin(_ collectionType: String?, _ content: HomeVideosContent = .videos) -> MediaLibrary? {
        let type = collectionType.map { #""CollectionType":"\#($0)","# } ?? ""
        let view: JFItem = JellyfinFixtures.decode(#"{"Id":"v","Name":"V",\#(type)"Type":"CollectionFolder"}"#)
        return JellyfinMediaMapper.library(view, providerID: "jf", homeVideos: content)
    }

    func test_plexMovieSection_noneAgent_browsesByFolder() {
        XCTAssertTrue(plex("movie", agent: "tv.plex.agents.none").browsesByFolder)
        XCTAssertTrue(plex("show", agent: "com.plexapp.agents.none").browsesByFolder)
        XCTAssertFalse(plex("movie", agent: "tv.plex.agents.movie").browsesByFolder)
        XCTAssertFalse(plex("photo", agent: "com.plexapp.agents.none").browsesByFolder)
    }

    func test_jellyfinMixed_usesPosterLibrary() {
        let library = jellyfin(nil)
        XCTAssertEqual(library?.kind, .mixed)
        XCTAssertEqual(library?.browsesByFolder, false)
        XCTAssertEqual(jellyfin("mixed")?.browsesByFolder, false)
        XCTAssertEqual(jellyfin("folders")?.browsesByFolder, false)
        XCTAssertEqual(jellyfin("movies")?.browsesByFolder, false)
    }

    func test_jellyfinHomeVideos_withVideos_usesPosterLibrary() {
        let library = jellyfin("homevideos", .videos)
        XCTAssertEqual(library?.kind, .mixed)
        XCTAssertEqual(library?.browsesByFolder, false)
    }

    func test_jellyfinHomeVideos_photosOnly_isPhotos() {
        let library = jellyfin("homevideos", .photosOnly)
        XCTAssertEqual(library?.kind, .photos)
        XCTAssertEqual(library?.browsesByFolder, false)
    }
}
