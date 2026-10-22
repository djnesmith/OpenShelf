import CoreGraphics
import Foundation
import ImageIO

/// App and file icons from an image: a macOS .icns and a Windows .ico, each
/// holding the sizes those systems pick from.
enum IconMaker {
    static let icnsSizes = [16, 32, 64, 128, 256, 512, 1024]
    static let icoSizes = [16, 32, 48, 256]
    /// The iconset's points and scales, as iconutil expects them.
    static let iconsetEntries: [(points: Int, scale: Int)] = [16, 32, 128, 256, 512].flatMap { [($0, 1), ($0, 2)] }

    /// Saves "<name>.icns" and "<name>.ico" beside the image.
    static func make(_ url: URL) async throws -> [URL] {
        let image = try EditableImage.load(url).cgImage
        let icns = OutputNaming.destination(for: url, pathExtension: "icns")
        try await writeICNS(image, to: icns)
        let ico = OutputNaming.destination(for: url, pathExtension: "ico")
        try write(image, sizes: icoSizes, type: "com.microsoft.ico", to: ico)
        return [icns, ico]
    }

    /// ImageIO's ICNS writer drops some sizes, so this goes the way Xcode's
    /// icons do: an .iconset folder through macOS's iconutil.
    static func writeICNS(_ image: CGImage, to url: URL) async throws {
        try SaveError.checkWritable(url)
        let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-\(UUID().uuidString).iconset", isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }
        for entry in iconsetEntries {
            guard let square = square(image, side: entry.points * entry.scale) else { throw EditableImageError.unwritable(url) }
            let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
            try EditableImage.write(square, to: iconset.appendingPathComponent(name), type: .png)
        }
        try await PartialFile.write(url) { partial in
            try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/iconutil"), ["-c", "icns", iconset.path, "-o", partial.path])
        }
    }

    static func write(_ image: CGImage, sizes: [Int], type: String, to url: URL) throws {
        try SaveError.checkWritable(url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type as CFString, sizes.count, nil) else {
            throw SaveError.diagnose(url)
        }
        for side in sizes {
            guard let square = square(image, side: side) else { throw EditableImageError.unwritable(url) }
            CGImageDestinationAddImage(destination, square, nil)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw SaveError.diagnose(url)
        }
    }

    /// `image` fitted inside a `side`-pixel square, centred on transparency.
    static func square(_ image: CGImage, side: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        let scale = Double(side) / Double(max(image.width, image.height))
        let width = Double(image.width) * scale, height = Double(image.height) * scale
        context.draw(image, in: CGRect(x: (Double(side) - width) / 2, y: (Double(side) - height) / 2, width: width, height: height))
        return context.makeImage()
    }
}

/// Animated PNG from a GIF, with each frame's timing and the loop kept.
enum AnimatedPNG {
    static func write(gif source: URL, to url: URL) throws {
        guard let images = CGImageSourceCreateWithURL(source as CFURL, nil), CGImageSourceGetCount(images) > 0 else {
            throw ConversionError.unreadable(source)
        }
        let count = CGImageSourceGetCount(images)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, count, nil) else {
            throw SaveError.diagnose(url)
        }
        let loopCount = GIFLoop.loopCount(of: source) ?? 0
        CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: loopCount]] as CFDictionary)
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(images, index, nil) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(images, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1
            CGImageDestinationAddImage(destination, frame, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw SaveError.diagnose(url)
        }
    }
}
