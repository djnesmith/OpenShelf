import Foundation

/// The order of wedges on wheels long enough to page, so that the first page
/// holds the everyday options. Options a file doesn't support are simply
/// absent and the rest keep this order. Wheels that fit on one page keep the
/// order their catalog gives them, and the Actions wheel is never reordered.
enum WheelOrdering {
    /// Image tools; Combine only appears for several files.
    static let imageTools: [FileTool] = [
        .compress, .crop, .resize, .annotate, .removeBackground, .edit,
        .metadata, .redact, .addBackground, .readQR, .ocr, .icon, .gifLoop, .combinePDF,
    ]

    /// Video tools; Merge only appears for several files.
    static let videoTools: [FileTool] = [
        .mergeMedia, .trim, .compressVideo, .fitSize, .cropVideo, .rotateVideo, .splitMedia,
        .speed, .mute, .stillFrame, .grayscale, .transcribe, .reverse, .mediaMetadata, .normalize, .volume, .mono, .frameRate, .export,
    ]

    /// Conversions by the kind of file being converted. ZIP stays last.
    static let formatsBySource: [FileKind: [OutputFormat]] = [
        .image: [.png, .jpg, .heic, .webp, .pdf, .avif, .tiff, .bmp, .docx, .jxl, .apng, .zip],
        .pdf: [.docx, .jpg, .png, .txt, .pptx, .xlsx, .md, .epub, .mobi, .azw3, .fb2, .zip],
        .ebook: EbookConversion.formats + [.zip],
        .spreadsheet: [.xlsx, .csv, .tsv, .pdf, .ods, .numbers, .json, .yaml, .xml, .parquet, .sqlite, .zip],
        .video: [.mp4, .mov, .gif, .mp3, .m4a, .webm, .mkv, .avi, .wmv, .apng, .zip],
        .audio: [.mp3, .m4a, .wav, .flac, .aiff, .ogg, .opus, .wma, .zip],
    ]

    /// `tools` (from `FileTool.available`) in wheel order.
    static func tools(_ tools: [FileTool]) -> [FileTool] {
        guard isPaged(tools.count) else { return tools }
        return ordered(tools, by: imageTools + videoTools)
    }

    /// `formats` (from `ConversionCatalog`) for `urls`, in wheel order. Only
    /// files of one kind are reordered; mixed selections share few formats.
    static func formats(_ formats: [OutputFormat], for urls: [URL]) -> [OutputFormat] {
        guard isPaged(formats.count) else { return formats }
        let kinds = Set(urls.map { FileKind(url: $0) })
        guard kinds.count == 1, let kind = kinds.first, let priority = formatsBySource[kind] else { return formats }
        return ordered(formats, by: priority)
    }

    /// `list` sorted by position in `priority`. Anything missing from
    /// `priority` follows, in its original order.
    static func ordered<Element: Hashable>(_ list: [Element], by priority: [Element]) -> [Element] {
        var rank: [Element: Int] = [:]
        for (index, element) in priority.enumerated() where rank[element] == nil {
            rank[element] = index
        }
        let ranked: [(rank: Int, offset: Int, element: Element)] = list.enumerated().map { offset, element in
            (rank[element] ?? priority.count, offset, element)
        }
        let sorted = ranked.sorted { lhs, rhs in
            lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.offset < rhs.offset
        }
        return sorted.map(\.element)
    }

    private static func isPaged(_ count: Int) -> Bool {
        WheelPaging.pageCount(forItemCount: count) > 1
    }
}
