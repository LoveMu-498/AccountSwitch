import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

struct AccountAvatar: View {
    let profile: AccountProfile
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.12))
            if let data = profile.avatarData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let emoji = profile.avatarEmoji {
                Text(emoji).font(.system(size: size * 0.58))
            } else if !profile.region.isEmpty,
                      let code = profile.regionCode ?? StorefrontCatalog.shared.regionCode(for: profile.region) {
                Text(code)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "person.fill").foregroundStyle(Color.accentColor)
            }
        }
        .font(.system(size: size * 0.48))
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    nonisolated static func loadImage(from data: Data) -> CGImage? {
        try? AvatarImageLoader.thumbnail(from: data)
    }

    static func encodeCrop(_ image: CGImage, rect: CGRect) -> Data? {
        guard let cropped = image.cropping(to: rect),
              let bitmap = CGContext(data: nil, width: 160, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        bitmap.interpolationQuality = .high
        bitmap.draw(cropped, in: CGRect(x: 0, y: 0, width: 160, height: 160))
        guard let scaled = bitmap.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, scaled, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
