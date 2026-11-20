import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Clean an image (ROADMAP E6, David: "should remove non-hidden and hidden ones that the
/// same time, it should report back what it removed"): the marked areas filled to blend
/// in, every metadata container dropped by re-encoding the pixels, the copy's own bytes
/// checked, and a report of what was removed that never claims more than was done.
enum ImageCleaner {
    struct Result {
        var url: URL
        var report: String
    }

    /// Saves "<name> Clean.<ext>" beside `image` with `areas` filled and no metadata.
    static func clean(_ image: EditableImage, areas: [CGRect]) throws -> Result {
        let found = metadata(in: image.url)
        if let source = CGImageSourceCreateWithURL(image.url as CFURL, nil), CGImageSourceGetCount(source) > 1 {
            // Animations and multi-page TIFFs keep every frame; areas are for still images.
            guard areas.isEmpty else { throw CleanError.areasNeedAStillImage(image.url.lastPathComponent) }
            let url = try MetadataStripper.strip(image, keepsOrientationAndProfile: false)
            return Result(url: url, report: report(removed: found, areas: [], imageSize: CGSize(width: image.cgImage.width, height: image.cgImage.height)))
        }
        var pixels = image.cgImage
        if !areas.isEmpty { pixels = ImageFill.fill(pixels, areas: areas) ?? pixels }
        let type = EditableImage.writableTypes.contains(image.type) ? image.type : .png
        let url = OutputNaming.destination(for: image.url, suffix: MetadataSuffix.removed, pathExtension: image.pathExtension(for: type))
        try EditableImage.write(pixels, to: url, type: type, quality: 0.95, metadata: [:])
        let leftovers = MetadataStripper.leftoverMetadata(at: url)
        guard leftovers.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            throw MetadataStripper.StripError.couldNotRemove(file: image.url.lastPathComponent, fields: leftovers)
        }
        return Result(url: url, report: report(removed: found, areas: areas, imageSize: CGSize(width: pixels.width, height: pixels.height)))
    }

    enum CleanError: LocalizedError {
        case areasNeedAStillImage(String)

        var errorDescription: String? {
            switch self {
            case .areasNeedAStillImage(let name): "\(name) has several frames; marked areas can only be filled on a still image."
            }
        }
    }

    /// What metadata the file holds, by name, as the report says it: from ImageIO's
    /// properties and from the file's own bytes (C2PA, text chunks, comments).
    static func metadata(in url: URL) -> [String] {
        var found: [String] = []
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any], !exif.isEmpty {
                let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
                let camera = [tiff[kCGImagePropertyTIFFMake], tiff[kCGImagePropertyTIFFModel], exif[kCGImagePropertyExifLensModel]].compactMap { $0 as? String }
                found.append(camera.isEmpty ? "EXIF" : "EXIF (\(camera.joined(separator: ", ")))")
            }
            if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any], !gps.isEmpty { found.append("GPS location") }
            if let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any], !iptc.isEmpty {
                var parts: [String] = []
                if iptc[kCGImagePropertyIPTCCaptionAbstract] != nil { parts.append("caption") }
                if iptc[kCGImagePropertyIPTCByline] != nil || iptc[kCGImagePropertyIPTCCreatorContactInfo] != nil { parts.append("creator") }
                found.append(parts.isEmpty ? "IPTC" : "IPTC (\(parts.joined(separator: ", ")))")
            }
            if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               tiff[kCGImagePropertyTIFFArtist] != nil || tiff[kCGImagePropertyTIFFSoftware] != nil || tiff[kCGImagePropertyTIFFCopyright] != nil {
                found.append("TIFF tags (artist, software or copyright)")
            }
            if properties[kCGImagePropertyMakerAppleDictionary] != nil || properties[kCGImagePropertyMakerCanonDictionary] != nil
                || properties[kCGImagePropertyMakerNikonDictionary] != nil {
                found.append("maker notes")
            }
            if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil), let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag],
               tags.contains(where: { (CGImageMetadataTagCopyNamespace($0) as String?)?.contains("xmp") == true || (CGImageMetadataTagCopyPrefix($0) as String?) == "xmp" || (CGImageMetadataTagCopyPrefix($0) as String?) == "dc" }) {
                found.append("XMP")
            }
        }
        if let data = try? Data(contentsOf: url, options: .alwaysMapped) {
            for item in MetadataContainers.leftovers(in: data) where !found.contains(where: { $0.hasPrefix(item) }) {
                found.append(item == "EXIF thumbnail" ? "embedded thumbnail" : item)
            }
        }
        return found
    }

    /// "Removed: …; filled 1 marked area (bottom right, 220×60 px). Pixel-embedded marks,
    /// if any, are untouched."
    static func report(removed: [String], areas: [CGRect], imageSize: CGSize) -> String {
        var parts: [String] = []
        parts.append(removed.isEmpty ? "No metadata was found to remove" : "Removed: " + removed.joined(separator: ", "))
        if !areas.isEmpty {
            let places = areas.map { "\(place(of: $0, in: imageSize)), \(Int($0.width))×\(Int($0.height)) px" }
            parts.append("filled \(areas.count == 1 ? "1 marked area" : "\(areas.count) marked areas") (\(places.joined(separator: "; ")))")
        }
        return parts.joined(separator: "; ") + ". Pixel-embedded marks, if any, are untouched."
    }

    /// Where a rect sits: "top left", "middle", "bottom right" and so on (thirds).
    static func place(of rect: CGRect, in size: CGSize) -> String {
        guard size.width > 0, size.height > 0 else { return "middle" }
        let column = ["left", "", "right"][min(Int(rect.midX / size.width * 3), 2)]
        let row = ["top", "middle", "bottom"][min(Int(rect.midY / size.height * 3), 2)]
        if column.isEmpty { return row }
        return row == "middle" ? column : "\(row) \(column)"
    }
}
