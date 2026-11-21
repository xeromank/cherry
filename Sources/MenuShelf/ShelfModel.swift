import SwiftUI

enum ShelfScope: CaseIterable {
    case hidden
    case all

    var title: String {
        switch self {
        case .hidden: "가려짐"
        case .all: "전체"
        }
    }
}

enum ShelfSearch {
    static func matches(_ query: String, in fields: [String]) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        return terms.allSatisfy { term in
            fields.contains { $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil }
        }
    }
}

@MainActor
final class ShelfModel: ObservableObject {
    @Published var isTrusted = false
    @Published var hasNotch = false
    @Published var hotKeyAvailable = false
    @Published var isScanning = false
    @Published var isPinning = false
    @Published var items: [StatusItem] = []
    @Published var scope: ShelfScope = .hidden
    @Published var query = ""
    @Published var selectedID: String?
    @Published var focusRequest = 0
    @Published var feedback: String?

    var results: [StatusItem] {
        items.filter { item in
            (scope == .all || item.isHidden) && ShelfSearch.matches(query, in: [item.title, item.appName])
        }
    }

    var selectedItem: StatusItem? {
        let results = results
        return results.first { $0.id == selectedID } ?? results.first
    }

    func reset() {
        scope = hasNotch ? .hidden : .all
        query = ""
        selectedID = nil
        feedback = nil
    }

    func reconcileSelection() {
        selectedID = selectedItem?.id
    }

    func moveSelection(by offset: Int) {
        let results = results
        guard !results.isEmpty else { return }
        let current = results.firstIndex { $0.id == selectedID } ?? (offset < 0 ? results.count : -1)
        let next = (current + offset + results.count) % results.count
        selectedID = results[next].id
    }
}
