import Foundation

struct SessionSnapshot: Identifiable, Equatable {
    let id: String
    let sessionID: String?
    let name: String
    let workspaceName: String
    let cwd: String
    let modifiedAt: TimeInterval
    let fileURL: URL

    var agentSession: AgentSession {
        AgentSession(
            id: id,
            workspaceName: workspaceName,
            name: name,
            cwd: cwd,
            terminalApp: nil,
            terminalSessionID: nil,
            state: .idle,
            detail: "Waiting for pi events",
            contextTokens: nil,
            contextWindow: nil,
            updatedAt: modifiedAt,
            duration: "now"
        )
    }
}

struct RecentSessionMetadata: Equatable {
    let id: String
    let workspaceName: String
    let name: String
    let cwd: String
    let modifiedAt: TimeInterval
}

enum SessionDiscovery {
    private struct RecentCacheEntry {
        let modifiedAt: TimeInterval
        let metadata: RecentSessionMetadata
    }

    private static let recentCacheLock = NSLock()
    private static var recentCache: [String: RecentCacheEntry] = [:]
    private static let maxReadBytes = 16 * 1024

    static func mostRecentSession(modifiedWithin seconds: TimeInterval = 10, debug: (String) -> Void = { _ in }) -> RecentSessionMetadata? {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pi/agent/sessions", isDirectory: true)
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            debug("[SessionDiscovery] sessions root missing: \(root.path)")
            return nil
        }

        let workspaceDirectories = (try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let now = Date().timeIntervalSince1970
        var bestURL: URL?
        var bestModifiedAt: TimeInterval = 0

        for directoryURL in workspaceDirectories {
            let values = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }

            let files = (try? fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for fileURL in files where fileURL.pathExtension == "jsonl" {
                let modifiedAt = ((try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast).timeIntervalSince1970
                guard now - modifiedAt <= seconds else { continue }
                if modifiedAt > bestModifiedAt {
                    bestModifiedAt = modifiedAt
                    bestURL = fileURL
                }
            }
        }

        guard let fileURL = bestURL else { return nil }
        return metadata(for: fileURL, modifiedAt: bestModifiedAt, debug: debug)
    }

    private static func metadata(for fileURL: URL, modifiedAt: TimeInterval, debug: (String) -> Void) -> RecentSessionMetadata {
        let cacheKey = fileURL.path
        recentCacheLock.lock()
        if let cached = recentCache[cacheKey], cached.modifiedAt == modifiedAt {
            recentCacheLock.unlock()
            return cached.metadata
        }
        recentCacheLock.unlock()

        let fallbackCWD = decodedWorkspacePath(from: fileURL) ?? fileURL.deletingLastPathComponent().path
        let fallbackName = fileURL.deletingPathExtension().lastPathComponent
        var resolvedCWD = fallbackCWD
        var resolvedName = fallbackName

        if let prefix = readPrefix(from: fileURL, maxBytes: maxReadBytes) {
            let lines = prefix.split(separator: "\n", omittingEmptySubsequences: true)
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = entry["type"] as? String else {
                    continue
                }

                if type == "session", let candidate = entry["cwd"] as? String, !candidate.isEmpty {
                    resolvedCWD = candidate
                }

                if (type == "session_info" || type == "session"),
                   let candidate = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !candidate.isEmpty {
                    resolvedName = candidate
                    break
                }
            }
        } else {
            debug("[SessionDiscovery] unreadable fallback session file: \(fileURL.path)")
        }

        let workspaceName = URL(fileURLWithPath: resolvedCWD).lastPathComponent.isEmpty ? "pi" : URL(fileURLWithPath: resolvedCWD).lastPathComponent
        let metadata = RecentSessionMetadata(
            id: "pi-file:\(fileURL.path)",
            workspaceName: workspaceName,
            name: resolvedName,
            cwd: resolvedCWD,
            modifiedAt: modifiedAt
        )

        recentCacheLock.lock()
        recentCache[cacheKey] = RecentCacheEntry(modifiedAt: modifiedAt, metadata: metadata)
        recentCacheLock.unlock()
        return metadata
    }

    private static func readPrefix(from fileURL: URL, maxBytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        let data = try? handle.read(upToCount: maxBytes)
        guard let data, !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodedWorkspacePath(from fileURL: URL) -> String? {
        let folder = fileURL.deletingLastPathComponent().lastPathComponent
        guard folder.hasPrefix("--"), folder.hasSuffix("--") else { return nil }
        let trimmed = String(folder.dropFirst(2).dropLast(2))
        let decoded = trimmed.replacingOccurrences(of: "-", with: "/")
        return decoded.hasPrefix("/") ? decoded : "/\(decoded)"
    }
}
