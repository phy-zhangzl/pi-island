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

enum SessionDiscovery {
    static func scanAllSessions(debug: (String) -> Void = { _ in }) -> [SessionSnapshot] {
        let root = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".pi/agent/sessions", isDirectory: true)
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            debug("[SessionDiscovery] sessions root missing: \(root.path)")
            return []
        }

        let workspaceDirectories = (try? fm.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let sessionFiles = workspaceDirectories.flatMap { directoryURL -> [URL] in
            let values = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return [] }
            return (try? fm.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }
        .filter { $0.pathExtension == "jsonl" }

        var snapshotsByID: [String: SessionSnapshot] = [:]
        for fileURL in sessionFiles {
            guard let snapshot = parseSnapshot(from: fileURL, debug: debug) else { continue }

            if let existing = snapshotsByID[snapshot.id] {
                if snapshot.modifiedAt > existing.modifiedAt {
                    snapshotsByID[snapshot.id] = snapshot
                }
            } else {
                snapshotsByID[snapshot.id] = snapshot
            }
        }

        return snapshotsByID.values.sorted { lhs, rhs in
            if lhs.modifiedAt == rhs.modifiedAt {
                return lhs.id < rhs.id
            }
            return lhs.modifiedAt > rhs.modifiedAt
        }
    }

    private static func parseSnapshot(from fileURL: URL, debug: (String) -> Void) -> SessionSnapshot? {
        let modifiedAt = ((try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()).timeIntervalSince1970

        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            debug("[SessionDiscovery] unreadable session file: \(fileURL.path)")
            return nil
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else {
            debug("[SessionDiscovery] empty session file: \(fileURL.path)")
            return nil
        }

        var sessionID: String?
        var cwd: String?
        var name: String?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = entry["type"] as? String else {
                continue
            }

            if type == "session" {
                if let id = entry["id"] as? String, !id.isEmpty {
                    sessionID = id
                }
                if let sessionCWD = entry["cwd"] as? String, !sessionCWD.isEmpty {
                    cwd = sessionCWD
                }
            }

            if type == "session_info" || type == "session" {
                if let candidate = (entry["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
                    name = candidate
                }
            }
        }

        let fallbackCWD = decodedWorkspacePath(from: fileURL) ?? fileURL.deletingLastPathComponent().path
        let resolvedCWD = cwd ?? fallbackCWD
        let workspaceName = URL(fileURLWithPath: resolvedCWD).lastPathComponent.isEmpty ? "pi" : URL(fileURLWithPath: resolvedCWD).lastPathComponent
        let resolvedName = name ?? fileURL.deletingPathExtension().lastPathComponent
        let identity = sessionID.map { "pi:\($0)" } ?? "pi-file:\(fileURL.path)"

        return SessionSnapshot(
            id: identity,
            sessionID: sessionID,
            name: resolvedName,
            workspaceName: workspaceName,
            cwd: resolvedCWD,
            modifiedAt: modifiedAt,
            fileURL: fileURL
        )
    }

    private static func decodedWorkspacePath(from fileURL: URL) -> String? {
        let folder = fileURL.deletingLastPathComponent().lastPathComponent
        guard folder.hasPrefix("--"), folder.hasSuffix("--") else { return nil }
        let trimmed = String(folder.dropFirst(2).dropLast(2))
        let decoded = trimmed.replacingOccurrences(of: "-", with: "/")
        return decoded.hasPrefix("/") ? decoded : "/\(decoded)"
    }
}
