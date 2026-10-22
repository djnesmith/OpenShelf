import Foundation

/// Ebooks through calibre's `ebook-convert`: EPUB, Kindle (MOBI, AZW3) and
/// FictionBook in and out, plus PDF, Word and text out, and PDFs in.
enum EbookConversion {
    /// What a book can become, in wheel order.
    static let formats: [OutputFormat] = [.epub, .mobi, .azw3, .fb2, .pdf, .docx, .txt]
    /// What only calibre writes, so other files offer them only with calibre.
    static let calibreOnly: Set<OutputFormat> = [.mobi, .azw3, .fb2]

    static func convert(
        _ source: URL,
        to format: OutputFormat,
        tools: ExternalTools,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let ebookConvert = tools.ebookConvert else { throw MissingToolError(name: "calibre") }
        guard let pathExtension = format.fileExtension else { throw ConversionError.unsupported("book to \(format.title)") }
        let destination = OutputNaming.destination(for: source, pathExtension: pathExtension)
        // calibre picks the output format from the file's extension, which the partial file keeps.
        try await PartialFile.write(destination) { partial in
            try await ProcessRunner.run(ebookConvert, [source.path, partial.path]) { line in
                if let fraction = fraction(fromProgressLine: line) { progress(fraction) }
            }
        }
        return destination
    }

    /// ebook-convert prints "34% Running transforms on e-book" as it goes.
    static func fraction(fromProgressLine line: String) -> Double? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, line.dropFirst(digits.count).hasPrefix("%"), let percent = Double(digits) else { return nil }
        return min(percent / 100, 1)
    }
}

/// Writes a file through a hidden partial file beside it, moved into place
/// only once it's complete, as the media tools do: a failure leaves nothing.
enum PartialFile {
    static func write(_ destination: URL, _ body: (URL) async throws -> Void) async throws {
        try SaveError.checkWritable(destination)
        let partial = MediaTools.partialURL(for: destination)
        do {
            try await body(partial)
        } catch {
            MediaTools.discardPartial(partial)
            throw error
        }
        try MediaTools.moveIntoPlace(partial, destination: destination)
    }
}
