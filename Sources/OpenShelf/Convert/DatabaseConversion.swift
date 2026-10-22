import Foundation

/// Parquet through DuckDB's command line, and SQLite through macOS's sqlite3.
/// Only queries built here run, never SQL from a file: names are quoted as
/// identifiers and paths as string literals, SQLite opens read-only in safe
/// mode, DuckDB can't install or load extensions, and neither reads the
/// user's startup file (~/.sqliterc, ~/.duckdbrc).
enum DatabaseConversion {
    static let sqlite3 = URL(fileURLWithPath: "/usr/bin/sqlite3")
    static let sqliteExtensions: Set<String> = ["sqlite", "sqlite3", "db"]

    static func isSQLite(_ url: URL) -> Bool {
        sqliteExtensions.contains(url.pathExtension.lowercased())
    }

    /// Convert-wheel formats for Parquet files and for tables that can become one.
    static func formats(forExtension pathExtension: String, tools: ExternalTools) -> [OutputFormat] {
        let hasDuckDB = tools.duckdb != nil
        switch pathExtension.lowercased() {
        case "parquet": return hasDuckDB ? [.csv, .json, .xlsx] : []
        case "csv": return (hasDuckDB ? [.parquet] : []) + [.sqlite]
        case "json": return hasDuckDB ? [.parquet] : []
        default: return []
        }
    }

    /// Whether this conversion is DuckDB's or SQLite's rather than `DataConversion`'s.
    static func handles(_ source: URL, to format: OutputFormat) -> Bool {
        source.pathExtension.lowercased() == "parquet" || format == .parquet || format == .sqlite
    }

    static func convert(_ source: URL, to format: OutputFormat, tools: ExternalTools) async throws -> [URL] {
        let input = source.pathExtension.lowercased()
        guard formats(forExtension: input, tools: tools).contains(format), let pathExtension = format.fileExtension else {
            if tools.duckdb == nil, format == .parquet || input == "parquet" { throw MissingToolError(name: "DuckDB") }
            throw ConversionError.unsupported("\(input.uppercased()) to \(format.title)")
        }
        let destination = OutputNaming.destination(for: source, pathExtension: pathExtension)
        switch (input, format) {
        case ("csv", .sqlite):
            try await csvToSQLite(source, to: destination)
        case ("parquet", .xlsx):
            // DuckDB's own Excel writer is an extension it would download, so through CSV.
            let csv = temporaryFile("csv")
            defer { try? FileManager.default.removeItem(at: csv) }
            try await duckDB(tools, copy: source, as: .csv, to: csv)
            try writeXLSX(csv: csv, sheet: source.deletingPathExtension().lastPathComponent, to: destination)
        default:
            try await PartialFile.write(destination) { partial in
                try await duckDB(tools, copy: source, as: format, to: partial)
            }
        }
        return [destination]
    }

    // MARK: Quoting

    /// `name` as an SQL identifier: "a ""b""".
    static func identifier(_ name: String) -> String {
        "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// `text` as an SQL string literal: 'it''s'.
    static func literal(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }

    // MARK: DuckDB

    /// Settings run before anything else: no extension is installed or
    /// loaded (so nothing is downloaded), and no query can change that.
    static let duckDBLockdown = "SET autoinstall_known_extensions = false; SET autoload_known_extensions = false; SET allow_community_extensions = false; SET lock_configuration = true;"

    /// The COPY that reads `source` (Parquet, CSV or JSON) and writes `format` to `output`.
    static func duckDBCopy(_ source: URL, as format: OutputFormat, to output: URL) -> String? {
        let reader: String
        switch source.pathExtension.lowercased() {
        case "parquet": reader = "read_parquet"
        case "csv": reader = "read_csv_auto"
        case "json": reader = "read_json_auto"
        default: return nil
        }
        let options: String
        switch format {
        case .parquet: options = "FORMAT parquet"
        case .csv: options = "FORMAT csv, HEADER true"
        case .json: options = "FORMAT json, ARRAY true"
        default: return nil
        }
        return "COPY (SELECT * FROM \(reader)(\(literal(source.path)))) TO \(literal(output.path)) (\(options));"
    }

    static func duckDBArguments(_ sql: String) -> [String] {
        ["-init", "/dev/null", "-batch", "-c", duckDBLockdown + " " + sql]
    }

    private static func duckDB(_ tools: ExternalTools, copy source: URL, as format: OutputFormat, to output: URL) async throws {
        guard let duckdb = tools.duckdb else { throw MissingToolError(name: "DuckDB") }
        guard let sql = duckDBCopy(source, as: format, to: output) else { throw ConversionError.unsupported("\(format.title) with DuckDB") }
        try await ProcessRunner.run(duckdb, duckDBArguments(sql))
    }

    // MARK: SQLite

    /// sqlite3 opening an untrusted file: read-only, in safe mode (no dot
    /// commands that touch files, no extensions), without ~/.sqliterc.
    static func sqliteReadArguments(_ database: URL, mode: [String] = [], sql: String) -> [String] {
        ["-readonly", "-safe", "-bail", "-init", "/dev/null"] + mode + [database.path, sql]
    }

    static let listTablesSQL = "SELECT name FROM sqlite_schema WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;"

    /// The tables in a SQLite file, in name order.
    static func tables(in database: URL) async throws -> [String] {
        let output = temporaryFile("txt")
        defer { try? FileManager.default.removeItem(at: output) }
        try await ProcessRunner.run(sqlite3, sqliteReadArguments(database, mode: ["-list"], sql: listTablesSQL), standardOutputFile: output)
        return try String(contentsOf: output, encoding: .utf8).split(whereSeparator: \.isNewline).map(String.init)
    }

    /// Each of `tables` as "<database> <table>.csv" (or JSON, or XLSX).
    static func export(tables: [String], from database: URL, as format: OutputFormat) async throws -> [URL] {
        var saved: [URL] = []
        for table in tables {
            try Task.checkCancellation()
            let sql = "SELECT * FROM \(identifier(table));"
            let destination = OutputNaming.destination(for: database, suffix: table, pathExtension: format.fileExtension ?? "csv")
            switch format {
            case .json:
                try await PartialFile.write(destination) { partial in
                    try await ProcessRunner.run(sqlite3, sqliteReadArguments(database, mode: ["-json"], sql: sql), standardOutputFile: partial)
                }
                saved.append(destination)
            case .xlsx:
                let csv = temporaryFile("csv")
                defer { try? FileManager.default.removeItem(at: csv) }
                try await ProcessRunner.run(sqlite3, sqliteReadArguments(database, mode: ["-csv", "-header"], sql: sql), standardOutputFile: csv)
                try writeXLSX(csv: csv, sheet: table, to: destination)
                saved.append(destination)
            default:
                try await PartialFile.write(destination) { partial in
                    try await ProcessRunner.run(sqlite3, sqliteReadArguments(database, mode: ["-csv", "-header"], sql: sql), standardOutputFile: partial)
                }
                saved.append(destination)
            }
        }
        return saved
    }

    /// A table name from a file name: letters, digits and underscores.
    static func tableName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
        return name.first?.isLetter == true ? name : "t_" + name
    }

    /// A new SQLite file holding the CSV as one table, typed by sqlite3's
    /// import. The CSV is copied to a plain temporary name first, so nothing
    /// in its path needs quoting in the import command.
    private static func csvToSQLite(_ source: URL, to destination: URL) async throws {
        let csv = temporaryFile("csv")
        defer { try? FileManager.default.removeItem(at: csv) }
        try FileManager.default.copyItem(at: source, to: csv)
        try await PartialFile.write(destination) { partial in
            try await ProcessRunner.run(sqlite3, ["-bail", "-init", "/dev/null", partial.path, ".import --csv \(csv.path) \(tableName(for: source))"])
        }
    }

    /// One sheet, named as Excel allows: 31 characters without []:*?/\.
    private static func writeXLSX(csv: URL, sheet: String, to destination: URL) throws {
        try SaveError.checkWritable(destination)
        let name = String(sheet.map { "[]:*?/\\".contains($0) ? "_" : $0 }.prefix(31))
        try XlsxWriter.write(sheets: [(name: name.isEmpty ? "Sheet1" : name, table: try SpreadsheetConversion.read(csv))], to: destination)
    }

    private static func temporaryFile(_ pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("openshelf-\(UUID().uuidString).\(pathExtension)")
    }
}
