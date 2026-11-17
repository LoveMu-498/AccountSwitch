import SwiftUI

struct StorefrontPicker: View {
    @Binding var region: String
    @Binding var regionCode: String?
    private let catalog = StorefrontCatalog.shared
    @State private var expanded = false
    @State private var query = ""
    @FocusState private var searching: Bool

    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var matches: [StorefrontRegion] {
        let term = searchTerm
        guard !term.isEmpty else { return catalog.regions }
        let matching = catalog.regions.filter { $0.matches(term) }
        return matching.filter { $0.isExactMatch(term) } + matching.filter { !$0.isExactMatch(term) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                query = ""
                expanded.toggle()
            } label: {
                HStack(spacing: 9) {
                    StorefrontFlag(code: regionCode ?? catalog.regionCode(for: region))
                    Text(region.isEmpty ? "选择国家与地区" : region)
                        .foregroundStyle(region.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("国家与地区")
            .accessibilityValue(region.isEmpty ? "未选择" : region)
            .accessibilityHint(expanded ? "收起地区列表" : "展开地区列表")

            if expanded {
                searchPanel
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.quaternary)
                            .allowsHitTesting(false)
                    }
                    .task {
                        searching = true
                        await catalog.refreshIfNeeded()
                    }
                    .onExitCommand { expanded = false }
            }
        }
    }

    private var searchPanel: some View {
        let term = searchTerm
        let results = matches
        let hasExactMatch = results.contains { $0.isExactMatch(term) }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索地区或输入自定义名称", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searching)
                    .onSubmit {
                        let exact = results.filter { $0.isExactMatch(term) }
                        if exact.count == 1, let item = exact.first { select(item.name, code: item.code) }
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(12)
            Divider()

            if results.isEmpty {
                Text(term.isEmpty ? "国家与地区列表不可用" : "没有匹配的国家或地区")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(results) { option in
                            let selected = (regionCode != nil && regionCode == option.code) || region == option.name
                            Button {
                                select(option.name, code: option.code)
                            } label: {
                                HStack(spacing: 8) {
                                    StorefrontFlag(code: option.code)
                                    Text(option.name).lineLimit(1)
                                    Spacer()
                                    if let code = option.code {
                                        Text(code).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityHidden(true)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                    .padding(5)
                }
                .frame(height: min(186, CGFloat(results.count) * 28 + 10))
            }

            if !term.isEmpty && !hasExactMatch {
                Divider()
                optionButton("使用自定义地区「\(term)」", icon: "pencil.line") { select(term, code: nil) }
            } else if term.isEmpty && !region.isEmpty {
                Divider()
                optionButton("清除地区", icon: "xmark.circle") { select("", code: nil) }
            }
        }
    }

    private func optionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ name: String, code: String?) {
        region = name
        regionCode = code
        expanded = false
    }
}
