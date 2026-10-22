import Foundation

enum ConversionError: LocalizedError {
    case unsupported(String)
    case unreadable(URL)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let detail): "This conversion isn’t supported: \(detail)."
        case .unreadable(let url): "“\(url.lastPathComponent)” couldn’t be read."
        case .failed(let detail): detail
        }
    }
}

/// Converts one file into another format, saving the result next to it.
enum Converter {
    /// Returns the files written (several when, e.g., a multi-page PDF becomes images).
    static func convert(
        _ source: URL,
        to format: OutputFormat,
        tools: ExternalTools,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [URL] {
        do {
            return try await run(source, to: format, tools: tools, progress: progress)
        } catch {
            throw FailureMessage.describe(error, source: source)
        }
    }

    private static func run(
        _ source: URL,
        to format: OutputFormat,
        tools: ExternalTools,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [URL] {
        switch format {
        case .zip:
            return [try await ArchiveConversion.zip([source])]
        case .tar, .tgz, .txz, .tzst, .sevenZip:
            return [try await ArchiveConversion.archive([source], as: format)]
        case .extract:
            return [try await ArchiveConversion.extract(source)]
        default:
            break
        }

        switch FileKind(url: source) {
        case .image:
            return [try await ImageConversion.convert(source, to: format, tools: tools)]
        case .pdf where EbookConversion.calibreOnly.contains(format):
            return [try await EbookConversion.convert(source, to: format, tools: tools, progress: progress)]
        case .pdf:
            return try PDFConversion.convert(source, to: format)
        case .document where tools.pandoc != nil && PandocConversion.handles(source, to: format):
            return [try await PandocConversion.convert(source, to: format, tools: tools)]
        case .document:
            return [try await DocumentConversion.convert(source, to: format)]
        case .data where EdnConversion.handles(source, to: format):
            return [try await EdnConversion.convert(source, to: format, tools: tools)]
        case .data where DatabaseConversion.handles(source, to: format):
            return try await DatabaseConversion.convert(source, to: format, tools: tools)
        case .spreadsheet where DatabaseConversion.handles(source, to: format):
            return try await DatabaseConversion.convert(source, to: format, tools: tools)
        case .data:
            return [try await DataConversion.convert(source, to: format, tools: tools)]
        case .spreadsheet where [.json, .yaml, .xml].contains(format):
            return [try await DataConversion.convert(source, to: format, tools: tools)]
        case .spreadsheet:
            return try await SpreadsheetConversion.convert(source, to: format, tools: tools)
        case .presentation:
            return try await OfficeConversion.convert(source, to: format, tools: tools)
        case .audio, .video:
            return [try await MediaConversion.convert(source, to: format, tools: tools, progress: progress)]
        case .subtitle:
            return [try await SubtitleConversion.convert(source, to: format, tools: tools)]
        case .ebook:
            return [try await EbookConversion.convert(source, to: format, tools: tools, progress: progress)]
        case .archive, .folder, .other:
            throw ConversionError.unsupported("\(source.pathExtension.uppercased()) to \(format.title)")
        }
    }
}
