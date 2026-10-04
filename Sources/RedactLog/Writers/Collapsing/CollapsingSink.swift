// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import Synchronization

/// A sink that says a repeated line once and then counts.
///
/// Repetition here is not the ordinary case — it is the failure case. A poller
/// that meets an unreachable host writes the same sentence every thirty
/// seconds for as long as the network is away; a rate limit answers the same
/// 429 to every retry; a caller refused an operation it believes is supported
/// asks again in a loop. None of the three is hypothetical.
/// Those are the runs a log is read for, and they are the runs it is least
/// readable in.
///
/// **The count is not enough on its own.** "Repeated seventeen times" without
/// a span is worse than seventeen lines: a reader cannot tell a second from an
/// hour. The summary carries both.
///
/// **A summary is never held for ever.** It is written when a different line
/// arrives, when the window closes, when the count reaches its cap, or when
/// the process flushes — whichever comes first. There is deliberately no timer
/// inside: a background task per sink, running for the life of the process to
/// tidy a log, is a poor trade. What that costs is one case — a run that goes
/// completely quiet holds its last count until the flush — and it costs
/// nothing that matters, because the line itself is already written and only
/// its tally is waiting.
///
/// A decorator rather than a setting on each sink, and rather than something
/// in the facade: the facade is rebuilt per call and holds no state, while
/// what is worth collapsing differs by destination. A file wants it; the
/// console of a debugging tool does not, because somebody watching a retry
/// storm wants to see it storm.
public final class CollapsingSink: LogSink {
    private let inner: any LogSink
    private let window: TimeInterval
    private let cap: Int
    private let now: @Sendable () -> Date
    private let pending: Mutex<Repeat?> = Mutex(nil)

    /// - Parameters:
    ///   - inner: the sink that does the writing.
    ///   - window: how long a run of the same line may go on being counted
    ///     before it is summarised and started afresh.
    ///   - cap: how many repeats may be counted before the same happens. A
    ///     bound on the count as well as on the time, so a tight loop is
    ///     reported while it is still running.
    public init(
        _ inner: any LogSink,
        window: TimeInterval = 60,
        cap: Int = 1000,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.inner = inner
        self.window = window
        self.cap = cap
        self.now = now
    }

    public func accepts(_ level: LogLevel, in category: LogCategory) -> Bool {
        inner.accepts(level, in: category)
    }

    public func write(_ entry: LogEntry) {
        let moment = now()
        // What to write is decided under the lock; the writing itself happens
        // outside it. A sink may take a while — the file one hands over to a
        // queue, but nothing here promises that — and holding a lock across
        // somebody else's work is how a log becomes a bottleneck.
        let toWrite: [LogEntry] = pending.withLock { current in
            guard var run = current, run.matches(entry) else {
                let summary = current.flatMap { $0.summary(at: moment) }
                current = Repeat(entry: entry, since: moment)
                return [summary, entry].compactMap { $0 }
            }
            let expired = moment.timeIntervalSince(run.since) >= window
            guard !expired, run.count < cap else {
                let summary = run.summary(at: moment)
                current = Repeat(entry: entry, since: moment)
                // The line that ended the run is written again: a run cut by
                // its own length is still going on, and a reader who sees only
                // the summary would not know what is repeating.
                return [summary, entry].compactMap { $0 }
            }
            run.count += 1
            run.last = moment
            current = run
            return []
        }
        for line in toWrite { inner.write(line) }
    }

    public func flush() async {
        let summary = pending.withLock { current -> LogEntry? in
            let summary = current.flatMap { $0.summary(at: now()) }
            current = nil
            return summary
        }
        if let summary { inner.write(summary) }
        await inner.flush()
    }

    /// The line being repeated, when it started, when it last came round,
    /// and how many times it has.
    private struct Repeat {
        let entry: LogEntry
        let since: Date
        var last: Date
        var count: Int = 1

        init(entry: LogEntry, since: Date) {
            self.entry = entry
            self.since = since
            last = since
        }

        func matches(_ other: LogEntry) -> Bool {
            entry.level == other.level
                && entry.category == other.category
                && entry.message == other.message
                && entry.metadata == other.metadata
        }

        /// `nil` for a line that never repeated: there is nothing to say about
        /// it that the line itself has not.
        ///
        /// The span runs from the first line to the last repeat, not to the
        /// moment the run was closed: a run that ends because something else
        /// was said an hour later did not go on for an hour.
        func summary(at moment: Date) -> LogEntry? {
            guard count > 1 else { return nil }
            let span = max(0, last.timeIntervalSince(since))
            return LogEntry(
                level: entry.level,
                category: entry.category,
                message: "… previous line repeated \(count - 1) more times over "
                    + CollapsingSink.seconds(span),
                date: moment
            )
        }
    }

    /// A span to a tenth of a second, spelled with a point.
    ///
    /// Not `String(format: "%.1f", span)`: that spells the number the way the
    /// machine's locale does, and on a German machine the summary read
    /// `20,0s` — the same span in two spellings, depending on whose machine
    /// wrote the file. A log is parsed by tools before it is read by people,
    /// and a tool that reads `20.0` does not read `20,0`. So the tenths are
    /// worked out by hand and no locale is consulted at all.
    ///
    /// A span is the gap between two dates this sink itself took, so it is
    /// finite and it is not negative — except on a clock that was set back
    /// between them. That is not a span worth spelling, so anything under
    /// zero, and anything that is not a number, reads as no time at all.
    static func seconds(_ span: TimeInterval) -> String {
        guard span.isFinite, span > 0 else { return "0.0s" }
        let tenths = Int((span * 10).rounded())
        return "\(tenths / 10).\(tenths % 10)s"
    }
}
