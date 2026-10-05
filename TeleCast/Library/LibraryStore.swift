import Foundation
import Observation
import CastCore

struct LibraryEntry: Codable, Identifiable, Hashable {
    var url: URL
    var title: String
    var date: Date

    var id: String { url.absoluteString }
}

struct LibraryData: Codable {
    var favorites: [LibraryEntry] = []
    var history: [LibraryEntry] = []
}

/// Favourites and recent pages.
@MainActor
@Observable
final class LibraryStore {
    private(set) var favorites: [LibraryEntry] = []
    private(set) var history: [LibraryEntry] = []
    @ObservationIgnored private let store = JSONFileStore(
        url: JSONFileStore<LibraryData>.applicationSupportURL(named: "library"), defaultValue: LibraryData())

    static let historyLimit = 50

    init() {
        let data = store.load()
        favorites = data.favorites
        history = data.history
    }

    func isFavorite(_ url: URL?) -> Bool {
        guard let url else { return false }
        return favorites.contains { $0.url == url }
    }

    func toggleFavorite(url: URL, title: String) {
        if let index = favorites.firstIndex(where: { $0.url == url }) {
            favorites.remove(at: index)
        } else {
            favorites.insert(LibraryEntry(url: url, title: title.isEmpty ? (url.host ?? url.absoluteString) : title,
                                          date: Date()), at: 0)
        }
        save()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        save()
    }

    func addHistory(url: URL, title: String) {
        history.removeAll { $0.url == url }
        history.insert(LibraryEntry(url: url, title: title.isEmpty ? (url.host ?? url.absoluteString) : title,
                                    date: Date()), at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
        save()
    }

    func clearHistory() {
        history.removeAll()
        save()
    }

    private func save() {
        store.save(LibraryData(favorites: favorites, history: history))
    }
}
