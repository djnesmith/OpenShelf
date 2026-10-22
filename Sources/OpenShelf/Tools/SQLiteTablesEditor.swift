import Observation
import SwiftUI

/// Lists a SQLite file's tables and saves one, or all, as CSV, JSON or Excel.
struct SQLiteTablesEditor: View {
    static let windowSize = CGSize(width: 420, height: 260)
    static let formats: [OutputFormat] = [.csv, .json, .xlsx]

    let actions: EditorActions
    @State private var model: SQLiteTablesModel

    init(url: URL, actions: EditorActions) {
        self.actions = actions
        _model = State(initialValue: SQLiteTablesModel(url: url))
    }

    var body: some View {
        EditorChrome(
            title: "Tables",
            primaryTitle: "Save",
            isPrimaryEnabled: !model.tables.isEmpty && !model.isSaving,
            actions: actions,
            onPrimary: { model.save(actions: actions) }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.summary)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                EditorRow(label: "Table") {
                    Picker("Table", selection: $model.choice) {
                        Text("All tables").tag(String?.none)
                        ForEach(model.tables, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .labelsHidden()
                }
                EditorRow(label: "Save as") {
                    Picker("Save as", selection: $model.format) {
                        ForEach(Self.formats, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if let error = model.loadError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
        }
        .task { await model.load() }
    }
}

@MainActor
@Observable
final class SQLiteTablesModel {
    let url: URL
    var choice: String?
    var format = OutputFormat.csv
    private(set) var tables: [String] = []
    private(set) var loadError: String?
    private(set) var isSaving = false

    init(url: URL) {
        self.url = url
    }

    var summary: String {
        "\(url.lastPathComponent) · \(tables.count) \(tables.count == 1 ? "table" : "tables")"
    }

    func load() async {
        do {
            tables = try await DatabaseConversion.tables(in: url)
            if tables.isEmpty { loadError = "This database has no tables." }
        } catch {
            loadError = "This file can’t be read as a SQLite database."
        }
    }

    func save(actions: EditorActions) {
        isSaving = true
        let url = url
        let selected = choice.map { [$0] } ?? tables
        let format = format
        Task { [weak self] in
            do {
                actions.saved(try await DatabaseConversion.export(tables: selected, from: url, as: format))
            } catch {
                self?.isSaving = false
                actions.failed(error)
            }
        }
    }
}
