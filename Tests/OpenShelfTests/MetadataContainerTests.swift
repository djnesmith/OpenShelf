import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import OpenShelf

/// Metadata › Clean against metadata ImageIO's properties don't show, in
/// files made here: C2PA, PNG text chunks, JPEG APP segments, GIF comments.
struct MetadataContainerTests {
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-containers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A Display P3 picture with a gradient, so the profile and the pixels can be checked.
    static func image() -> CGImage {
        let context = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.displayP3)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<40 {
            context.setFillColor(red: CGFloat(x) / 40, green: 0.5, blue: 0.8, alpha: 1)
            context.fill(CGRect(x: x, y: 0, width: 1, height: 30))
        }
        return context.makeImage()!
    }

    static func encode(_ type: UTType, properties: [CFString: Any] = [:]) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image(), properties as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func pngChunk(_ type: String, _ body: Data) -> Data {
        func be(_ n: UInt32) -> Data { Data([UInt8(n >> 24), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff)]) }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in Data(type.utf8) + body {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (0xEDB8_8320 & (0 &- (crc & 1))) }
        }
        return be(UInt32(body.count)) + Data(type.utf8) + body + be(crc ^ 0xFFFF_FFFF)
    }

    static func jpegSegment(_ marker: UInt8, _ body: String) -> Data {
        let body = Data(body.utf8)
        return Data([0xFF, marker, UInt8((body.count + 2) >> 8), UInt8((body.count + 2) & 0xff)]) + body
    }

    /// RGBA8 sRGB pixels of the image as it shows (orientation applied).
    static func pixels(_ url: URL) throws -> [UInt8] {
        let image = try EditableImage.load(url).cgImage
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    static func profileName(_ url: URL) -> String? {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyProfileName] as? String
    }

    /// The case this fixes: a PNG with Content Credentials and text comments,
    /// cleaned with "keep orientation and profile" on.
    @Test func pngLosesC2PAAndTextButKeepsProfileAndPixels() throws {
        var png = Self.encode(.png)
        let extras = Self.pngChunk("caBX", Data("jumbc2pa.manifest".utf8)) + Self.pngChunk("tEXt", Data("Comment\0secret".utf8))
            + Self.pngChunk("iTXt", Data("Description\0\0\0\0\0secret".utf8)) + Self.pngChunk("zTXt", Data("Author\0\0".utf8) + Data([0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]))
        png.insert(contentsOf: extras, at: png.count - 12)
        let url = try Self.directory().appendingPathComponent("Shot.png")
        try png.write(to: url)
        #expect(MetadataStripper.leftoverMetadata(at: url) == ["Content Credentials (C2PA)", "text comments"])
        #expect(MetadataStripper.hasIdentifyingMetadata(at: url))

        let clean = try MetadataStripper.strip(try EditableImage.load(url), keepsOrientationAndProfile: true)
        let bytes = try Data(contentsOf: clean)
        for leftover in ["caBX", "tEXt", "iTXt", "zTXt", "secret", "c2pa"] {
            #expect(bytes.range(of: Data(leftover.utf8)) == nil, "\(leftover)")
        }
        #expect(MetadataStripper.leftoverMetadata(at: clean).isEmpty)
        #expect(Self.profileName(clean) == Self.profileName(url))
        #expect(Self.profileName(clean)?.contains("P3") == true)
        // Re-encoding a PNG is lossless: the same pixels.
        #expect(try Self.pixels(clean) == Self.pixels(url))
    }

    /// Orientation is kept: the cleaned PNG shows the same way up.
    @Test func pngKeepsItsOrientation() throws {
        var png = Self.encode(.png, properties: [kCGImagePropertyOrientation: 6])
        png.insert(contentsOf: Self.pngChunk("tEXt", Data("Comment\0secret".utf8)), at: png.count - 12)
        let url = try Self.directory().appendingPathComponent("Turned.png")
        try png.write(to: url)
        let clean = try MetadataStripper.strip(try EditableImage.load(url), keepsOrientationAndProfile: true)
        #expect(try EditableImage.load(clean).cgImage.width == EditableImage.load(url).cgImage.width)
        #expect(try Self.pixels(clean) == Self.pixels(url))
        #expect(MetadataStripper.leftoverMetadata(at: clean).isEmpty)
    }

    /// JPEG: C2PA, XMP, IPTC and a comment go, and the image data is copied, not re-encoded.
    @Test func jpegLosesItsSegmentsAndStaysLossless() throws {
        var jpeg = Self.encode(.jpeg)
        let extras = Self.jpegSegment(0xE1, "http://ns.adobe.com/xap/1.0/\0<x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'><rdf:Description xmlns:dc='http://purl.org/dc/elements/1.1/' dc:creator='secret'/></rdf:RDF></x:xmpmeta>")
            + Self.jpegSegment(0xEB, "JP\0\0\0\0\0\u{1}jumbjumdc2pa") + Self.jpegSegment(0xED, "Photoshop 3.0\0secret") + Self.jpegSegment(0xFE, "secret")
        jpeg.insert(contentsOf: extras, at: 2)
        let url = try Self.directory().appendingPathComponent("Shot.jpg")
        try jpeg.write(to: url)
        // (The Photoshop IPTC segment is ImageIO's to report; it does, as IPTC.)
        #expect(MetadataContainers.leftovers(in: jpeg) == ["Content Credentials (C2PA)", "comment"])

        let clean = try MetadataStripper.strip(try EditableImage.load(url), keepsOrientationAndProfile: true)
        let bytes = try Data(contentsOf: clean)
        #expect(bytes.range(of: Data("secret".utf8)) == nil)
        #expect(bytes.range(of: Data("c2pa".utf8)) == nil)
        #expect(MetadataStripper.leftoverMetadata(at: clean).isEmpty)
        // The compressed image data is the original's, byte for byte.
        func scan(_ data: Data) -> Data { data[data.range(of: Data([0xFF, 0xDA]))!.lowerBound...] }
        #expect(scan(bytes) == scan(jpeg))
    }

    @Test func gifLosesItsComment() throws {
        var gif = Self.encode(.gif)
        gif.insert(contentsOf: Data([0x21, 0xFE, 6]) + Data("secret".utf8) + Data([0]), at: gif.count - 1)
        #expect(MetadataContainers.leftovers(in: gif) == ["comment"])
        let url = try Self.directory().appendingPathComponent("Anim.gif")
        try gif.write(to: url)
        let clean = try MetadataStripper.strip(try EditableImage.load(url), keepsOrientationAndProfile: true)
        #expect(try Data(contentsOf: clean).range(of: Data("secret".utf8)) == nil)
        #expect(MetadataStripper.leftoverMetadata(at: clean).isEmpty)
    }

    /// TIFF keeps text tags in a lossless copy; ImageIO's check sees them, and the copy is re-encoded.
    @Test func tiffLosesItsTextTags() throws {
        let tiff = Self.encode(.tiff, properties: [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFImageDescription: "secret", kCGImagePropertyTIFFArtist: "secret"]])
        let url = try Self.directory().appendingPathComponent("Scan.tiff")
        try tiff.write(to: url)
        let clean = try MetadataStripper.strip(try EditableImage.load(url), keepsOrientationAndProfile: true)
        let bytes = try Data(contentsOf: clean)
        #expect(bytes.range(of: Data("secret".utf8)) == nil)
        #expect(try Self.pixels(clean) == Self.pixels(url))
    }

    /// The byte check finds what ImageIO doesn't show, and passes what is only about the pixels.
    @Test func byteCheckNamesWhatIsLeft() {
        var png = Self.encode(.png)
        #expect(MetadataContainers.leftovers(in: png).isEmpty)
        png.insert(contentsOf: Self.pngChunk("tIME", Data(repeating: 0, count: 7)) + Self.pngChunk("abCd", Data()), at: png.count - 12)
        #expect(MetadataContainers.leftovers(in: png) == ["modification time", "PNG abCd chunk"])
        var jpeg = Self.encode(.jpeg)
        #expect(MetadataContainers.leftovers(in: jpeg).isEmpty)
        jpeg.insert(contentsOf: Self.jpegSegment(0xE2, "MPF\0") + Self.jpegSegment(0xE5, "x") + Self.jpegSegment(0xEB, "other"), at: 2)
        #expect(MetadataContainers.leftovers(in: jpeg) == ["embedded images (MPF)", "APP5 data", "APP11 data"])
        #expect(MetadataContainers.leftovers(in: Self.encode(.tiff)).isEmpty)
        let tiff = Self.encode(.tiff, properties: [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFImageDescription: "x", kCGImagePropertyTIFFCopyright: "y"]])
        #expect(MetadataContainers.leftovers(in: tiff) == ["image description", "copyright"])
        #expect(MetadataContainers.leftovers(in: Data("not an image".utf8)).isEmpty)
    }
}
