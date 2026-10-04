// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import Synchronization

/// Lines to a file, for the run nobody was watching.
///
/// The system log is the right place for a line and the wrong place for a
/// week of them: it rolls, it is filtered by a policy that is not ours, and a
/// person sending in a report cannot attach it. A file can be read after the
/// fact and handed over whole.
///
/// **Never a place the caller waits.** Logging is called from the middle of
/// whatever the host is doing — a transfer, a render, a request something else
/// is blocked on — and a disk write in that path would turn the cheapest
/// statement in the code into the slowest. Entries are handed to a stream and
/// formatted and written by one task behind it: the caller returns at once,
/// and the order the lines were written in is the order they land in — a
/// stream keeps what a scattering of tasks would not.
///
/// **Not for every host.** Every extra writer inside a sandboxed process is
/// another lock to hold while whoever called it waits, and such a process has
/// the system log already. A long-running application and a command-line tool
/// install this one; a process answering someone else's requests should not.
public struct FileSink: LogSink {
    private let minimum: LogLevel
    private let queue: LogQueue

    /// - Parameters:
    ///   - directory: where the file goes. The group container in the app, a
    ///     temporary directory in a test.
    ///   - name: the current file's name. The older ones are named after it,
    ///     the way `rotation` says.
    ///   - rotation: how large the file may grow, how many older ones are
    ///     kept, and what they are called.
    ///   - format: what a line looks like. Prose by default, because a file is
    ///     read by a person before it is read by anything else; hand it
    ///     `JSONLinesFormat()` and the same file is parsed rather than read.
    ///   - bufferedLines: how many lines may wait for the disk. Past it the
    ///     oldest waiting line is dropped and counted — see `LogQueue`.
    ///   - minimum: this sink's own threshold, as every sink's is. Higher than
    ///     the console's by default: a file is read days later, and a debug
    ///     line about one blob among ten thousand is not what it is read for.
    public init(
        directory: URL,
        name: String,
        rotation: LogRotation = LogRotation(),
        format: any LogFormatting = PlainTextFormat(),
        bufferedLines: Int = 4096,
        minimum: LogLevel = .info
    ) {
        self.minimum = minimum
        queue = LogQueue(bufferedLines: bufferedLines)
        let writer = RotatingFile(
            current: directory.appending(path: name),
            rotation: rotation,
            format: format
        )
        // One consumer, so the file is written by one thing in one order —
        // and formatted there too, off the caller's thread.
        let items = queue.items
        Task.detached(priority: .utility) {
            for await item in items {
                switch item {
                case .entry(let entry): await writer.append(entry)
                case .barrier(let done): done()
                }
            }
        }
    }

    /// Wait until everything handed over so far is on disk.
    ///
    /// The waiting is done **in the stream**, not on the writer. Asking the
    /// actor directly looks equivalent and is not: the lines reach it from the
    /// consumer task, so a `settle()` enqueued from here can be answered
    /// before the consumer has delivered a single one of them — the file can
    /// come back empty, and only by luck in a live run, which is the worst way
    /// for a race to introduce itself.
    ///
    /// A barrier travels with the lines instead: the consumer takes items in
    /// order, so by the time it reaches this one everything ahead of it has
    /// been written. The stream is not finished — a process that flushes
    /// mid-run must not go silent afterwards. And a barrier the queue had to
    /// drop to make room is answered by the queue itself, so this never waits
    /// on a line that is no longer coming.
    public func flush() async {
        await withCheckedContinuation { continuation in
            queue.send(.barrier { continuation.resume() })
        }
    }

    public func accepts(_ level: LogLevel, in category: LogCategory) -> Bool {
        level >= minimum
    }

    public func write(_ entry: LogEntry) {
        // What was lost while the disk was behind, said before the line that
        // finally got through. Reported here rather than by the writer,
        // because here is where it is known — and reported at all, because a
        // log that quietly holds less than it was given is a log that answers
        // the wrong question later.
        if let lost = queue.pendingDrops, queue.send(.entry(Self.dropMarker(lost))) {
            queue.forgetDrops(lost)
        }
        queue.send(.entry(entry))
    }

    /// What the sink has to say about its own losses, as an entry and not as
    /// text.
    ///
    /// An entry because the file has one shape, and the format decides it: a
    /// sentence written straight into a file of JSON objects is a line the
    /// collector chokes on, at exactly the moment — a storm, a full disk —
    /// the file is being read to find out what happened. So a marker goes
    /// through `format.format(_:)` like every other line, under this
    /// package's own category, because the loss is the sink's fact and not
    /// the host's.
    ///
    /// A notice: the process is behind, which a reader should know and
    /// nothing has failed.
    static func dropMarker(_ count: Int) -> LogEntry {
        LogEntry(
            level: .notice,
            category: .redactlog,
            message: "… \(count) log lines dropped: the file could not keep up",
            date: Date()
        )
    }

    /// An error: the disk refused lines, and that is a fault the file exists
    /// to report.
    static func failureMarker(_ count: Int) -> LogEntry {
        LogEntry(
            level: .error,
            category: .redactlog,
            message: "… \(count) log lines not written: the file could not be opened or written",
            date: Date()
        )
    }
}

/// The file itself, and the one thing that may touch it.
///
/// An actor because a file handle and a byte count are state, and the lines
/// arrive from a stream that is fed by every isolation in the product. What it
/// does with them is deliberately dull: append, and when the file is large
/// enough, put it aside under the name the policy asks for.
private actor RotatingFile {
    private let current: URL
    private let rotation: LogRotation
    private let format: any LogFormatting
    private var handle: FileHandle?
    private var written: Int = 0
    /// Lines the disk refused and the file does not hold. Said in the file
    /// the moment it takes a line again, the way the queue's losses are: the
    /// two are the same fact to a reader — the file has less than it was
    /// given — and a full disk is the more likely cause of the two.
    private var unwritten: Int = 0

    init(current: URL, rotation: LogRotation, format: any LogFormatting) {
        self.current = current
        self.rotation = rotation
        self.format = format
    }

    /// Formatted here, on the writer's time, and the marker for what the disk
    /// refused is formatted the same way: one shape of line in the file,
    /// whatever the format is.
    func append(_ entry: LogEntry) {
        if unwritten > 0, put(format.format(FileSink.failureMarker(unwritten))) {
            unwritten = 0
        }
        if !put(format.format(entry)) {
            unwritten += 1
        }
    }

    /// One line onto the disk. `false` when it did not get there.
    ///
    /// `try?` throughout, and deliberately: a log that throws its way up into
    /// the work — or worse, into a request something else is blocked on —
    /// would be a fault caused by the reporting of faults. What it does
    /// instead is answer, so the loss can be counted.
    private func put(_ line: String) -> Bool {
        let data = Data((line + "\n").utf8)
        // Opening an existing log establishes its size before rotation is decided.
        guard open() != nil else { return false }
        if written + data.count > rotation.maxFileSize, written > 0 { rotate() }
        guard let handle = open() else { return false }
        guard (try? handle.write(contentsOf: data)) != nil else { return false }
        written += data.count
        return true
    }

    private func open() -> FileHandle? {
        if let handle { return handle }
        let manager = FileManager.default
        try? manager.createDirectory(
            at: current.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !manager.fileExists(atPath: current.path) {
            manager.createFile(atPath: current.path, contents: nil)
        }
        guard let opened = try? FileHandle(forWritingTo: current) else { return nil }
        // Once, here, and not on every line: a handle opened for writing
        // starts at the beginning of the file, and this actor only ever
        // appends. The offset it hands back is of no use — discarded
        // explicitly, because `try?` on a value makes an optional nobody
        // reads and the compiler is right to say so.
        _ = try? opened.seekToEnd()
        handle = opened
        written = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return opened
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        written = 0
        guard rotation.maxArchives > 0 else {
            // Nothing is kept: the file that grew is the file that goes.
            try? FileManager.default.removeItem(at: current)
            return
        }
        switch rotation.naming {
        case .numbered: rotateByNumber()
        case .timestamped: rotateByTime()
        }
    }

    /// `.1` is the most recent, and every archive shifts up by one. The oldest
    /// is removed before the shift rather than after: moving onto a name that
    /// still exists fails, and a failed rotation would leave the current file
    /// in place to grow past its limit for ever.
    private func rotateByNumber() {
        let manager = FileManager.default
        let numbered = { (index: Int) in
            self.current.deletingLastPathComponent()
                .appending(path: "\(self.current.lastPathComponent).\(index)")
        }
        try? manager.removeItem(at: numbered(rotation.maxArchives))
        for index in stride(from: rotation.maxArchives - 1, through: 1, by: -1) {
            try? manager.moveItem(at: numbered(index), to: numbered(index + 1))
        }
        try? manager.moveItem(at: current, to: numbered(1))
    }

    /// The moment it was put aside, in the name. Renames nothing, so the cost
    /// does not grow with the number kept — and the archives sort by name into
    /// the order they happened, which is what somebody reading them wants.
    private func rotateByTime() {
        let manager = FileManager.default
        try? manager.moveItem(at: current, to: stampedName())
        // What is now past the limit, oldest first. The names sort
        // chronologically by construction, so this needs no dates off disk.
        let archives = existingArchives().sorted { $0.lastPathComponent < $1.lastPathComponent }
        for stale in archives.dropLast(rotation.maxArchives) {
            try? manager.removeItem(at: stale)
        }
    }

    private func stampedName() -> URL {
        let stamp = Date().formatted(.iso8601)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
        // Four characters of a UUID, so two rotations inside one second cannot
        // land on the same name.
        let unique = UUID().uuidString.prefix(4).lowercased()
        let name = base.isEmpty ? "log" : base
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        return current.deletingLastPathComponent()
            .appending(path: "\(name)_\(stamp)_\(unique)\(suffix)")
    }

    /// The files this sink has put aside, and nothing else in the directory:
    /// a log directory may hold another sink's files, and a prune that swept
    /// them would be a bug nobody sees until the other log is missing. So the
    /// whole shape of the name is checked, not its prefix — `app_notes.log`
    /// beside `app.log` is somebody else's, and `app_20260827T150501Z_1f3c.log`
    /// is ours.
    private func existingArchives() -> [URL] {
        let directory = current.deletingLastPathComponent()
        let found = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        let name = base.isEmpty ? "log" : base
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        return found.filter { url in
            var middle = Substring(url.lastPathComponent)
            guard url.lastPathComponent != current.lastPathComponent,
                  middle.hasPrefix("\(name)_"), middle.hasSuffix(suffix)
            else { return false }
            middle = middle.dropFirst(name.count + 1).dropLast(suffix.count)
            return middle.wholeMatch(of: /\d{8}T\d{6}Z_[0-9a-f]{4}/) != nil
        }
    }

    private var base: String {
        (current.lastPathComponent as NSString).deletingPathExtension
    }

    private var fileExtension: String {
        (current.lastPathComponent as NSString).pathExtension
    }
}
