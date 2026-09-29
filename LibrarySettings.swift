import Foundation
import Combine

/// The selected folder and the volume information captured when it was chosen.
/// Reading this value never needs to touch the selected disk.
struct GameLibraryLocation: Codable, Equatable, Sendable {
    let folder: URL
    let volumePath: String?
    let volumeName: String

    var isExternal: Bool { volumePath != nil }
}

enum GameLibrarySettingsError: LocalizedError {
    case unsupportedConsole
    case invalidURL
    case unreadableDirectory
    case filesystemRoot

    var errorDescription: String? {
        switch self {
        case .unsupportedConsole: return "Escolha um console válido: PS1 ou PS2."
        case .invalidURL: return "Escolha uma pasta do Mac ou de um disco conectado."
        case .unreadableDirectory: return "Não foi possível acessar esta pasta. Verifique se ela existe e se o aplicativo tem permissão de leitura."
        case .filesystemRoot: return "Escolha uma pasta dedicada aos jogos, não a raiz inteira do Mac."
        }
    }
}

/// Stores each console separately. Startup restores paths lexically, including
/// disconnected disks; it does not resolve bookmarks, symlinks or file metadata.
@MainActor
final class GameLibrarySettings: ObservableObject {
    @Published private(set) var locations: [String: GameLibraryLocation]
    private let defaults: UserDefaults
    private static let consoleKeys = ["ps1", "ps2"]

    private struct StoredLocation: Codable {
        let version: Int
        let path: String
        let volumePath: String?
        let volumeName: String
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var restored: [String: GameLibraryLocation] = [:]
        for key in Self.consoleKeys {
            restored[key] = Self.restore(defaults.data(forKey: Self.storageKey(for: key)))
                ?? Self.defaultLocation(for: key)
        }
        self.locations = restored
    }

    static func defaultLocation(for consoleKey: String) -> GameLibraryLocation {
        precondition(consoleKeys.contains(consoleKey), "Unsupported console key")
        return GameLibraryLocation(
            folder: URL(fileURLWithPath: "/Volumes/Extreme SSD/Emulacao/\(consoleKey.uppercased())/Jogos", isDirectory: true),
            volumePath: "/Volumes/Extreme SSD", volumeName: "Extreme SSD")
    }

    static func storageKey(for consoleKey: String) -> String {
        "PS12.GameLibraryLocation.\(consoleKey)"
    }

    func location(for consoleKey: String) -> GameLibraryLocation {
        precondition(Self.consoleKeys.contains(consoleKey), "Unsupported console key")
        return locations[consoleKey] ?? Self.defaultLocation(for: consoleKey)
    }

    func folder(for consoleKey: String) -> URL { location(for: consoleKey).folder }

    /// Called only after the user confirms a folder picker. This is the only
    /// operation in this model that reads the selected folder's filesystem.
    @discardableResult
    func setFolder(_ url: URL, for consoleKey: String) throws -> Bool {
        guard Self.consoleKeys.contains(consoleKey) else { throw GameLibrarySettingsError.unsupportedConsole }
        guard url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.query == nil, url.fragment == nil,
              Self.isValidPath(url.path) else { throw GameLibrarySettingsError.invalidURL }
        guard url.path != "/" else { throw GameLibrarySettingsError.filesystemRoot }

        // Resolve a selected folder alias once, so its persisted mount metadata
        // describes the disk actually containing the games, not an alias path.
        let folder = url.standardizedFileURL.resolvingSymlinksInPath()
        guard folder.path != "/" else { throw GameLibrarySettingsError.filesystemRoot }
        let values: URLResourceValues
        do {
            values = try folder.resourceValues(forKeys: [.isDirectoryKey, .volumeURLKey, .volumeIsInternalKey, .volumeNameKey])
        } catch {
            throw GameLibrarySettingsError.unreadableDirectory
        }
        guard values.isDirectory == true, FileManager.default.isReadableFile(atPath: folder.path) else {
            throw GameLibrarySettingsError.unreadableDirectory
        }
        var volumePath: String?
        var volumeName = "Disco local"
        if values.volumeIsInternal == false, let volume = values.volume,
           volume.isFileURL, Self.isValidPath(volume.path), volume.path != "/",
           Self.contains(folder.path, in: volume.path) {
            volumePath = volume.path
            let candidate = values.volumeName ?? volume.lastPathComponent
            volumeName = Self.isValidName(candidate) ? candidate : volume.lastPathComponent
        }
        let location = GameLibraryLocation(folder: folder, volumePath: volumePath, volumeName: volumeName)
        guard location != self.location(for: consoleKey) else { return false }
        let stored = StoredLocation(version: 1, path: folder.path, volumePath: volumePath, volumeName: volumeName)
        // Encode before mutating the visible settings, so failure leaves the
        // current library untouched. No library files are copied or changed.
        let data = try JSONEncoder().encode(stored)
        defaults.set(data, forKey: Self.storageKey(for: consoleKey))
        locations[consoleKey] = location
        return true
    }

    /// Restoring the original SSD folder must also work with that disk absent.
    @discardableResult
    func reset(for consoleKey: String) -> Bool {
        guard Self.consoleKeys.contains(consoleKey) else { return false }
        let original = Self.defaultLocation(for: consoleKey)
        let changed = location(for: consoleKey) != original
        defaults.removeObject(forKey: Self.storageKey(for: consoleKey))
        if changed { locations[consoleKey] = original }
        return changed
    }

    private static func restore(_ data: Data?) -> GameLibraryLocation? {
        guard let data, data.count <= 16 * 1024,
              let stored = try? JSONDecoder().decode(StoredLocation.self, from: data), stored.version == 1,
              isValidPath(stored.path), stored.path != "/", isValidName(stored.volumeName) else { return nil }
        if let volumePath = stored.volumePath {
            guard isValidPath(volumePath), volumePath != "/", contains(stored.path, in: volumePath) else { return nil }
        }
        return GameLibraryLocation(folder: URL(fileURLWithPath: stored.path, isDirectory: true),
            volumePath: stored.volumePath, volumeName: stored.volumePath == nil ? "Disco local" : stored.volumeName)
    }

    private static func isValidPath(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), path.utf8.count <= 4096,
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains(".") && !components.contains("..")
            && (path == "/" || (!path.hasSuffix("/") && !path.contains("//")))
    }

    private static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf8.count <= 1024
            && !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private static func contains(_ path: String, in root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }
}
