import Foundation
import HermesChat

/// Writes a conversation export to a temporary Markdown file, so that it can be shared with `ShareLink`.
enum ExportFile {
    static func write(_ export: ConversationExport) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: export.fileName, directoryHint: .notDirectory)
        try export.markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// Share button for a conversation export. Renders nothing if the file cannot be written.
struct ExportLink: View {
    let export: ConversationExport

    var body: some View {
        if let url = try? ExportFile.write(export) {
            ShareLink(item: url) {
                Label("Export as Markdown", systemImage: "square.and.arrow.up")
            }
        }
    }
}
