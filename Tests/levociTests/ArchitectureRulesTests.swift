import Testing
import Foundation

/// Regole architetturali del progetto, verificate automaticamente.
/// Sono test puri: leggono i sorgenti, non servono DB né Application.
@Suite("Architecture Rules")
struct ArchitectureRulesTests {

    /// REGOLA: i controller non leggono mai l'input del client in modo grezzo.
    /// Per il body si usa `req.validatedBody(MioDTO.self)` e per le query string `req.validatedQuery(MioDTO.self)` (vedi `Validation/Validatable.swift`).
    @Test("I controller leggono l'input solo tramite i tipi validati")
    func controllersDoNotReadRawInput() throws {
        let projectDir = try TestProjectPaths.root(from: #filePath)
        let controllersDir = projectDir.appendingPathComponent("Sources/levoci/Controllers")

        let files = try FileManager.default
            .contentsOfDirectory(at: controllersDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        // Se il percorso cambia il test non deve passare "a vuoto"
        #expect(!files.isEmpty, "Nessun controller trovato in \(controllersDir.path)")

        let forbidden = ["content.decode(", "content.get(", "query.decode(", "query.get("]

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in source.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                for pattern in forbidden where code.contains(pattern) {
                    Issue.record("\(file.lastPathComponent):\(index + 1) usa `\(pattern)`: leggi l'input con req.validatedBody(...)")
                }
            }
        }
    }
}
