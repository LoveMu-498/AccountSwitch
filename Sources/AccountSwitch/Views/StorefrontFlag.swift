import SwiftUI

struct StorefrontFlag: View {
    let code: String?

    var body: some View {
        Group {
            if code == "TW" {
                taiwanFlag
            } else if let flag = Self.emoji(for: code) {
                Text(flag)
            } else {
                Image(systemName: "globe").foregroundStyle(.secondary)
            }
        }
        .frame(width: 18)
        .accessibilityHidden(true)
    }

    // Some Macs render the TW flag sequence as a missing glyph.
    private var taiwanFlag: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.87, green: 0.04, blue: 0.10)))
            context.fill(Path(CGRect(x: 0, y: 0, width: 8, height: 5.5)),
                         with: .color(Color(red: 0.08, green: 0.19, blue: 0.48)))
            let sun = Path { path in
                for point in 0..<24 {
                    let angle = Double(point) * .pi / 12 - .pi / 2
                    let radius = point.isMultiple(of: 2) ? 2.0 : 1.25
                    let vertex = CGPoint(x: 4 + cos(angle) * radius, y: 2.75 + sin(angle) * radius)
                    if point == 0 { path.move(to: vertex) } else { path.addLine(to: vertex) }
                }
                path.closeSubpath()
            }
            context.fill(sun, with: .color(.white))
        }
        .frame(width: 16, height: 11)
        .clipShape(.rect(cornerRadius: 1))
    }

    private static func emoji(for code: String?) -> String? {
        guard let code, code.utf8.count == 2,
              code.utf8.allSatisfy({ (65...90).contains($0) })
        else { return nil }
        let scalars = code.utf8.compactMap { Unicode.Scalar(0x1F1E6 + Int($0) - 65) }
        return String(String.UnicodeScalarView(scalars))
    }
}
