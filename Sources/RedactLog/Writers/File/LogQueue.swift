// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import Synchronization

/// The lines waiting for the disk, and what happens when too many wait.
///
/// The sink does not make its caller wait — that is the whole point of it —
/// and something has to give when lines arrive faster than a disk takes them.
/// The choice is memory or lines, and it is lines: an unbounded queue turns a
/// storm of logging into a process the system kills for its footprint, and it
/// does so silently. A bounded one loses the oldest waiting lines and **says
/// how many**, which is a fact somebody reading the file can work with.
/// A class rather than a struct: it holds a `Mutex`, which is non-copyable,
/// and the sink that owns it is a value handed around by copy.
final class LogQueue: Sendable {
    /// What goes down the stream: an entry still to be formatted, or a
    /// request to be told when everything before it has been written.
    ///
    /// An entry rather than its text, because formatting is work — a date
    /// spelled out, a JSON object encoded — and the caller's thread is the
    /// one place this sink promises not to do any. The consumer formats, on
    /// its own time. What the sink itself has to say, such as how many
    /// entries it lost, is an entry too: there is no case for text already
    /// formatted, because a line that skipped the format is a line in the
    /// wrong shape for the file.
    enum Item: Sendable {
        case entry(LogEntry)
        case barrier(@Sendable () -> Void)
    }

    let items: AsyncStream<Item>
    private let feed: AsyncStream<Item>.Continuation
    private let dropped = Mutex(0)

    init(bufferedLines: Int) {
        (items, feed) = AsyncStream<Item>.makeStream(
            of: Item.self,
            // The newest are kept: during a storm the recent lines are the
            // ones that explain it, and the old ones are what the file
            // already holds.
            bufferingPolicy: .bufferingNewest(max(bufferedLines, 1))
        )
    }

    /// Hand an item over. `true` when it is on its way to the consumer, even
    /// if an older one had to make room for it; `false` when nothing will
    /// ever take it. What was made room for is counted rather than thrown
    /// away in silence.
    ///
    /// A barrier that falls out of the queue is answered here, at once.
    /// Somebody is suspended on it, and the stream will never reach it now —
    /// a dropped barrier that stayed silent would hold `flush()` for ever, and
    /// under exactly the load that a flush at exit is called to survive. Nor
    /// is it a lost line: nothing the file was supposed to hold went missing
    /// with it, so it does not count towards the marker.
    @discardableResult
    func send(_ item: Item) -> Bool {
        switch feed.yield(item) {
        case .enqueued:
            return true
        case .dropped(let lost):
            release(lost)
            return true
        case .terminated:
            release(item)
            return false
        @unknown default:
            return false
        }
    }

    private func release(_ item: Item) {
        switch item {
        case .entry: dropped.withLock { $0 += 1 }
        case .barrier(let done): done()
        }
    }

    /// How many lines have been lost and not yet reported, or `nil` when none
    /// have.
    var pendingDrops: Int? {
        let count = dropped.withLock { $0 }
        return count > 0 ? count : nil
    }

    /// Subtract what has been reported — and only that, because more may have
    /// been lost between reading the count and writing the line.
    func forgetDrops(_ count: Int) {
        dropped.withLock { $0 = max(0, $0 - count) }
    }
}
