import Foundation

struct StorefrontRegion: Decodable, Identifiable, Sendable {
    let name: String
    let english: String
    let code: String?

    var id: String { code ?? english }

    private static let shortcuts: [String: String] = [
        "AU": "澳区", "CA": "加区", "CN": "国区 中区 中国大陆",
        "GB": "英区 UK", "HK": "港区 香港", "JP": "日区", "KR": "韩区 韩国",
        "MO": "澳門 澳门区", "SG": "新加坡区 新区", "TW": "台区 台灣",
        "US": "美区 USA", "DE": "德区", "FR": "法区"
    ]

    func matches(_ query: String) -> Bool {
        let names = [name, english, Self.shortcuts[code ?? ""] ?? ""]
        return code?.caseInsensitiveCompare(query) == .orderedSame ||
            names.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    func isExactMatch(_ query: String) -> Bool {
        let aliases = (Self.shortcuts[code ?? ""] ?? "").split(separator: " ").map(String.init)
        return ([name, english, code ?? ""] + aliases).contains {
            $0.compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }
}
