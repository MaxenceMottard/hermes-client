import CoreTransferable
import Foundation
import HermesChat
import UniformTypeIdentifiers

/// A conversation exported as a Markdown file. Shared or saved with `ShareLink`.
struct ConversationFile: Transferable {
    let export: ConversationExport

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            // A fresh folder per export keeps the file name the user sees.
            let folder = FileManager.default.temporaryDirectory.appending(
                path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: file.export.fileName, directoryHint: .notDirectory)
            try file.export.markdown.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
