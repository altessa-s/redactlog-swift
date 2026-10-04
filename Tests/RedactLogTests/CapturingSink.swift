// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
@testable import RedactLog
import Synchronization

/// A sink that keeps what it was given, so a test can say what was logged.
///
/// Here rather than in each test file for the reason the other doubles are
/// here: three suites already want to ask this question — that a token never
/// reached a line, that a failure said which document it was about, that a
/// level nobody listens to costs nothing — and three copies of a recorder
/// would answer it three slightly different ways.
///
/// Linked by test bundles only. A recorder in a shipped process would be a
/// second place the user's lines pile up in memory.
public final class CapturingSink: LogSink {
    private let taken: Mutex<[LogEntry]> = Mutex([])
    private let minimum: LogLevel
    private let only: LogCategory?

    /// `minimum` and `only` are this sink's own thresholds, exactly as a real
    /// sink's are — which is also how a test says "nobody is listening" and
    /// asks what that costs.
    public init(minimum: LogLevel = .debug, only: LogCategory? = nil) {
        self.minimum = minimum
        self.only = only
    }

    public var entries: [LogEntry] { taken.withLock { $0 } }
    public var messages: [String] { entries.map(\.message) }
    public var text: String { messages.joined(separator: "\n") }

    public func accepts(_ level: LogLevel, in category: LogCategory) -> Bool {
        level >= minimum && (only == nil || only == category)
    }

    public func write(_ entry: LogEntry) {
        taken.withLock { $0.append(entry) }
    }
}
