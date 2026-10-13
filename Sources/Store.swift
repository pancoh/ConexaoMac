import Foundation
import SQLite3
import Darwin

struct StoreError: Error, CustomStringConvertible, LocalizedError {
    let description: String
    var errorDescription: String? { description }
}

enum HistorySection: Int {
    case outages, sessions, speeds, events
    var limit: Int { self == .sessions ? 100 : 200 }
}

struct HistoryPage {
    let rows: [[String]]
    let hasMore: Bool
    var notice: String {
        hasMore ? "Mostrando os \(rows.count) registros mais recentes. Há outros registros neste dia." : "\(rows.count) registro(s) neste dia."
    }
}

final class Store {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    let path: String
    var lastError: String?
    private var errorScopeDepth = 0

    // Uma atualização reúne várias consultas sem esconder uma falha intermediária.
    func withErrorScope<T>(_ body: () throws -> T) rethrows -> T {
        beginOperation()
        errorScopeDepth += 1
        defer { errorScopeDepth -= 1 }
        return try body()
    }
    private func beginOperation() {
        if errorScopeDepth == 0 { lastError = nil }
    }

    init(path: String) throws {
        self.path = path
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw StoreError(description: "Não foi possível abrir o histórico.") }
        sqlite3_busy_timeout(db, 1000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL; PRAGMA cache_size=-512;")
        try execute("""
        CREATE TABLE IF NOT EXISTS spans(start REAL, end REAL, state TEXT, interface TEXT, session TEXT, received REAL, sent REAL, latency REAL);
        CREATE INDEX IF NOT EXISTS spans_time ON spans(end);
        CREATE INDEX IF NOT EXISTS spans_session ON spans(session);
        CREATE TABLE IF NOT EXISTS outages(start REAL, end REAL, interface TEXT, interrupted INTEGER DEFAULT 0);
        CREATE TABLE IF NOT EXISTS events(time REAL, message TEXT);
        CREATE TABLE IF NOT EXISTS speeds(time REAL, session TEXT, interface TEXT, download REAL, upload REAL);
        CREATE INDEX IF NOT EXISTS speeds_time ON speeds(time);
        """)
        // Uma execução anterior interrompida só comprova observação até o último intervalo.
        try execute("UPDATE outages SET end=MAX(start,COALESCE((SELECT MAX(end) FROM spans),start)),interrupted=1 WHERE end IS NULL;")
    }
    deinit { sqlite3_close(db) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError(description: String(cString: sqlite3_errmsg(db))) }
    }
    private func statement(_ sql: String) -> OpaquePointer? {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK else { lastError = String(cString: sqlite3_errmsg(db)); return nil }
        return s
    }
    private func bind(_ s: OpaquePointer, _ values: [Any?]) {
        for (i, value) in values.enumerated() {
            let index = Int32(i + 1)
            if let text = value as? String { sqlite3_bind_text(s, index, text, -1, transient) }
            else if let number = value as? Double { sqlite3_bind_double(s, index, number) }
            else { sqlite3_bind_null(s, index) }
        }
    }
    private func nextRow(_ s: OpaquePointer) throws -> Bool {
        let result = sqlite3_step(s)
        if result == SQLITE_ROW { return true }
        if result == SQLITE_DONE { return false }
        let message = String(cString: sqlite3_errmsg(db))
        lastError = message
        throw StoreError(description: message)
    }
    func write(_ sql: String, _ values: [Any?] = []) {
        beginOperation()
        guard let s = statement(sql) else { return }
        defer { sqlite3_finalize(s) }
        bind(s, values)
        var result = sqlite3_step(s)
        while result == SQLITE_ROW { result = sqlite3_step(s) }
        if result != SQLITE_DONE { lastError = String(cString: sqlite3_errmsg(db)) }
    }
    func rows(_ sql: String, _ values: [Any?] = []) -> [[String]] {
        do { return try checkedRows(sql, values) }
        catch { lastError = error.localizedDescription; return [] }
    }
    func checkedRows(_ sql: String, _ values: [Any?] = []) throws -> [[String]] {
        beginOperation()
        return try readRows(sql, values)
    }
    private func readRows(_ sql: String, _ values: [Any?]) throws -> [[String]] {
        guard let s = statement(sql) else { throw StoreError(description: lastError ?? "Erro de leitura") }
        defer { sqlite3_finalize(s) }
        bind(s, values)
        var result: [[String]] = []
        while try nextRow(s) {
            result.append((0..<sqlite3_column_count(s)).map { index in
                sqlite3_column_text(s, index).map { String(cString: $0) } ?? ""
            })
        }
        return result
    }
    func save(_ span: Span) {
        write("INSERT INTO spans VALUES(?,?,?,?,?,?,?,?)", [span.start, span.end, span.state.rawValue, span.interface, span.session, span.received, span.sent, span.latency])
    }
    func event(_ time: Double, _ message: String) { write("INSERT INTO events VALUES(?,?)", [time, message]) }
    func beginOutage(_ time: Double, _ interface: String) { write("INSERT INTO outages(start,interface) VALUES(?,?)", [time, interface]) }
    func endOutage(_ time: Double, _ interrupted: Bool) { write("UPDATE outages SET end=?,interrupted=? WHERE end IS NULL", [time, interrupted ? 1.0 : 0.0]) }
    func saveSpeed(_ time: Double, _ session: String, _ interface: String, _ down: Double, _ up: Double) {
        write("INSERT INTO speeds VALUES(?,?,?,?,?)", [time, session, interface, down, up])
    }
    func summary(from: Double, to: Double, session: String? = nil) -> Summary {
        beginOperation()
        let predicate = session == nil ? "" : " AND session=?"
        guard let s = statement("SELECT start,end,state,interface,session,received,sent,latency FROM spans WHERE end>? AND start<?" + predicate) else { return Summary() }
        defer { sqlite3_finalize(s) }
        bind(s, [from, to] + (session.map { [$0 as Any?] } ?? []))
        var total = Summary()
        do {
            while try nextRow(s) {
                func str(_ index: Int32) -> String { sqlite3_column_text(s, index).map { String(cString: $0) } ?? "" }
                total.add(Span(start: sqlite3_column_double(s, 0), end: sqlite3_column_double(s, 1),
                               state: Connectivity(rawValue: str(2)) ?? .offline, interface: str(3), session: str(4),
                               received: sqlite3_column_type(s, 5) == SQLITE_NULL ? nil : sqlite3_column_double(s, 5),
                               sent: sqlite3_column_type(s, 6) == SQLITE_NULL ? nil : sqlite3_column_double(s, 6),
                               latency: sqlite3_column_type(s, 7) == SQLITE_NULL ? nil : sqlite3_column_double(s, 7)), from: from, to: to)
            }
        } catch { lastError = error.localizedDescription; return Summary() }
        return total
    }
    func speeds(from: Double, to: Double, session: String? = nil) -> (Double?, Double?, Int) {
        let extra = session == nil ? "" : " AND session=?"
        let row = rows("SELECT AVG(download),AVG(upload),COUNT(*) FROM speeds WHERE time>=? AND time<?" + extra, [from, to] + (session.map { [$0 as Any?] } ?? [])).first ?? ["", "", "0"]
        return (Double(row[0]), Double(row[1]), Int(row[2]) ?? 0)
    }
    // Consulta somente o dia selecionado e mantém no máximo 288 intervalos na memória.
    func dayTimeline(from: Double, to: Double, count: Int = 288) -> [TimelineBucket] {
        beginOperation()
        guard to > from, count > 0 else { return [] }
        let count = min(count, 288)
        let width = (to - from) / Double(count)
        guard let s = statement("SELECT start,end,state FROM spans WHERE end>? AND start<? ORDER BY start") else { return [] }
        defer { sqlite3_finalize(s) }
        bind(s, [from, to])
        var buckets = Array(repeating: TimelineBucket(), count: count)
        do {
            while try nextRow(s) {
                let start = max(from, sqlite3_column_double(s, 0))
                let end = min(to, sqlite3_column_double(s, 1))
                guard end > start else { continue }
                let online = sqlite3_column_text(s, 2).map { String(cString: $0) } == "online"
                let first = max(0, min(count - 1, Int((start - from) / width)))
                let last = max(first, min(count - 1, Int(ceil((end - from) / width)) - 1))
                for index in first...last {
                    let lower = from + Double(index) * width
                    let seconds = max(0, min(end, lower + width) - max(start, lower))
                    if online { buckets[index].online += seconds }
                    else { buckets[index].offline += seconds }
                }
            }
        } catch { return [] }
        return buckets
    }
    func outages(from: Double, to: Double, now: Double) -> [[String]] {
        rows("SELECT start,MIN(COALESCE(end,?),?),interface,interrupted FROM outages WHERE start<? AND COALESCE(end,?)>? ORDER BY start DESC LIMIT 200", [now, to, to, now, from])
    }
    func outageDetails(from: Double, to: Double, now: Double) -> [OutageDetail] {
        rows("SELECT start,COALESCE(end,?),interface,end IS NULL,interrupted FROM outages WHERE start<? AND COALESCE(end,?)>? ORDER BY start LIMIT 7", [now, to, now, from]).compactMap { row in
            guard let start = Double(row[0]), let end = Double(row[1]) else { return nil }
            return OutageDetail(start: start, end: end, interface: row[2], ongoing: row[3] == "1", interrupted: row[4] == "1")
        }
    }
    func outageStats(from: Double, to: Double, now: Double) -> (Int, Double) {
        let row = rows("SELECT COUNT(CASE WHEN start>=? THEN 1 END),MAX(MAX(0,MIN(COALESCE(end,?),?)-MAX(start,?))) FROM outages WHERE start<? AND COALESCE(end,?)>?", [from, now, to, from, to, now, from]).first ?? ["0", "0"]
        return (Int(row[0]) ?? 0, Double(row[1]) ?? 0)
    }
    func prune(now: Double) {
        withErrorScope {
            let cutoff = now - 90 * 86400
            write("DELETE FROM spans WHERE end<?", [cutoff])
            write("DELETE FROM events WHERE time<?", [cutoff])
            write("DELETE FROM speeds WHERE time<?", [cutoff])
            write("DELETE FROM outages WHERE end<?", [cutoff])
            write("PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }
    func history(from: Double, to: Double, now: Double, section: HistorySection) throws -> HistoryPage {
        let sql: String
        let values: [Any?]
        switch section {
        case .outages:
            sql = "SELECT start,MIN(COALESCE(end,?),?),interface,interrupted FROM outages WHERE start<? AND COALESCE(end,?)>? ORDER BY start DESC"
            values = [now, to, to, now, from]
        case .sessions:
            sql = "SELECT MIN(start),MAX(end),GROUP_CONCAT(DISTINCT interface),SUM(MIN(end,?)-MAX(start,?)),session FROM spans WHERE end>? AND start<? AND state='online' GROUP BY session ORDER BY MIN(start) DESC"
            values = [to, from, from, to]
        case .speeds:
            sql = "SELECT time,interface,download,upload FROM speeds WHERE time>=? AND time<? ORDER BY time DESC"
            values = [from, to]
        case .events:
            sql = "SELECT time,message FROM events WHERE time>=? AND time<? ORDER BY time DESC"
            values = [from, to]
        }
        let rows = try checkedRows(sql + " LIMIT \(section.limit + 1)", values)
        return HistoryPage(rows: Array(rows.prefix(section.limit)), hasMore: rows.count > section.limit)
    }

    static func exportTargets(for url: URL) -> [URL] {
        [url, url.deletingPathExtension().appendingPathExtension("testes.csv"), url.deletingPathExtension().appendingPathExtension("quedas.csv")]
    }
    func export(from: Double, to: Double, to url: URL) throws {
        beginOperation()
        let manager = FileManager.default
        let targets = Self.exportTargets(for: url)
        if let existing = targets.first(where: { manager.fileExists(atPath: $0.path) }) {
            throw StoreError(description: "O arquivo \(existing.lastPathComponent) já existe. Escolha outro nome para preservar os três arquivos da exportação anterior.")
        }
        let stage = url.deletingLastPathComponent().appendingPathComponent(".conexao-export-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: stage) }
        let stagedMain = stage.appendingPathComponent(url.lastPathComponent)
        try exportFiles(from: from, to: to, to: stagedMain)
        var created: [URL] = []
        do {
            for (source, target) in zip(Self.exportTargets(for: stagedMain), targets) {
                // A criação exclusiva protege também contra colisões surgidas após a consulta inicial.
                let descriptor = target.path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, 0o600) }
                guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                created.append(target)
                let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                defer { try? output.close() }
                let input = try FileHandle(forReadingFrom: source)
                defer { try? input.close() }
                while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    try output.write(contentsOf: chunk)
                }
                try output.synchronize()
            }
        } catch {
            for target in created { try? manager.removeItem(at: target) }
            throw error
        }
    }
    private func exportFiles(from: Double, to: Double, to url: URL) throws {
        guard let s = statement("SELECT start,end,state,interface,session,received,sent,latency FROM spans WHERE end>? AND start<? ORDER BY start") else { throw StoreError(description: lastError ?? "Erro de leitura") }
        defer { sqlite3_finalize(s) }
        bind(s, [from, to])
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.write(contentsOf: Data("inicio_unix,fim_unix,estado,interface,sessao,bytes_recebidos,bytes_enviados,latencia_ms\n".utf8))
        while try nextRow(s) {
            let line = (0..<8).map { i in
                let value = sqlite3_column_text(s, Int32(i)).map { String(cString: $0) } ?? ""
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }.joined(separator: ",") + "\n"
            try handle.write(contentsOf: Data(line.utf8))
        }
        // Abas adicionais preservam os testes e as quedas sem carregar os intervalos na memória.
        for (suffix, sql, headers) in [
            ("testes", "SELECT time,session,interface,download,upload FROM speeds WHERE time>=? AND time<? ORDER BY time", "instante_unix,sessao,interface,download_mbps,upload_mbps"),
            ("quedas", "SELECT start,end,interface,interrupted FROM outages WHERE COALESCE(end,1e20)>? AND start<? ORDER BY start", "inicio_unix,fim_unix,interface,observacao_interrompida")
        ] {
            let lines = try readRows(sql, [from, to]).map { $0.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",") }
            let target = url.deletingPathExtension().appendingPathExtension(suffix + ".csv")
            try (headers + "\n" + lines.joined(separator: "\n") + "\n").write(to: target, atomically: true, encoding: .utf8)
        }
    }
}
