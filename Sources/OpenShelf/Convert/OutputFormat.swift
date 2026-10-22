import Foundation
import UniformTypeIdentifiers

/// A conversion target.
enum OutputFormat: String, CaseIterable, Hashable, Sendable {
    // Images
    case png, jpg, webp, heic, tiff, avif, bmp, gif
    // Documents
    case pdf, docx, txt, rtf, html, md, epub, pptx
    // Spreadsheets
    case xlsx, csv, tsv, ods
    // Audio and video
    case mp4, mov, m4a, mp3, wav, aiff, flac, ogg, opus, wma
    case mkv, webm, avi, wmv
    // Subtitles
    case srt, vtt
    // Archives
    case zip, tar, tgz, extract
    case txz, tzst
    case sevenZip = "7z"
    // Ebooks (calibre)
    case mobi, azw3, fb2
    // Markup (pandoc)
    case tex, adoc, rst, org, typ
    // Data files
    case json, yaml, xml, plist
    // Animated PNG, written as .png
    case apng

    var title: String {
        switch self {
        case .extract: "UNZIP"
        case .tgz: "TAR.GZ"
        case .txz: "TAR.XZ"
        case .tzst: "TAR.ZST"
        case .tex: "LATEX"
        case .apng: "APNG"
        case .typ: "TYPST"
        default: rawValue.uppercased()
        }
    }

    /// Extension of the written file; nil for formats that produce a folder.
    var fileExtension: String? {
        switch self {
        case .extract: nil
        case .tgz: "tar.gz"
        case .txz: "tar.xz"
        case .tzst: "tar.zst"
        case .apng: "png"
        default: rawValue
        }
    }

    /// Whether a file with this extension is already in this format.
    func matches(extension ext: String) -> Bool {
        let ext = ext.lowercased()
        switch self {
        case .jpg: return ["jpg", "jpeg", "jpe"].contains(ext)
        case .tiff: return ["tif", "tiff"].contains(ext)
        case .heic: return ["heic", "heif"].contains(ext)
        case .html: return ["html", "htm"].contains(ext)
        case .aiff: return ["aif", "aiff"].contains(ext)
        case .txt: return ["txt", "text"].contains(ext)
        case .md: return ["md", "markdown"].contains(ext)
        case .ogg: return ["ogg", "oga"].contains(ext)
        case .tgz: return ext == "tgz"
        case .txz: return ext == "txz"
        case .tzst: return ext == "tzst"
        case .apng: return ext == "apng"
        case .tex: return ["tex", "latex"].contains(ext)
        case .adoc: return ["adoc", "asciidoc"].contains(ext)
        case .yaml: return ["yaml", "yml"].contains(ext)
        default: return ext == rawValue
        }
    }

    /// The ImageIO type for image formats ImageIO can encode.
    var imageIOType: UTType? {
        switch self {
        case .png: .png
        case .jpg: .jpeg
        case .heic: .heic
        case .tiff: .tiff
        case .avif: UTType("public.avif")
        case .bmp: .bmp
        case .gif: .gif
        default: nil
        }
    }

    /// Formats only ffmpeg can write from audio or video. (GIF has a native
    /// fallback, `VideoGIF`.)
    var needsFFmpeg: Bool {
        [.mp3, .ogg, .opus, .wma, .mkv, .webm, .avi, .wmv, .apng].contains(self)
    }

    /// Audio-only outputs, which need a sound track in the source.
    var isAudioOnly: Bool {
        [.m4a, .mp3, .wav, .aiff, .flac, .ogg, .opus, .wma].contains(self)
    }
}

/// Which conversions apply to which files.
///
/// Wheels stay at 12 items or fewer (the largest, images, has 10); more than
/// seven are shown over two pages, in `WheelOrdering`'s order. PAGES is never
/// offered: it's Apple's private format.
enum ConversionCatalog {
    /// What folders and other files can be packed into.
    static let archiveFormats: [OutputFormat] = [.zip, .tar, .tgz, .txz, .tzst, .sevenZip]

    /// The most wedges a wheel shows; the last one is always ZIP.
    static let maxWedges = 12

    /// Formats every file in `urls` can be converted to; `WheelOrdering` orders long lists for the wheel.
    static func formats(for urls: [URL], tools: ExternalTools) -> [OutputFormat] {
        guard let first = urls.first else { return [] }
        var common = formats(for: first, tools: tools)
        for url in urls.dropFirst() {
            let available = Set(formats(for: url, tools: tools))
            common.removeAll { !available.contains($0) }
        }
        return common
    }

    /// The formats a Convert wheel's wedges offer.
    static func formats(in items: [WheelItem]) -> [OutputFormat] {
        items.compactMap { item in
            if case .convert(let format) = item.command { return format }
            return nil
        }
    }

    static func formats(for url: URL, tools: ExternalTools) -> [OutputFormat] {
        let ext = url.pathExtension.lowercased()
        let hasFFmpeg = tools.ffmpeg != nil
        var formats: [OutputFormat]

        switch FileKind(url: url) {
        case .image:
            formats = [.png, .jpg, .heic, .tiff, .avif, .bmp, .pdf, .docx]
            if tools.canEncodeWebP { formats.insert(.webp, at: 2) }
            if ext == "gif" { formats.append(.apng) }
        case .pdf:
            formats = [.docx, .jpg, .png, .txt, .md, .epub, .pptx, .xlsx]
            if tools.ebookConvert != nil { formats += EbookConversion.calibreOnly.sortedLike(EbookConversion.formats) }
        case .document where PandocConversion.markupExtensions.contains(ext):
            if tools.pandoc != nil {
                formats = PandocConversion.formatsForMarkup
            } else {
                // As before pandoc: LaTeX, Typst, AsciiDoc and Org read as plain text.
                formats = ext == "rst" ? [] : [.pdf, .docx, .txt, .md, .epub, .html, .rtf]
            }
        case .document:
            formats = [.pdf, .docx, .txt, .md, .epub, .html, .rtf]
            if tools.pandoc != nil, PandocConversion.reader(for: url) != nil {
                formats += PandocConversion.markupFormats
            }
        case .spreadsheet:
            formats = spreadsheetFormats(ext: ext, tools: tools)
        case .presentation:
            // Slides need LibreOffice to render; Keynote files can't be read at all.
            formats = tools.libreOffice != nil && ext != "key" ? [.pdf, .jpg, .png] : []
        case .audio:
            if MediaFormats.isAVFoundationReadable(url) {
                formats = [.m4a, .wav, .aiff, .flac]
                if hasFFmpeg { formats = [.mp3] + formats + [.ogg, .opus, .wma] }
            } else {
                // Ogg, Opus, WMA and friends can only be decoded by ffmpeg.
                formats = hasFFmpeg ? [.mp3, .m4a, .wav, .aiff, .flac, .ogg, .opus, .wma] : []
            }
        case .video:
            if MediaFormats.isAVFoundationReadable(url) {
                // GIF is made natively when ffmpeg isn't installed.
                formats = [.mp4, .mov, .m4a, .gif]
                if hasFFmpeg { formats += [.mp3, .mkv, .webm, .avi, .wmv, .apng] }
            } else {
                formats = hasFFmpeg ? [.mp4, .mov, .m4a, .gif, .mp3, .mkv, .webm, .avi, .wmv, .apng] : []
            }
            // Silent videos have nothing to extract as audio.
            if MediaProbe.hasAudioTrack(url.resolvingSymlinksInPath(), ffprobe: tools.ffprobe) == false {
                formats.removeAll(where: \.isAudioOnly)
            }
        case .subtitle:
            formats = [.txt, .srt, .vtt]
        case .data:
            formats = DataConversion.formats(forExtension: ext, tools: tools)
        case .ebook:
            // Without calibre a book is just a file, as before.
            guard tools.ebookConvert != nil else { return archiveFormats }
            formats = EbookConversion.formats
        case .archive:
            return [.extract]
        case .folder, .other:
            return archiveFormats
        }
        formats.removeAll { $0.matches(extension: ext) }
        return Array(formats.prefix(maxWedges - 1)) + [.zip]
    }

    private static func spreadsheetFormats(ext: String, tools: ExternalTools) -> [OutputFormat] {
        let hasOffice = tools.libreOffice != nil
        switch ext {
        case "csv", "tsv", "xlsx":
            // Built in: CSV ⇄ TSV ⇄ XLSX and a table PDF; ODS needs LibreOffice.
            return [.xlsx, .csv, .tsv, .pdf] + (hasOffice ? [.ods] : []) + DataConversion.formats(forExtension: ext, tools: tools)
        default:
            // XLS and ODS can only be opened by LibreOffice.
            return hasOffice ? [.xlsx, .csv, .pdf, .ods] : []
        }
    }
}

extension Set<OutputFormat> {
    /// These formats in `order`'s order.
    func sortedLike(_ order: [OutputFormat]) -> [OutputFormat] {
        order.filter(contains)
    }
}
