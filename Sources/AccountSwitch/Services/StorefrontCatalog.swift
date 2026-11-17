import Foundation
import Observation

@MainActor
@Observable
final class StorefrontCatalog {
    static let shared = StorefrontCatalog()
    private let snapshot: [StorefrontRegion]
    private(set) var regions: [StorefrontRegion]
    private var lastRefresh: Date?
    private var refreshing = false

    private static let source = URL(string: "https://support.apple.com/en-us/118205")!
    private static let commonCodes = ["CN", "HK", "TW", "MO", "US", "JP", "KR", "SG", "GB", "CA", "AU"]

    private init() {
        let source = Bundle.main.url(forResource: "Storefronts", withExtension: "json")
            ?? Bundle.module.url(forResource: "Storefronts", withExtension: "json")
        if let source, let data = try? Data(contentsOf: source),
           let list = try? JSONDecoder().decode([StorefrontRegion].self, from: data) {
            snapshot = list
        } else {
            snapshot = []
        }
        regions = Self.sorted(snapshot)
    }

    func refreshIfNeeded() async {
        guard !refreshing, lastRefresh.map({ Date().timeIntervalSince($0) > 21_600 }) ?? true else { return }
        refreshing = true
        defer { refreshing = false }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: Self.source),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https", http.url?.host == "support.apple.com",
              data.count <= 1_500_000, !Task.isCancelled
        else { return }
        let names = Self.appStoreTerritories(in: data)
        // A partial or changed page must not replace the bundled list.
        guard names.count >= max(150, snapshot.count * 9 / 10),
              ["United States", "Japan", "China mainland", "United Kingdom"].allSatisfy(names.contains)
        else { return }

        let known = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.english, $0) })
        regions = Self.sorted(names.map { known[$0] ?? StorefrontRegion(name: $0, english: $0, code: nil) })
        lastRefresh = Date()
    }

    func regionCode(for name: String) -> String? {
        let matches = snapshot.filter { $0.isExactMatch(name) }
        return matches.count == 1 ? matches[0].code : nil
    }

    static func appStoreTerritories(in data: Data) -> [String] {
        guard let document = try? XMLDocument(data: data, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever]),
              let headings = try? document.nodes(forXPath: "//div[h3 and ul/li/p[normalize-space(.) = 'App Store']]/h3")
        else { return [] }
        var visited: Set<String> = []
        return headings.compactMap { heading in
            guard let title = heading.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty, title.count <= 100, visited.insert(title).inserted
            else { return nil }
            return title
        }
    }

    private static func sorted(_ list: [StorefrontRegion]) -> [StorefrontRegion] {
        let priority = Dictionary(uniqueKeysWithValues: commonCodes.enumerated().map { ($1, $0) })
        return list.sorted { left, right in
            let leftRank = priority[left.code ?? ""] ?? commonCodes.count
            let rightRank = priority[right.code ?? ""] ?? commonCodes.count
            if leftRank != rightRank { return leftRank < rightRank }
            return left.name.compare(right.name, locale: Locale(identifier: "zh-Hans")) == .orderedAscending
        }
    }
}
