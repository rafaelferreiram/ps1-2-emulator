import Foundation

/// On-demand safety/readability check for a single launch request. Never walks
/// the library, scans disc contents, or rebuilds the saved catalog.
enum GameLaunchCheck {
    private static let maximumDescriptorBytes = 128 * 1024
    private static let maximumDepth = 8
    private static let maximumReferences = 512
    private static let playableExtensions: Set<String> = ["cue", "ccd", "m3u", "chd", "iso", "pbp", "img", "bin", "cso", "zso", "gz", "mdf"]
    private static let descriptors: Set<String> = ["cue", "ccd", "m3u"]

    static func isAvailable(_ url: URL, library: URL) -> Bool {
        guard url.isFileURL, library.isFileURL else { return false }
        let root = library.standardizedFileURL.resolvingSymlinksInPath()
        guard root.path != "/", let info = try? root.resourceValues(forKeys: [.isDirectoryKey]), info.isDirectory == true else { return false }
        var validator = Validator(root: root)
        return validator.validate(url, depth: 0)
    }

    private struct Validator {
        let root: URL
        var active: Set<String> = []
        var verified: Set<String> = []
        var references = 0

        mutating func validate(_ url: URL, depth: Int) -> Bool {
            references += 1
            guard references <= maximumReferences, depth <= maximumDepth else { return false }
            let file = url.standardizedFileURL.resolvingSymlinksInPath()
            let kind = file.pathExtension.lowercased()
            guard contained(file), playableExtensions.contains(kind), !active.contains(file.path) else { return false }
            if verified.contains(file.path) { return true }
            guard readable(file) else { return false }
            active.insert(file.path)
            defer { active.remove(file.path) }
            switch kind {
            case "cue":
                guard let text = descriptor(file), let names = cueReferences(text), !names.isEmpty else { return false }
                for name in names {
                    references += 1
                    guard references <= maximumReferences, let dependency = resolve(name, relativeTo: file),
                          !descriptors.contains(dependency.pathExtension.lowercased()), readable(dependency) else { return false }
                }
            case "ccd":
                references += 1
                guard references <= maximumReferences,
                      let dependency = resolve(file.deletingPathExtension().lastPathComponent + ".img", relativeTo: file),
                      readable(dependency) else { return false }
            case "m3u":
                guard let text = descriptor(file) else { return false }
                let names = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("#") }
                guard !names.isEmpty, names.count <= maximumReferences else { return false }
                for name in names {
                    guard let dependency = resolve(name, relativeTo: file), validate(dependency, depth: depth + 1) else { return false }
                }
            default: break
            }
            verified.insert(file.path)
            return true
        }

        private func contained(_ file: URL) -> Bool {
            file.isFileURL && file.path.hasPrefix(root.path + "/")
                && !file.path.dropFirst(root.path.count + 1).split(separator: "/").contains { $0.hasPrefix(".") }
        }

        private func readable(_ file: URL) -> Bool {
            guard contained(file), let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, (values.fileSize ?? 0) > 0,
                  FileManager.default.isReadableFile(atPath: file.path), let handle = try? FileHandle(forReadingFrom: file) else { return false }
            defer { try? handle.close() }
            return ((try? handle.read(upToCount: 1))?.count ?? 0) == 1
        }

        private func descriptor(_ file: URL) -> String? {
            guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: maximumDescriptorBytes + 1), data.count <= maximumDescriptorBytes else { return nil }
            return (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252))?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        }

        private func resolve(_ name: String, relativeTo descriptor: URL) -> URL? {
            let name = name.replacingOccurrences(of: "\\", with: "/")
            guard !name.isEmpty, !name.hasPrefix("/"), !name.contains(":"), !name.contains("\0") else { return nil }
            var file = descriptor.deletingLastPathComponent().appendingPathComponent(name).standardizedFileURL
            guard contained(file.resolvingSymlinksInPath()) else { return nil }
            // Match the scanner's case-insensitive descriptor compatibility on
            // case-sensitive SSDs. Only the dependency's own immediate parent is
            // inspected; there is no recursion or catalog enumeration here.
            if !FileManager.default.fileExists(atPath: file.path) {
                guard let siblings = try? FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil),
                      siblings.count <= 4096 else { return nil }
                let matches = siblings.filter { $0.lastPathComponent.caseInsensitiveCompare(file.lastPathComponent) == .orderedSame }
                guard matches.count == 1, let actual = matches.first else { return nil }
                file = actual
            }
            file = file.standardizedFileURL.resolvingSymlinksInPath()
            return contained(file) ? file : nil
        }
    }

    private static func cueReferences(_ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: #"(?im)^\s*FILE\s+(?:\"([^\"]+)\"|(\S+))\s+\S+\s*$"#) else { return nil }
        let names = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            let range = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
            return Range(range, in: text).map { String(text[$0]) }
        }
        let fileLines = text.components(separatedBy: .newlines).filter { $0.range(of: #"(?i)^\s*FILE(?:\s|$)"#, options: .regularExpression) != nil }.count
        guard fileLines == names.count, text.range(of: #"(?im)^\s*TRACK\s+\d+\s+\S+"#, options: .regularExpression) != nil else { return nil }
        return names
    }
}
