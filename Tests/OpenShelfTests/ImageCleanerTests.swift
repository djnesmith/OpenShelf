import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OpenShelf

/// Clean an image (ROADMAP E6): the fill, the metadata removed, and the report.
struct ImageCleanerTests {
    /// A flat field of `gray` with a black stamp at `stamp`.
    static func field(width: Int = 100, height: Int = 80, gray: UInt8 = 180, stamp: CGRect) -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let inStamp = stamp.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
                let value: UInt8 = inStamp ? 0 : gray
                pixels.replaceSubrange((y * width + x) * 4..<(y * width + x) * 4 + 4, with: [value, value, value, 255])
            }
        }
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> UInt8 {
        var buffer = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &buffer, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CGContext is y-up; draw so (x, y) from the top lands on the one pixel.
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return buffer[0]
    }

    /// The stamp's pixels are gone and the area matches its surround.
    @Test func theFillBlendsAStampIntoAFlatField() {
        let stamp = CGRect(x: 60, y: 50, width: 25, height: 12)
        let image = Self.field(stamp: stamp)
        #expect(Self.pixel(image, 70, 55) == 0)
        let filled = ImageFill.fill(image, areas: [stamp])!
        for (x, y) in [(60, 50), (72, 56), (84, 61)] {
            #expect(abs(Int(Self.pixel(filled, x, y)) - 180) <= 2, "(\(x), \(y))")
        }
        // Outside the area nothing changes.
        #expect(Self.pixel(filled, 5, 5) == 180)
    }

    /// Around a curved surround the fill is smooth: each pixel is the average of its
    /// neighbours (a Laplace fill), not just a blend between the edges.
    @Test func theFillIsSmoothAgainstACurvedEdge() {
        let width = 60, height = 40
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = UInt8(min(40 + (x * x) / 18, 255))
                pixels.replaceSubrange((y * width + x) * 4..<(y * width + x) * 4 + 4, with: [value, value, value, 255])
            }
        }
        let area = (x0: 20, y0: 10, x1: 45, y1: 30)
        ImageFill.fill(&pixels, width: width, height: height, x0: area.x0, y0: area.y0, x1: area.x1, y1: area.y1)
        func at(_ x: Int, _ y: Int) -> Int { Int(pixels[(y * width + x) * 4]) }
        var worst = 0
        for y in area.y0..<area.y1 {
            for x in area.x0..<area.x1 {
                let average = (at(x - 1, y) + at(x + 1, y) + at(x, y - 1) + at(x, y + 1)) / 4
                worst = max(worst, abs(at(x, y) - average))
            }
        }
        #expect(worst <= 2)
    }

    /// Next to a bright edge the fill stays close to it, as the smooth (Laplace) solution
    /// does; a plain blend between opposite edges would be half as bright there.
    @Test func theFillFollowsTheNearestEdge() {
        let width = 40, height = 40
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        // Bright only along the column left of the area.
        for y in 0..<height { pixels.replaceSubrange((y * width + 4) * 4..<(y * width + 4) * 4 + 4, with: [255, 255, 255, 255]) }
        ImageFill.fill(&pixels, width: width, height: height, x0: 5, y0: 5, x1: 35, y1: 35)
        #expect(pixels[(20 * width + 7) * 4] > 150)
    }

    /// The fill also goes through Redact's new Fill look.
    @Test func redactsFillLookIsTheSameFill() {
        let stamp = CGRect(x: 10, y: 10, width: 8, height: 8)
        let filled = Redaction.apply(to: Self.field(stamp: stamp), areas: [(rect: stamp, look: RedactionLook(style: .fill, strength: 50))])!
        #expect(abs(Int(Self.pixel(filled, 13, 13)) - 180) <= 2)
    }

    static func fixture(_ type: UTType, properties: [CFString: Any], in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("photo.\(type.preferredFilenameExtension!)")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, Self.field(stamp: CGRect(x: 70, y: 60, width: 20, height: 10)), properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func aJPEGLosesItsMetadataAndTheReportSaysWhat() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clean-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try Self.fixture(.jpeg, properties: [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Canon", kCGImagePropertyTIFFModel: "EOS R5"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "RF 50mm", kCGImagePropertyExifISOSpeedRatings: [100]],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCaptionAbstract: "Secret", kCGImagePropertyIPTCByline: ["Me"]],
        ], in: folder)
        let image = try EditableImage.load(url)
        let result = try ImageCleaner.clean(image, areas: [CGRect(x: 70, y: 60, width: 20, height: 10)])
        #expect(result.url.lastPathComponent == "photo Clean.jpeg" || result.url.lastPathComponent == "photo Clean.jpg")
        #expect(MetadataStripper.leftoverMetadata(at: result.url).isEmpty)
        #expect(result.report.hasPrefix("Removed: EXIF (Canon, EOS R5, RF 50mm), GPS location, IPTC (caption, creator)"))
        #expect(result.report.contains("filled 1 marked area (bottom right, 20×10 px)"))
        #expect(result.report.hasSuffix("Pixel-embedded marks, if any, are untouched."))
        // The stamp is gone from the saved copy.
        let saved = try EditableImage.load(result.url).cgImage
        #expect(Self.pixel(saved, 78, 64) > 150)
        // The original is never touched.
        #expect(ImageCleaner.metadata(in: url).contains("GPS location"))
    }

    @Test func aPNGsTextChunksGoToo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("clean-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try Self.fixture(.png, properties: [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "made by me"]], in: folder)
        #expect(ImageCleaner.metadata(in: url).contains("text comments"))
        let result = try ImageCleaner.clean(try EditableImage.load(url), areas: [])
        #expect(MetadataContainers.leftovers(in: try Data(contentsOf: result.url)).isEmpty)
        #expect(result.report.contains("text comments"))
        #expect(!result.report.contains("filled"))
    }

    @Test func reportsWhereEachAreaIs() {
        let size = CGSize(width: 300, height: 300)
        #expect(ImageCleaner.place(of: CGRect(x: 250, y: 250, width: 10, height: 10), in: size) == "bottom right")
        #expect(ImageCleaner.place(of: CGRect(x: 140, y: 140, width: 10, height: 10), in: size) == "middle")
        #expect(ImageCleaner.place(of: CGRect(x: 10, y: 140, width: 10, height: 10), in: size) == "left")
        #expect(ImageCleaner.place(of: CGRect(x: 140, y: 10, width: 10, height: 10), in: size) == "top")
        #expect(ImageCleaner.report(removed: [], areas: [], imageSize: size) == "No metadata was found to remove. Pixel-embedded marks, if any, are untouched.")
    }
}
