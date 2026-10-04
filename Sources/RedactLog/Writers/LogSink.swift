// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// One line, as it crosses out of the logging facade.
///
/// `message` is already rendered and already masked — that is the whole
/// contract, and the reason a sink is given this and not a `LogMessage`. A
/// sink that could reach the values could forget to mask one; this one cannot,
/// because by the time it is called there is nothing left to forget.
public struct LogEntry: Sendable {
    public let level: LogLevel
    public let category: LogCategory
    public let message: String
    /// The fields worth filtering on later, rendered and masked exactly as the
    /// message was. Empty for most lines, and empty costs nothing to print.
    public let metadata: [String: String]
    public let date: Date

    public init(
        level: LogLevel,
        category: LogCategory,
        message: String,
        metadata: [String: String] = [:],
        date: Date
    ) {
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
        self.date = date
    }

    /// The message and its fields as one line.
    ///
    /// Here rather than in each sink: three of them write text, and three
    /// spellings of the same fields would be three things to read differently
    /// in a report. Sorted by key, so two runs of the same code compare.
    ///
    /// One line, literally. A value tagged `.public` may still carry a line
    /// break — a status text off the wire, a multi-line description — and
    /// written as it is, the rest of it would read as a second entry that
    /// nobody logged, with whatever level and category the reader assumed.
    /// So a control character is spelled out, the way JSON spells it, and a
    /// line in a file is exactly what one call wrote.
    public var text: String {
        guard !metadata.isEmpty else { return Self.oneLine(message) }
        let fields = metadata.sorted { $0.key < $1.key }
            .map { "\(Self.oneLine($0.key))=\(Self.oneLine($0.value))" }
            .joined(separator: " ")
        return "\(Self.oneLine(message)) {\(fields)}"
    }

    static func oneLine(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\t" }) else {
            return text
        }
        var out = ""
        out.unicodeScalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out.unicodeScalars.append(scalar)
            case _ where scalar.value < 0x20:
                out += "\\u{" + String(scalar.value, radix: 16, uppercase: false) + "}"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

/// Somewhere lines go: the unified log, a terminal, a file.
///
/// **The threshold belongs here.** Whoever writes a line does not know, and
/// must not know, which sinks are listening or how much they want — that is a
/// property of where the process is running, settled once at its composition
/// root. The facade asks before it renders, so a line nobody would take costs
/// nothing to not write.
public protocol LogSink: Sendable {
    func accepts(_ level: LogLevel, in category: LogCategory) -> Bool
    func write(_ entry: LogEntry)

    /// Wait for whatever this sink has in flight.
    ///
    /// Most sinks have nothing: the system log and a terminal take a line and
    /// are done with it. A sink that writes somewhere slow does not make its
    /// caller wait — that is the rule — and the price of the rule is that a
    /// process which is about to exit has to say so, or the last lines are
    /// lost with it. A tool that runs for a second loses all of them.
    func flush() async
}

public extension LogSink {
    func flush() async {}
}
