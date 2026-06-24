import Foundation

/// Writes a game's CSV export to two temp files for the share sheet.
enum GameExportFiles {
    enum ExportError: Error { case writeFailed }

    /// Returns `[metadata.csv, picks.csv]` URLs in `FileManager.temporaryDirectory`,
    /// named after the game so the share sheet/Files app shows something sensible.
    static func write(for game: Game, data: LeagueData) throws -> [URL] {
        let illegalCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let safeName = game.name
            .components(separatedBy: illegalCharacters)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let base = safeName.isEmpty ? "Game" : safeName

        let metadataURL = try write(GameExportCSV.metadataCSV(for: game), named: "\(base) - metadata.csv")
        let picksURL = try write(GameExportCSV.picksCSV(for: game, data: data), named: "\(base) - picks.csv")
        return [metadataURL, picksURL]
    }

    private static func write(_ contents: String, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed
        }
        return url
    }
}
