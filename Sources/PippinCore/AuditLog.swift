import CryptoKit
import Foundation

/// One JSON line per mutation attempt, at
/// `~/Library/Application Support/Pippin/audit.jsonl`.
///
/// Cheap, and it is the only forensic trail for "what did the agent just do".
/// Attempts are recorded, not just successes: a refused delete is exactly the
/// event worth being able to find later.
public actor AuditLog {
    public enum Outcome: String, Codable, Sendable {
        case succeeded
        case failed
        case refused
    }

    public struct Entry: Codable, Sendable {
        public let timestamp: String
        public let tool: String
        public let module: String?
        public let ids: [String]
        public let outcome: Outcome
        public let error: String?
        /// A digest, never the values. Arguments carry note bodies, mail
        /// subjects, and search terms; the audit trail must not become a second
        /// copy of the user's data.
        public let argumentsDigest: String?
    }

    /// Rotated rather than unbounded: this file is written on every mutation for
    /// the life of the machine.
    public static let maximumBytes = 5 * 1024 * 1024

    private let url: URL
    private let now: @Sendable () -> Date

    public init(url: URL = AuditLog.defaultURL, now: @escaping @Sendable () -> Date = Date.init) {
        self.url = url
        self.now = now
    }

    public static var defaultURL: URL {
        Config.defaultDirectory.appending(path: "audit.jsonl")
    }

    public static func digest(_ arguments: [String: String]) -> String {
        let canonical = arguments.keys.sorted()
            .map { "\($0)=\(arguments[$0] ?? "")" }
            .joined(separator: "\u{0}")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public func record(
        tool: String,
        module: String? = nil,
        ids: [String] = [],
        outcome: Outcome,
        error: PippinError? = nil,
        arguments: [String: String]? = nil
    ) {
        let entry = Entry(
            timestamp: ISO8601.string(from: now()),
            tool: tool,
            module: module,
            ids: ids,
            outcome: outcome,
            error: error.map { failure in failure.detail ?? failure.code.rawValue },
            argumentsDigest: arguments.map { AuditLog.digest($0) }
        )
        append(entry)
    }

    private func append(_ entry: Entry) {
        guard let line = try? JSONEncoder().encode(entry) else { return }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            rotateIfNeeded()

            if !FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                FileManager.default.createFile(
                    atPath: url.path(percentEncoded: false),
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line + Data("\n".utf8))
        } catch {
            // Never fail a user's operation because the audit trail could not be
            // written. Losing a line is bad; refusing the delete they asked for
            // because of it is worse.
        }
    }

    private func rotateIfNeeded() {
        let path = url.path(percentEncoded: false)
        guard
            let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber,
            size.intValue >= Self.maximumBytes
        else { return }

        // One generation kept. More would be a retention policy, which is a
        // decision the user has not been asked to make.
        let rotated = url.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
    }

    /// Reads back the log. Exists for tests and for the eventual "what happened"
    /// view; the file is plain JSONL precisely so it needs no special tooling.
    public func entries() throws -> [Entry] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
    }
}
