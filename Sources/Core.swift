import Foundation

enum Connectivity: String { case online, offline, noNetwork }

struct Reading {
    var time: Double
    var state: Connectivity
    var interface: String
    var received: UInt64?
    var sent: UInt64?
    var latency: Double?
}

struct Span {
    var start: Double
    var end: Double
    var state: Connectivity
    var interface: String
    var session: String
    var received: Double?
    var sent: Double?
    var latency: Double?
}

struct TimelineBucket {
    var online = 0.0
    var offline = 0.0
}

struct OutageDetail {
    var start: Double
    var end: Double
    var interface: String
    var ongoing: Bool
    var interrupted: Bool
}

struct Summary {
    var online = 0.0
    var offline = 0.0
    var wifi = 0.0
    var ethernet = 0.0
    var received = 0.0
    var sent = 0.0
    var trafficSeconds = 0.0
    var latencyTotal = 0.0
    var latencyWeight = 0.0
    var availability: Double? { online + offline > 0 ? 100 * online / (online + offline) : nil }
    var averageDownloadUsage: Double? { trafficSeconds > 0 ? received * 8 / trafficSeconds / 1_000_000 : nil }
    var averageUploadUsage: Double? { trafficSeconds > 0 ? sent * 8 / trafficSeconds / 1_000_000 : nil }
    var trafficCoverage: Double? { online > 0 ? 100 * trafficSeconds / online : nil }
    var latency: Double? { latencyWeight > 0 ? latencyTotal / latencyWeight : nil }

    mutating func add(_ span: Span, from: Double, to: Double) {
        let seconds = max(0, min(span.end, to) - max(span.start, from))
        guard seconds > 0, span.end > span.start else { return }
        let fraction = seconds / (span.end - span.start)
        if span.state == .online {
            online += seconds
            if let received = span.received, let sent = span.sent {
                self.received += received * fraction
                self.sent += sent * fraction
                trafficSeconds += seconds
            }
            if let latency = span.latency { latencyTotal += latency * seconds; latencyWeight += seconds }
        } else { offline += seconds }
        if span.interface == "Wi-Fi" || span.interface.hasPrefix("Wi-Fi|") { wifi += seconds }
        if span.interface == "Cabo" || span.interface.hasPrefix("Cabo|") { ethernet += seconds }
    }
}

// A lacuna rompe a sessão e nunca é convertida em uma queda.
final class Timeline {
    private(set) var previous: Reading?
    private(set) var session = ""
    private(set) var outageStart: Double?
    var saveSpan: (Span) -> Void = { _ in }
    var startOutage: (Double, String) -> Void = { _, _ in }
    var finishOutage: (Double, Bool) -> Void = { _, _ in }
    var event: (Double, String) -> Void = { _, _ in }

    func observe(_ reading: Reading) {
        if let old = previous, reading.time - old.time > 25 || reading.time < old.time {
            if outageStart != nil { finishOutage(old.time, true); outageStart = nil }
            event(reading.time, "Lacuna de monitoramento")
            previous = nil
            session = ""
        }
        if let old = previous {
            append(until: reading.time, next: reading)
            if old.interface != reading.interface { event(reading.time, "Interface: \(old.interface) → \(reading.interface)") }
            if old.state == .online && reading.state != .online {
                outageStart = reading.time
                startOutage(reading.time, reading.interface)
                session = ""
            } else if old.state != .online && reading.state == .online {
                if outageStart != nil { finishOutage(reading.time, false); outageStart = nil }
                session = UUID().uuidString
                event(reading.time, "Internet restabelecida")
            }
        } else {
            session = reading.state == .online ? UUID().uuidString : ""
            event(reading.time, reading.state == .online ? "Monitoramento iniciado com internet" : "Monitoramento iniciado sem internet")
        }
        previous = reading
    }

    private func append(until end: Double, next: Reading?) {
        guard let old = previous, end >= old.time, end - old.time <= 25 else { return }
        var received: Double?
        var sent: Double?
        if let next, next.interface == old.interface,
           let oldReceived = old.received, let oldSent = old.sent,
           let nextReceived = next.received, let nextSent = next.sent,
           nextReceived >= oldReceived, nextSent >= oldSent {
            received = Double(nextReceived - oldReceived)
            sent = Double(nextSent - oldSent)
        }
        saveSpan(Span(start: old.time, end: end, state: old.state, interface: old.interface,
                      session: session, received: received, sent: sent, latency: old.latency))
    }

    func suspend(at time: Double, reason: String) {
        let observedEnd = previous.map { time >= $0.time && time - $0.time <= 25 ? time : $0.time } ?? time
        append(until: observedEnd, next: nil)
        if outageStart != nil { finishOutage(observedEnd, true); outageStart = nil }
        event(time, reason)
        previous = nil
        session = ""
    }
}

func duration(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)min" }
    if s >= 60 { return "\(s / 60)min \(s % 60)s" }
    return "\(s)s"
}

func number(_ value: Double, digits: Int = 1) -> String {
    value.formatted(.number.locale(Locale(identifier: "pt_BR")).precision(.fractionLength(digits)))
}

func exportDayName(_ date: Date, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    return "conexao-\(formatter.string(from: date)).csv"
}
