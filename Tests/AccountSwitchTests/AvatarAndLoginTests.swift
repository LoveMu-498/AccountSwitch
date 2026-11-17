import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import AccountSwitch

struct AvatarAndLoginTests {
    @Test func thumbnailDownsamplesARegularImage() throws {
        let thumbnail = try AvatarImageLoader.thumbnail(from: png(width: 1800, height: 60))
        #expect(thumbnail.width == 1200)
        #expect(thumbnail.height == 40)
    }

    @Test func thumbnailRejectsInvalidDataAndOversizeDimensions() throws {
        #expect(throws: AvatarImageLoader.Failure.unreadable) {
            try AvatarImageLoader.thumbnail(from: Data("not an image".utf8))
        }
        let wideImage = try png(width: 16_385, height: 1)
        #expect(throws: AvatarImageLoader.Failure.imageTooLarge) {
            try AvatarImageLoader.thumbnail(from: wideImage)
        }
    }

    @Test func pendingProviderImageRemainsReadableAfterUnlink() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AccountSwitchTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "avatar.png")
        try png(width: 32, height: 32).write(to: url)
        let file = try AvatarImageLoader.openImageFile(url)
        try FileManager.default.removeItem(at: url)
        let image = try await AvatarImageLoader.shared.load(from: file)
        #expect(image.width == 32)
        #expect(image.height == 32)
    }

    @Test func fileSizeIsCheckedBeforeLoading() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "AccountSwitchTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0]).write(to: url, options: .withoutOverwriting)
        let file = try FileHandle(forWritingTo: url)
        try file.truncate(atOffset: 32_000_001)
        try file.close()
        #expect(throws: AvatarImageLoader.Failure.fileTooLarge) {
            try AvatarImageLoader.openImageFile(url)
        }
    }

    @Test func dataBackedDropCanUseAFileRepresentation() async throws {
        let bytes = try png(width: 16, height: 8)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { complete in
            complete(bytes, nil)
            return nil
        }
        let file: FileHandle = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, error in
                continuation.resume(with: Result {
                    guard let url else { throw error ?? AvatarImageLoader.Failure.unreadable }
                    return try AvatarImageLoader.openImageFile(url)
                })
            }
        }
        let image = try await AvatarImageLoader.shared.load(from: file)
        #expect(image.width == 16)
        #expect(image.height == 8)
    }

    @Test func passwordCleanupDistinguishesEditsAndUnknownContents() {
        let written = "fixture-é"
        #expect(AppStoreLogin.passwordFieldValue(written, written: written) == .autofilled)
        #expect(AppStoreLogin.passwordFieldValue("", written: written) == .empty)
        #expect(AppStoreLogin.passwordFieldValue("fixture-e\u{301}", written: written) == .changed)
        #expect(AppStoreLogin.passwordFieldValue("user-edited", written: written) == .changed)
        #expect(AppStoreLogin.passwordFieldValue("•••", written: written) == .differentLengthMask)
        #expect(AppStoreLogin.passwordFieldValue(nil, written: written) == .unreadable)
    }

    @Test func nativePasswordMaskRequiresMatchingLengthAndNoInterveningInput() {
        let written = "fixture"
        let nativeMask = String(repeating: "\u{F79A}", count: written.utf16.count)
        let state = AppStoreLogin.passwordFieldValue(nativeMask, written: written)
        #expect(state == .matchingMask)
        #expect(AppStoreLogin.canClearPassword(state, inputUnchanged: true))
        #expect(!AppStoreLogin.canClearPassword(state, inputUnchanged: false))
        #expect(AppStoreLogin.passwordFieldValue(nativeMask + "\u{F79A}", written: written) == .differentLengthMask)
        #expect(!AppStoreLogin.canClearPassword(.unreadable, inputUnchanged: true))
        #expect(!AppStoreLogin.canClearPassword(.changed, inputUnchanged: true))
    }

    private func png(width: Int, height: Int) throws -> Data {
        let bitmap = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try #require(bitmap.makeImage())
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}
