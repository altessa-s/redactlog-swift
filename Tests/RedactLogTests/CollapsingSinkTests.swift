// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
@testable import RedactLog
import Synchronization
import Testing

// Repetition is the failure case — a poller against an unreachable host, a
// retry storm — and these are about what a reader sees instead of the storm:
// the line once, then how many more and over how long. The clock is the
// test's, so a minute passes when the test says it does.

/// A sink that keeps what it was given and counts how often it was flushed.
private final class Recorder: LogSink {
    private let state = Mutex<(entries: [LogEntry], flushes: Int)>(([], 0))

    var messages: [String] { state.withLock { $0.entries.map(\.message) } }
    var flushes: Int { state.withLock { $0.flushes } }

    func accepts(_ level: LogLevel, in category: LogCategory) -> Bool { level >= .info }
    func write(_ entry: LogEntry) { state.withLock { $0.entries.append(entry) } }
    func flush() async { state.withLock { $0.flushes += 1 } }
}

private final class Clock: Sendable {
    private let now = Mutex(Date(timeIntervalSince1970: 1_787_757_030))
    func read() -> Date { now.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { now.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

private func line(_ message: String, metadata: [String: String] = [:]) -> LogEntry {
    LogEntry(level: .info, category: .sync, message: message, metadata: metadata, date: Date())
}

@Test("A repeated line is written once, and the rest are a count with a span")
func repeatsAreCounted() {
    let inner = Recorder()
    let clock = Clock()
    let sink = CollapsingSink(inner, now: clock.read)

    sink.write(line("host unreachable"))
    clock.advance(10)
    sink.write(line("host unreachable"))
    clock.advance(10)
    sink.write(line("host unreachable"))
    clock.advance(30)
    sink.write(line("host back"))

    // The span runs to the last repeat, not to the line that ended the run:
    // the repeats stopped at twenty seconds, and the next line came at fifty.
    #expect(inner.messages == [
        "host unreachable",
        "… previous line repeated 2 more times over 20.0s",
        "host back",
    ])
}

@Test("A line that never repeated has nothing said about it")
func singlesHaveNoSummary() {
    let inner = Recorder()
    let sink = CollapsingSink(inner, now: Clock().read)

    sink.write(line("one"))
    sink.write(line("two"))
    sink.write(line("one"))

    #expect(inner.messages == ["one", "two", "one"])
}

@Test("The same words with different fields are different lines")
func metadataTellsLinesApart() {
    let inner = Recorder()
    let sink = CollapsingSink(inner, now: Clock().read)

    sink.write(line("refused", metadata: ["status": "429"]))
    sink.write(line("refused", metadata: ["status": "503"]))
    sink.write(line("refused", metadata: ["status": "503"]))

    #expect(inner.messages.prefix(2) == ["refused", "refused"])
    #expect(inner.messages.count == 2, "a line with other fields was counted as a repeat")
}

@Test("A run that outlives the window is summarised and started afresh")
func theWindowCloses() {
    let inner = Recorder()
    let clock = Clock()
    let sink = CollapsingSink(inner, window: 60, now: clock.read)

    sink.write(line("still waiting"))
    clock.advance(30)
    sink.write(line("still waiting"))
    clock.advance(31)
    // Sixty-one seconds in: the run is closed, and the line that closed it
    // is written again, so a reader knows what is still repeating.
    sink.write(line("still waiting"))

    #expect(inner.messages == [
        "still waiting",
        "… previous line repeated 1 more times over 30.0s",
        "still waiting",
    ])
}

@Test("A run that reaches the cap is reported while it is still going")
func theCapCloses() {
    let inner = Recorder()
    let sink = CollapsingSink(inner, cap: 3, now: Clock().read)

    for _ in 1...5 { sink.write(line("tight loop")) }

    // Three counted, the fourth closes the run and is written; the fifth is
    // the start of the next count and is still pending.
    #expect(inner.messages == [
        "tight loop",
        "… previous line repeated 2 more times over 0.0s",
        "tight loop",
    ])
}

@Test("A flush says what was pending and reaches the sink behind")
func flushWritesThePendingCount() async {
    let inner = Recorder()
    let clock = Clock()
    let sink = CollapsingSink(inner, now: clock.read)

    sink.write(line("quiet run"))
    clock.advance(5)
    sink.write(line("quiet run"))
    await sink.flush()

    #expect(inner.messages == ["quiet run", "… previous line repeated 1 more times over 5.0s"])
    #expect(inner.flushes == 1, "the inner sink was not asked to flush")

    // And nothing is said twice: a second flush has nothing pending.
    await sink.flush()
    #expect(inner.messages.count == 2)
}

@Test("What the decorator accepts is what the sink behind it accepts")
func acceptsIsDelegated() {
    let sink = CollapsingSink(Recorder())
    #expect(!sink.accepts(.debug, in: .sync))
    #expect(sink.accepts(.info, in: .sync))
}

// The span goes into a file that tools parse, and `String(format:)` spells a
// number the way the machine's locale does.
@Test("The span is spelled with a point on a machine whose locale writes a comma")
func theSpanIgnoresTheLocale() {
    // What the locale-dependent spelling gives on a German machine, so that
    // this test is about something.
    #expect(String(format: "%.1f", locale: Locale(identifier: "de_DE"), 20.0) == "20,0")

    #expect(CollapsingSink.seconds(20) == "20.0s")
    #expect(CollapsingSink.seconds(0) == "0.0s")
    #expect(CollapsingSink.seconds(0.96) == "1.0s")
    #expect(CollapsingSink.seconds(61.26) == "61.3s")
    #expect(CollapsingSink.seconds(-1.5) == "0.0s")
    #expect(CollapsingSink.seconds(.nan) == "0.0s")
}
