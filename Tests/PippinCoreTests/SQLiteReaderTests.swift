import Foundation
import SQLite3
import Testing

@testable import PippinCore

@Suite("SQLite reader")
struct SQLiteReaderTests {
    /// Builds a throwaway database that stands in for an app's private store.
    private func makeDatabase(in directory: URL, name: String = "store.db") throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: name).path(percentEncoded: false)

        var handle: OpaquePointer?
        #expect(sqlite3_open(path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }

        let schema = """
            CREATE TABLE messages (rowid INTEGER PRIMARY KEY, subject TEXT, sender TEXT, date INTEGER);
            INSERT INTO messages VALUES (1, 'Lunch', 'ann@example.com', 100);
            INSERT INTO messages VALUES (2, 'Invoice', 'bob@example.com', 200);
            INSERT INTO messages VALUES (3, 'O''Brien said "hi"', 'ann@example.com', 300);
            """
        #expect(sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK)
        return path
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "pippin sqlite \(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test("reads rows with bound parameters")
    func parameterizedQuery() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = try SQLiteReader(path: try makeDatabase(in: directory))

        let subjects = try reader.query(
            "SELECT subject FROM messages WHERE sender = ? ORDER BY date",
            parameters: [.text("ann@example.com")]
        ) { $0.string(at: 0) }

        #expect(subjects.compactMap { $0 } == ["Lunch", "O'Brien said \"hi\""])
    }

    @Test("a SQL payload in a parameter is data, not syntax", arguments: [
        "' OR 1=1 --",
        "'; DROP TABLE messages; --",
        "ann@example.com' UNION SELECT subject FROM messages --",
    ])
    func injectionIsInert(payload: String) throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = try SQLiteReader(path: try makeDatabase(in: directory))

        let rows = try reader.query(
            "SELECT subject FROM messages WHERE sender = ?",
            parameters: [.text(payload)]
        ) { $0.string(at: 0) }

        // Matches nothing, because it was compared as a literal sender address.
        #expect(rows.isEmpty)
        // And the table is still there.
        #expect(try reader.query("SELECT count(*) FROM messages") { $0.int(at: 0) }.first == 3)
    }

    @Test("the database is opened read-only")
    func readOnly() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = try SQLiteReader(path: try makeDatabase(in: directory))

        // Not a policy we intend to rely on alone, but the last line of defence:
        // this tier reads other applications' private stores and must never write
        // to one.
        #expect(throws: PippinError.self) {
            try reader.query("DELETE FROM messages") { _ in 0 }
        }
        #expect(try reader.query("SELECT count(*) FROM messages") { $0.int(at: 0) }.first == 3)
    }

    // MARK: Schema probe

    @Test("a matching schema probes clean")
    func probeSucceeds() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = try SQLiteReader(path: try makeDatabase(in: directory))

        #expect(throws: Never.self) {
            try reader.probe(["messages": ["subject", "sender", "date"]]).get()
        }
    }

    @Test("a missing column disables the backend rather than returning zero rows")
    func probeDetectsMissingColumn() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = try SQLiteReader(path: try makeDatabase(in: directory))

        // The failure this exists to prevent: a renamed column across an OS
        // release, silently yielding no results that read as "you have no mail".
        let result = reader.probe(["messages": ["subject", "conversation_id"]])
        guard case .failure(let error) = result else {
            Issue.record("probe should have failed")
            return
        }
        #expect(error.code == .backendUnavailable)
        #expect(error.hint.contains("conversation_id"))
        #expect(error.hint.contains("fallback"))
    }

    @Test("a missing table is caught too")
    func probeDetectsMissingTable() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reader = try SQLiteReader(path: try makeDatabase(in: directory))

        guard case .failure(let error) = reader.probe(["envelopes": ["id"]]) else {
            Issue.record("probe should have failed")
            return
        }
        #expect(error.code == .backendUnavailable)
    }

    @Test("a missing database file reports actionably")
    func missingFile() {
        let error = #expect(throws: PippinError.self) {
            try SQLiteReader(path: "/nonexistent/pippin/store.db")
        }
        #expect(error?.code == .backendUnavailable)
    }

    // MARK: Versioned path resolution

    @Test("a versioned path resolves to the newest match")
    func resolvesNewestVersion() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for version in ["V2", "V9", "V10"] {
            _ = try makeDatabase(in: root.appending(path: version), name: "Envelope Index")
        }

        let resolved = try SQLiteReader.resolveVersionedPath(
            root.appending(path: "V*").appending(path: "Envelope Index").path(percentEncoded: false))

        // V10 beats V9: compared numerically, not as text. A hard-coded version
        // is a guaranteed future outage, and so is a lexicographic sort.
        #expect(resolved.contains("/V10/"))
    }

    @Test("no match is an explicit error, not a silent fallback")
    func noVersionMatch() {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "pippin missing \(UUID().uuidString)")
        #expect(throws: PippinError.self) {
            try SQLiteReader.resolveVersionedPath(root.appending(path: "V*").path(percentEncoded: false))
        }
    }

    @Test("a path with no wildcard is returned when it exists")
    func plainPath() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = try makeDatabase(in: directory)
        #expect(try SQLiteReader.resolveVersionedPath(path) == path)
    }

    @Test("identifier quoting escapes embedded quotes")
    func identifierQuoting() {
        // Identifiers cannot be bound as parameters, so this is applied to table
        // names this repository authors — never to caller input.
        #expect(SQLiteReader.quoteIdentifier("messages") == "\"messages\"")
        #expect(SQLiteReader.quoteIdentifier("od\"d") == "\"od\"\"d\"")
    }
}
