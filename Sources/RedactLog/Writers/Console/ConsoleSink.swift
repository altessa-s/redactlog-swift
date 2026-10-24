// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// Lines to standard error, for a process with a person in front of it.
///
/// Standard error and not standard output, by this project's rule: the answer
/// of a command may be piped into a file, and its commentary must not land
/// there beside it.
///
/// **Not conditional on a terminal**, which is what this did at first. A tty
/// check reads as prudence and measures as a bug: piping a run into `head` or
/// into a file is exactly what somebody debugging does, and the check turned
/// the log off in the one case it had been switched on for. Whether a process
/// wants a console at all is the decision of its composition root — a
/// command-line tool installs one, a windowed application and an extension do
/// not — and that decision is made once, where it can be read.
public struct ConsoleSink: LogSink {
    private let minimum: LogLevel
    private let format: any LogFormatting

    /// The bare message by default: one command is running, the person
    /// watching knows what time it is and which tool they typed. A stamped
    /// format is one argument away when the run is long enough to want one.
    public init(minimum: LogLevel = .debug, format: any LogFormatting = MessageFormat()) {
        self.minimum = minimum
        self.format = format
    }

    public func accepts(_ level: LogLevel, in category: LogCategory) -> Bool {
        level >= minimum
    }

    public func write(_ entry: LogEntry) {
        #if canImport(Darwin)
        // `fputs` rather than `FileHandle.write`: one call instead of a `Data`
        // per line, and it reports a closed pipe by returning rather than by
        // raising an Objective-C exception, which Swift cannot catch. A log
        // that kills the process when its reader goes away would be worse than
        // no log.
        fputs(format.format(entry) + "\n", stderr)
        #else
        // Non-Apple C runtimes expose stderr as shared mutable state, which
        // Swift 6 rejects here; Foundation provides a concurrency-safe handle.
        try? FileHandle.standardError.write(contentsOf: Data((format.format(entry) + "\n").utf8))
        #endif
    }
}
