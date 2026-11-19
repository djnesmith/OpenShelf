import Foundation

/// Reads an image file's own containers (PNG chunks, JPEG segments, GIF
/// blocks) for metadata that ImageIO's properties don't show: Content
/// Credentials (C2PA), text comments, XMP and Photoshop IPTC. Metadata ›
/// Clean checks its result with this, so it can't call a file clean that isn't.
/// A lossless PNG copy, for one, keeps caBX and tEXt chunks.
enum MetadataContainers {
    /// What metadata the bytes still hold, by name; empty when none, or when
    /// the format isn't one this reads (HEIC and AVIF are re-encoded and
    /// checked by ImageIO).
    static func leftovers(in data: Data) -> [String] {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return png(bytes) }
        if bytes.starts(with: [0xFF, 0xD8]) { return jpeg(bytes) }
        if bytes.starts(with: Array("GIF8".utf8)) { return gif(bytes) }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) { return tiff(bytes) }
        return []
    }

    // MARK: - PNG

    /// Chunks that describe only the pixels and how to show them.
    static let pngAllowed: Set<String> = [
        "IHDR", "PLTE", "IDAT", "IEND", "tRNS", "gAMA", "cHRM", "sRGB", "iCCP", "sBIT", "pHYs", "bKGD", "hIST",
        "cICP", "mDCv", "cLLi", "acTL", "fcTL", "fdAT",
        // Apple's layout hint for decoding in parallel.
        "iDOT",
        // EXIF is ImageIO's to judge, as in JPEG: it writes a neutral one into every PNG.
        "eXIf",
    ]

    static func png(_ bytes: [UInt8]) -> [String] {
        var found: [String] = []
        var offset = 8
        while offset + 8 <= bytes.count {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let type = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
            if !pngAllowed.contains(type) {
                switch type {
                case "caBX": found.append("Content Credentials (C2PA)")
                case "tEXt", "iTXt", "zTXt": found.append("text comments")
                case "tIME": found.append("modification time")
                default: found.append("PNG \(type) chunk")
                }
            }
            if type == "IEND" { break }
            offset += 12 + length
        }
        return unique(found)
    }

    // MARK: - JPEG

    static func jpeg(_ bytes: [UInt8]) -> [String] {
        var found: [String] = []
        var offset = 2
        while offset + 4 <= bytes.count, bytes[offset] == 0xFF {
            let marker = bytes[offset + 1]
            // Fill bytes, and markers with no length.
            if marker == 0xFF { offset += 1; continue }
            if marker == 0xD8 || (0xD0...0xD7).contains(marker) || marker == 0x01 { offset += 2; continue }
            // The image data starts: no more metadata segments.
            if marker == 0xDA || marker == 0xD9 { break }
            let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let body = Array(bytes[min(offset + 4, bytes.count)..<min(offset + 2 + length, bytes.count)])
            func starts(_ text: String) -> Bool { body.starts(with: Array(text.utf8)) }
            switch marker {
            case 0xE0, 0xEE:
                break // JFIF, and Adobe's colour transform.
            case 0xE1:
                // EXIF and XMP are ImageIO's to judge (its XMP check reads
                // every tag, and lets a kept orientation through); anything
                // else in APP1 is not either.
                if !starts("Exif") && !starts("http://ns.adobe.com/xap/1.0/") && !starts("http://ns.adobe.com/xmp/extension/") { found.append("APP1 data") }
            case 0xE2:
                if starts("MPF") { found.append("embedded images (MPF)") } else if !starts("ICC_PROFILE") { found.append("APP2 data") }
            case 0xEB:
                let text = String(decoding: body, as: UTF8.self)
                found.append(text.contains("jumb") || text.contains("c2pa") ? "Content Credentials (C2PA)" : "APP11 data")
            case 0xED:
                break // Photoshop resources: ImageIO writes one itself, and reports any IPTC in it.
            case 0xFE:
                found.append("comment")
            case 0xE3...0xEF:
                found.append("APP\(marker - 0xE0) data")
            default:
                break // Tables and frame headers.
            }
            offset += 2 + length
        }
        return unique(found)
    }

    // MARK: - GIF

    static func gif(_ bytes: [UInt8]) -> [String] {
        guard bytes.count >= 13 else { return [] }
        var found: [String] = []
        var offset = 13
        if bytes[10] & 0x80 != 0 { offset += 3 << (Int(bytes[10] & 0x07) + 1) }
        func skipSubBlocks() {
            while offset < bytes.count {
                let size = Int(bytes[offset])
                offset += 1 + size
                if size == 0 { return }
            }
        }
        while offset < bytes.count {
            switch bytes[offset] {
            case 0x3B:
                return unique(found)
            case 0x21:
                guard offset + 1 < bytes.count else { return unique(found) }
                let label = bytes[offset + 1]
                offset += 2
                if label == 0xFE { found.append("comment") }
                if label == 0xFF, offset + 12 <= bytes.count {
                    let application = String(decoding: bytes[(offset + 1)..<(offset + 12)], as: UTF8.self)
                    if !["NETSCAPE2.0", "ANIMEXTS1.0"].contains(application) {
                        found.append(application.hasPrefix("XMP") ? "XMP" : "application data")
                    }
                }
                skipSubBlocks()
            case 0x2C:
                guard offset + 10 <= bytes.count else { return unique(found) }
                let flags = bytes[offset + 9]
                offset += 10
                if flags & 0x80 != 0 { offset += 3 << (Int(flags & 0x07) + 1) }
                offset += 1 // LZW minimum code size
                skipSubBlocks()
            default:
                return unique(found)
            }
        }
        return unique(found)
    }

    // MARK: - TIFF

    /// Text and identifying tags. A lossless TIFF copy keeps them, and
    /// ImageIO's properties of the copy don't show them.
    static let tiffTags: [Int: String] = [
        270: "image description", 271: "camera details", 272: "camera details", 305: "software", 306: "date",
        315: "artist", 316: "host computer", 33432: "copyright", 700: "XMP", 33723: "IPTC", 34377: "Photoshop data",
        34853: "location", 37510: "comment",
    ]

    static func tiff(_ bytes: [UInt8]) -> [String] {
        let little = bytes[0] == 0x49
        func u16(_ at: Int) -> Int { at + 2 <= bytes.count ? (little ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : Int(bytes[at]) << 8 | Int(bytes[at + 1])) : 0 }
        func u32(_ at: Int) -> Int { at + 4 <= bytes.count ? (little ? u16(at) | u16(at + 2) << 16 : u16(at) << 16 | u16(at + 2)) : 0 }
        var found: [String] = []
        var directory = u32(4)
        var visited = Set<Int>()
        while directory > 0, directory + 2 <= bytes.count, visited.insert(directory).inserted {
            let count = u16(directory)
            for index in 0..<count {
                if let name = tiffTags[u16(directory + 2 + index * 12)] { found.append(name) }
            }
            directory = u32(directory + 2 + count * 12)
        }
        return unique(found)
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
