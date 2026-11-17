import Foundation
import ImageIO

actor AvatarImageLoader {
    static let shared = AvatarImageLoader()

    private static let maximumBytes = 32_000_000
    private static let maximumSide = 16_384
    private static let maximumPixels = 64_000_000

    enum Failure: LocalizedError, Equatable {
        case unreadable
        case fileTooLarge
        case imageTooLarge

        var errorDescription: String? {
            switch self {
            case .unreadable: "无法读取这张图片，请换一张。"
            case .fileTooLarge: "头像图片不能超过 32 MB，请缩小文件后重试。"
            case .imageTooLarge: "头像图片尺寸过大，请缩小到 6400 万像素以内，且宽高均不超过 16384 像素。"
            }
        }
    }

    // Open within the item provider’s callback so its temporary file can be unlinked afterward.
    nonisolated static func openImageFile(_ url: URL) throws -> FileHandle {
        guard url.isFileURL else { throw Failure.unreadable }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else { throw Failure.unreadable }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, (metadata.st_mode & S_IFMT) == S_IFREG,
              metadata.st_size > 0 else { throw Failure.unreadable }
        guard metadata.st_size <= maximumBytes else { throw Failure.fileTooLarge }
        return file
    }

    func load(from url: URL) throws -> CGImage {
        try Task.checkCancellation()
        return try load(from: Self.openImageFile(url))
    }

    func load(from file: FileHandle) throws -> CGImage {
        defer { try? file.close() }
        try Task.checkCancellation()
        return try autoreleasepool {
            guard let data = try file.read(upToCount: Self.maximumBytes + 1) else {
                throw Failure.unreadable
            }
            try Task.checkCancellation()
            let image = try Self.thumbnail(from: data)
            try Task.checkCancellation()
            return image
        }
    }

    nonisolated static func thumbnail(from data: Data) throws -> CGImage {
        guard data.count <= maximumBytes else { throw Failure.fileTooLarge }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, width > 0,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, height > 0
        else { throw Failure.unreadable }
        guard width <= maximumSide, height <= maximumSide, width <= maximumPixels / height
        else { throw Failure.imageTooLarge }
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200
        ] as CFDictionary) else { throw Failure.unreadable }
        return thumbnail
    }
}
