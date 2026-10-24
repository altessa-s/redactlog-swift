// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
@testable import RedactLog
import Synchronization
import Testing

// Over a temporary directory, the way the index store's tests run over a
// temporary file: what is being checked is the file this writes, and a fake
// file system would be checking the fake.

/// A directory of its own per case, removed after it.
private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "redactlog-filesink-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// What the file holds, line by line.
///
/// Read only after `flush()`: the sink hands its lines to a stream and
/// returns, and the barrier is the one wait that says nothing about the
/// clock. A deadline would measure the machine, not the sink — under a full
/// run the writer and the test itself both wait for a pool thread, and how
/// long is the other tests' business.
private func contents(of file: URL) -> [String] {
    ((try? String(contentsOf: file, encoding: .utf8)) ?? "")
        .split(separator: "\n").map(String.init)
}

@Test("Lines land in the file, in the order they were written")
func linesKeepTheirOrder() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sink = FileSink(directory: directory, name: "test.log", minimum: .debug)

    for number in 1...50 {
        sink.write(
            LogEntry(level: .info, category: .sync, message: "line \(number)", date: Date())
        )
    }

    await sink.flush()

    let lines = contents(of: directory.appending(path: "test.log"))
    #expect(lines.count == 50)
    // The order is the whole reason there is one writer behind a stream: a
    // task per line would land them in whatever order the runtime felt like.
    #expect(lines.first?.hasSuffix("line 1") == true)
    #expect(lines.last?.hasSuffix("line 50") == true)
    #expect(lines.enumerated().allSatisfy { $0.element.hasSuffix("line \($0.offset + 1)") })
    // And each carries when, how loud and from where.
    #expect(lines[0].contains("[info] sync:"))
}

@Test("The file rotates at its limit, and keeps exactly one older file")
func theFileRotates() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let current = directory.appending(path: "test.log")
    let previous = directory.appending(path: "test.log.1")
    // Small enough that a handful of lines pass it, and nothing about the
    // rotation depends on the number being small.
    let sink = FileSink(
        directory: directory,
        name: "test.log",
        rotation: LogRotation(maxFileSize: 512, maxArchives: 1),
        minimum: .debug
    )

    for number in 1...40 {
        sink.write(
            LogEntry(
                level: .info,
                category: .cloud,
                message: String(repeating: "x", count: 40) + " \(number)",
                date: Date()
            )
        )
    }

    await sink.flush()

    // The last line written is in the current file; the rotation happened at
    // least once, so the previous one exists too.
    let latest = contents(of: current)
    #expect(latest.last?.hasSuffix(" 40") == true)
    #expect(FileManager.default.fileExists(atPath: previous.path), "nothing was rotated out")

    // One archive was asked for, so two files exist and no more.
    let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(Set(written) == ["test.log", "test.log.1"])
    // The current file is the newer one: what rotated out ends before it
    // begins.
    let older = try #require(try? String(contentsOf: previous, encoding: .utf8))
    #expect(!older.contains(" 40"))
}

// How many are kept is the installer's business, and the numbers differ:
// a shipped app keeps little, a debugging session on a spike may want the
// last several runs.
@Test("Numbered archives shift up, and the oldest falls off the end")
func numberedArchivesAreKeptToTheLimit() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sink = FileSink(
        directory: directory,
        name: "test.log",
        rotation: LogRotation(maxFileSize: 200, maxArchives: 2),
        minimum: .debug
    )

    // Every line is past the limit on its own, so this is one rotation apiece.
    for number in 1...6 {
        sink.write(
            LogEntry(
                level: .info,
                category: .cloud,
                message: String(repeating: "y", count: 200) + " \(number)",
                date: Date()
            )
        )
    }
    await sink.flush()

    let written = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    #expect(written == ["test.log", "test.log.1", "test.log.2"], "kept \(written.sorted())")
    // `.1` is always the most recent archive, `.2` the one before it.
    let current = try String(contentsOf: directory.appending(path: "test.log"), encoding: .utf8)
    let first = try String(contentsOf: directory.appending(path: "test.log.1"), encoding: .utf8)
    let second = try String(contentsOf: directory.appending(path: "test.log.2"), encoding: .utf8)
    #expect(current.contains(" 6"))
    #expect(first.contains(" 5"))
    #expect(second.contains(" 4"))
    // And what fell off the end is gone rather than lying about somewhere.
    #expect(!current.contains(" 3") && !first.contains(" 3") && !second.contains(" 3"))
}

@Test("Timestamped archives are named for the moment, and pruned to the limit")
func timestampedArchivesArePruned() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // A file the sink did not write, to prove the prune sweeps only its own.
    let stranger = directory.appending(path: "other.log")
    try Data("not ours".utf8).write(to: stranger)

    let sink = FileSink(
        directory: directory,
        name: "test.log",
        rotation: LogRotation(maxFileSize: 200, maxArchives: 2, naming: .timestamped),
        minimum: .debug
    )
    for number in 1...5 {
        sink.write(
            LogEntry(
                level: .info,
                category: .cloud,
                message: String(repeating: "z", count: 200) + " \(number)",
                date: Date()
            )
        )
    }
    await sink.flush()

    let written = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    let archives = written.filter { $0.hasPrefix("test_") }
    #expect(archives.count == 2, "kept \(written)")
    // The current file keeps its plain name; the archives carry the moment
    // and sort into the order they happened.
    #expect(written.contains("test.log"))
    #expect(archives == archives.sorted())
    #expect(archives.allSatisfy { $0.hasSuffix(".log") })
    // Somebody else's file in the same directory is untouched.
    #expect(written.contains("other.log"))
}

@Test("Keeping nothing keeps nothing: the file that grew is the file that goes")
func noArchivesMeansNoArchives() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sink = FileSink(
        directory: directory,
        name: "test.log",
        rotation: LogRotation(maxFileSize: 200, maxArchives: 0),
        minimum: .debug
    )

    for number in 1...4 {
        sink.write(
            LogEntry(
                level: .info,
                category: .sync,
                message: String(repeating: "w", count: 200) + " \(number)",
                date: Date()
            )
        )
    }
    await sink.flush()

    let written = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(written == ["test.log"])
    let text = try String(contentsOf: directory.appending(path: "test.log"), encoding: .utf8)
    #expect(text.contains(" 4"))
    #expect(!text.contains(" 1"))
}

// The sink never makes its caller wait, so something has to give when lines
// arrive faster than the disk takes them. It is lines rather than memory —
// and the count of what was lost is itself a line, because a file that
// quietly holds less than it was given answers the wrong question later.

@Test("A full queue drops the oldest waiting lines and counts them")
func afullQueueCountsWhatItLost() {
    // Nothing consumes this stream, so the queue fills and stays full: what
    // is being checked is the arithmetic of the loss, not the disk.
    let queue = LogQueue(bufferedLines: 2)
    #expect(queue.pendingDrops == nil)

    for number in 1...5 {
        queue.send(.entry(LogEntry(level: .info, category: .sync, message: "line \(number)", date: Date())))
    }

    // Two fitted, three did not.
    #expect(queue.pendingDrops == 3)
    // Reporting subtracts only what was reported: more may be lost between
    // reading the count and writing the line that names it.
    queue.forgetDrops(2)
    #expect(queue.pendingDrops == 1)
    queue.forgetDrops(99)
    #expect(queue.pendingDrops == nil)
}

@Test("What was lost is said in the file, in lines and not in silence")
func theLossHasWords() {
    #expect(FileSink.dropMarker(17).message.contains("17"))
    #expect(FileSink.dropMarker(17).message.contains("dropped"))
    #expect(FileSink.failureMarker(4).message.contains("4 log lines not written"))
    // The sink's own voice, not a host's channel borrowed for it.
    #expect(FileSink.dropMarker(1).category == .redactlog)
    #expect(FileSink.failureMarker(1).category == .redactlog)
}

// A flush is a wait on a barrier that travels with the lines. The one way the
// barrier can fail to arrive is to be pushed out of a full queue — and then it
// has to be answered anyway, or the process flushing at exit never exits.
@Test("A barrier pushed out of a full queue is answered, and is not a lost line")
func aDroppedBarrierStillAnswers() {
    let queue = LogQueue(bufferedLines: 1)
    let answered = Mutex(false)

    queue.send(.barrier { answered.withLock { $0 = true } })
    #expect(!answered.withLock { $0 }, "answered before anything pushed it out")
    // The line takes the only slot; the barrier is what falls out.
    queue.send(.entry(LogEntry(level: .info, category: .sync, message: "storm", date: Date())))

    #expect(answered.withLock { $0 }, "a dropped barrier was never answered — a flush here would hang")
    #expect(queue.pendingDrops == nil, "a barrier is not a line the file was supposed to hold")
}

@Test("A flush under a storm comes back")
func flushSurvivesAStorm() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sink = FileSink(directory: directory, name: "test.log", bufferedLines: 8, minimum: .debug)

    // More than the queue holds, on both sides of a flush, so that whatever
    // the consumer's pace, a barrier is somewhere in a queue being overrun.
    for number in 1...500 {
        sink.write(LogEntry(level: .info, category: .sync, message: "line \(number)", date: Date()))
    }
    async let flushed: Void = sink.flush()
    for number in 501...1000 {
        sink.write(LogEntry(level: .info, category: .sync, message: "line \(number)", date: Date()))
    }
    await flushed
    await sink.flush()

    let text = try String(contentsOf: directory.appending(path: "test.log"), encoding: .utf8)
    #expect(text.contains("line 1000"))
}

@Test("Lines the disk refused are counted, and said once the disk takes lines again")
func writeFailuresAreReported() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sink = FileSink(directory: directory, name: "test.log", minimum: .debug)

    // Make opening the log fail so the line has nowhere to go.
    try allowWrites(false, in: directory, name: "test.log")
    sink.write(LogEntry(level: .info, category: .sync, message: "lost", date: Date()))
    await sink.flush()
    #if !os(Windows)
    // The Windows failure fixture itself occupies this path.
    #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "test.log").path))
    #endif

    try allowWrites(true, in: directory, name: "test.log")
    sink.write(LogEntry(level: .info, category: .sync, message: "kept", date: Date()))
    await sink.flush()

    let lines = contents(of: directory.appending(path: "test.log"))
    #expect(lines.count == 2, "got \(lines)")
    #expect(lines.first?.contains("1 log lines not written") == true)
    #expect(lines.last?.hasSuffix("kept") == true)
    #expect(!lines.joined().contains("lost"))
}

// A marker is the sink's own line, and it goes through the format like every
// other: a sentence dropped into a file of JSON objects is the one line the
// collector cannot parse, at the moment the file is read to find out why.
@Test("A loss marker takes the file's format, so a JSON file stays JSON line for line")
func markersTakeTheFormat() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sink = FileSink(directory: directory, name: "test.jsonl", format: JSONLinesFormat(), minimum: .debug)

    try allowWrites(false, in: directory, name: "test.jsonl")
    sink.write(LogEntry(level: .info, category: .sync, message: "lost", date: Date()))
    await sink.flush()
    try allowWrites(true, in: directory, name: "test.jsonl")
    sink.write(LogEntry(level: .info, category: .sync, message: "kept", date: Date()))
    await sink.flush()

    let lines = contents(of: directory.appending(path: "test.jsonl"))
    #expect(lines.count == 2, "got \(lines)")
    // Every line, the marker included, is one JSON object.
    let objects = try lines.map { line in
        try #require(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], "not an object: \(line)")
    }
    #expect(objects.first?["category"] as? String == "redactlog")
    #expect(objects.first?["level"] as? String == "error")
    #expect((objects.first?["message"] as? String)?.contains("1 log lines not written") == true)
    #expect(objects.last?["message"] as? String == "kept")
    // The queue's marker takes the same route.
    let dropped = JSONLinesFormat().format(FileSink.dropMarker(3))
    #expect(try JSONSerialization.jsonObject(with: Data(dropped.utf8)) is [String: Any])
}

@Test("A prune sweeps only the archives this sink named, not a neighbour with the same prefix")
func pruneMatchesTheWholeName() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // Another sink's file, one underscore away from looking like an archive.
    let neighbour = directory.appending(path: "test_notes.log")
    try Data("not ours".utf8).write(to: neighbour)

    let sink = FileSink(
        directory: directory,
        name: "test.log",
        rotation: LogRotation(maxFileSize: 100, maxArchives: 1, naming: .timestamped),
        minimum: .debug
    )
    for number in 1...4 {
        sink.write(LogEntry(level: .info, category: .cloud, message: String(repeating: "q", count: 100) + " \(number)", date: Date()))
    }
    await sink.flush()

    let written = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    #expect(written.contains("test_notes.log"), "the neighbour was pruned: \(written)")
    #expect(written.filter { $0.hasPrefix("test_2") }.count == 1, "kept \(written)")
}

@Test("A queue nobody starved keeps everything, and says nothing about losses")
func anUnstarvedQueueIsSilent() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sink = FileSink(directory: directory, name: "test.log", minimum: .debug)

    for number in 1...200 {
        sink.write(
            LogEntry(level: .info, category: .sync, message: "line \(number)", date: Date())
        )
    }
    await sink.flush()

    let text = try String(contentsOf: directory.appending(path: "test.log"), encoding: .utf8)
    #expect(text.split(separator: "\n").count == 200)
    #expect(!text.contains("dropped"), "lines were lost at a volume that fits easily")
}

@Test("A sink takes only what its own threshold allows")
func theThresholdIsTheSinksOwn() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let sink = FileSink(directory: directory, name: "test.log", minimum: .error)

    #expect(!sink.accepts(.info, in: .sync))
    #expect(sink.accepts(.error, in: .sync))

    sink.write(LogEntry(level: .error, category: .sync, message: "kept", date: Date()))
    await sink.flush()

    let lines = contents(of: directory.appending(path: "test.log"))
    #expect(lines.count == 1)
    #expect(lines[0].hasSuffix("kept"))
}
