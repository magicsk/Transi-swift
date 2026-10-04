//
//  TicketCatalogueProvider.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import Foundation

/// The IDS BK ticket catalogue, cached in Application Support and checked for changes at most once a day.
class TicketCatalogueProvider: ObservableObject {
    @Published private(set) var catalogue: TicketCatalogue?
    @Published private(set) var isLoading = false
    /// Nothing cached and the last fetch failed.
    @Published private(set) var loadFailed = false
    /// When the catalogue was last confirmed current. Main thread only.
    private var checkedAt: Date?

    private static let refreshInterval: TimeInterval = 24 * 60 * 60
    private static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ticket_types.json")
    }()

    /// Publishes the cached catalogue, then refreshes it when the cache is a day old. Call on the main thread.
    func load() {
        guard !isLoading else { return }
        if let checkedAt, Date().timeIntervalSince(checkedAt) < Self.refreshInterval { return }
        isLoading = true
        loadFailed = false
        DispatchQueue.global(qos: .utility).async {
            let path = Self.fileURL.path
            let cached = FileManager.default.contents(atPath: path)
                .flatMap { try? JSONDecoder().decode(TicketCatalogue.self, from: $0) }
            // The file's modification date records the last check.
            let cachedAt = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
            let isFresh = cachedAt.map { Date().timeIntervalSince($0) < Self.refreshInterval } ?? false
            DispatchQueue.main.async {
                if let cached { self.catalogue = cached }
                if cached != nil, isFresh {
                    self.checkedAt = cachedAt
                    self.isLoading = false
                }
            }
            guard cached == nil || !isFresh else { return }

            let pathSegment = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let cacheKey = cached?.cacheKey?.addingPercentEncoding(withAllowedCharacters: pathSegment) ?? "null"
            fetchBApi(endpoint: "/mobile/v1/ticket/types/\(cacheKey)", type: TicketCatalogue.self) { result in
                self.isLoading = false
                switch result {
                case .success(let fetched) where fetched.tickets != nil && fetched.zones != nil:
                    self.catalogue = fetched
                    self.checkedAt = Date()
                    DispatchQueue.global(qos: .utility).async {
                        try? JSONEncoder().encode(fetched).write(to: Self.fileURL)
                    }
                case .success(let fetched) where cached?.isConfirmed(by: fetched) == true:
                    // Only the cached key came back: the cached copy is current. Anything else keeps it unconfirmed.
                    self.checkedAt = Date()
                    DispatchQueue.global(qos: .utility).async {
                        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: path)
                    }
                default:
                    self.loadFailed = self.catalogue == nil
                }
            }
        }
    }
}
