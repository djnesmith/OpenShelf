import Foundation

/// The optional tools Settings → Extra Formats lists below ffmpeg and
/// LibreOffice. OpenShelf doesn't install these; it finds them where Homebrew
/// puts them. ffprobe comes with ffmpeg. `CommandLineToolTests` fails when
/// `ExternalTools` gains a tool that isn't here.
enum CommandLineTool: String, CaseIterable, Identifiable, Sendable {
    case cwebp
    case calibre
    case pandoc
    case yq
    case cjxl
    case duckdb
    case jet
    case deno
    case cljfmt
    case ruff
    case shfmt
    case swiftFormat
    case pgFormat
    case clangFormat
    case gofmt
    case rustfmt

    var id: String { rawValue }

    /// The collapsed Settings row: "Command-Line Tools · 15 of 16 installed".
    static func title(tools: ExternalTools) -> String {
        let installed = allCases.filter { $0.isInstalled(in: tools) }.count
        return "Command-Line Tools · \(installed) of \(allCases.count) installed"
    }

    var name: String {
        switch self {
        case .cwebp: "cwebp"
        case .calibre: "calibre"
        case .pandoc: "pandoc"
        case .yq: "yq"
        case .cjxl: "cjxl"
        case .duckdb: "DuckDB"
        case .jet: "jet"
        case .deno: "deno"
        case .cljfmt: "cljfmt"
        case .ruff: "ruff"
        case .shfmt: "shfmt"
        case .swiftFormat: "swift-format"
        case .pgFormat: "pg_format"
        case .clangFormat: "clang-format"
        case .gofmt: "gofmt"
        case .rustfmt: "rustfmt"
        }
    }

    /// One short line on what it adds.
    var adds: String {
        switch self {
        case .cwebp: "Smaller WebP images"
        case .calibre: "EPUB, MOBI, AZW3 and FB2"
        case .pandoc: "LaTeX, Typst, reST, AsciiDoc and Org"
        case .yq: "YAML, XML and CSV data"
        case .cjxl: "JPEG XL"
        case .duckdb: "Parquet"
        case .jet: "EDN"
        case .deno: "Pretty Print: JS, TS, JSON, YAML, Markdown, HTML, CSS"
        case .cljfmt: "Pretty Print: Clojure and EDN"
        case .ruff: "Pretty Print: Python"
        case .shfmt: "Pretty Print: shell scripts"
        case .swiftFormat: "Pretty Print: Swift"
        case .pgFormat: "Pretty Print: SQL"
        case .clangFormat: "Pretty Print: C, C++ and Objective-C"
        case .gofmt: "Pretty Print: Go"
        case .rustfmt: "Pretty Print: Rust"
        }
    }

    var homebrewCommand: String {
        switch self {
        case .cwebp: "brew install webp"
        case .calibre: "brew install --cask calibre"
        case .pandoc: "brew install pandoc"
        case .yq: "brew install yq"
        case .cjxl: "brew install jpeg-xl"
        case .duckdb: "brew install duckdb"
        case .jet: "brew install borkdude/brew/jet"
        case .deno: "brew install deno"
        case .cljfmt: "brew install cljfmt"
        case .ruff: "brew install ruff"
        case .shfmt: "brew install shfmt"
        case .swiftFormat: "brew install swift-format"
        case .pgFormat: "brew install pgformatter"
        case .clangFormat: "brew install clang-format"
        case .gofmt: "brew install go"
        case .rustfmt: "brew install rust"
        }
    }

    /// Whether `homebrewCommand` comes from a third-party tap, not homebrew-core.
    var isThirdPartyTap: Bool { self == .jet }

    func isInstalled(in tools: ExternalTools) -> Bool {
        path(in: tools) != nil
    }

    /// `tools` as if this one were installed, to ask what it would add. The
    /// placeholder path is never run.
    func assumedInstalled(in tools: ExternalTools) -> ExternalTools {
        var tools = tools
        let placeholder = URL(fileURLWithPath: "/nonexistent/\(rawValue)")
        switch self {
        case .cwebp: tools.cwebp = placeholder
        case .calibre: tools.ebookConvert = placeholder
        case .pandoc: tools.pandoc = placeholder
        case .yq: tools.yq = placeholder
        case .cjxl: tools.cjxl = placeholder
        case .duckdb: tools.duckdb = placeholder
        case .jet: tools.jet = placeholder
        case .deno: tools.formatters.deno = placeholder
        case .cljfmt: tools.formatters.cljfmt = placeholder
        case .ruff: tools.formatters.ruff = placeholder
        case .shfmt: tools.formatters.shfmt = placeholder
        case .swiftFormat: tools.formatters.swiftFormat = placeholder
        case .pgFormat: tools.formatters.pgFormat = placeholder
        case .clangFormat: tools.formatters.clangFormat = placeholder
        case .gofmt: tools.formatters.gofmt = placeholder
        case .rustfmt: tools.formatters.rustfmt = placeholder
        }
        return tools
    }

    func path(in tools: ExternalTools) -> URL? {
        switch self {
        case .cwebp: tools.cwebp
        case .calibre: tools.ebookConvert
        case .pandoc: tools.pandoc
        case .yq: tools.yq
        case .cjxl: tools.cjxl
        case .duckdb: tools.duckdb
        case .jet: tools.jet
        case .deno: tools.formatters.deno
        case .cljfmt: tools.formatters.cljfmt
        case .ruff: tools.formatters.ruff
        case .shfmt: tools.formatters.shfmt
        case .swiftFormat: tools.formatters.swiftFormat
        case .pgFormat: tools.formatters.pgFormat
        case .clangFormat: tools.formatters.clangFormat
        case .gofmt: tools.formatters.gofmt
        case .rustfmt: tools.formatters.rustfmt
        }
    }
}
