// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
@testable import RedactLog
import Testing

// Where a line goes and what it looks like are two decisions. These are about
// the second one — and about the promise that runs under all of them: a format
// is handed an entry that is already rendered and already masked, so there is
// no format that can print what the tags said not to.

private func entry(
    level: LogLevel = .info,
    category: LogCategory = .sync,
    message: String = "root written",
    metadata: [String: String] = [:]
) -> LogEntry {
    LogEntry(
        level: level,
        category: category,
        message: message,
        metadata: metadata,
        date: Date(timeIntervalSince1970: 1_787_757_030)
    )
}

@Test("The message format is the sentence and its fields, and nothing else")
func messageFormatIsBare() {
    let format = MessageFormat()
    #expect(format.format(entry()) == "root written")
    #expect(
        format.format(entry(metadata: ["generation": "17", "to": "v4"]))
            == "root written {generation=17 to=v4}"
    )
}

@Test("The text format says when, how loud and from where")
func plainTextCarriesTheColumns() {
    let line = PlainTextFormat().format(entry(level: .error, category: .cloud))
    #expect(line.hasSuffix("[error] cloud: root written"))
    // The date as well as the time: a rotated file spans days, and an hour on
    // its own is no answer to when.
    #expect(line.hasPrefix("2026-08-"))
}

@Test("The JSON format is one object per line, and parses back")
func jsonIsOneObjectPerLine() throws {
    let line = JSONLinesFormat().format(
        entry(level: .notice, category: .fileProvider, metadata: ["pages": "12"])
    )
    #expect(!line.contains("\n"), "a line-delimited format may not contain a line break")

    let parsed = try #require(
        try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    )
    #expect(parsed["level"] as? String == "notice")
    // The category is the name the system log has always been filtered by.
    #expect(parsed["category"] as? String == "fileprovider")
    #expect(parsed["message"] as? String == "root written")
    #expect((parsed["metadata"] as? [String: String])?["pages"] == "12")
    #expect((parsed["time"] as? String)?.hasPrefix("2026-08-") == true)
}

@Test("A line with no fields carries no empty object")
func jsonLeavesOutEmptyMetadata() throws {
    let line = JSONLinesFormat().format(entry())
    let parsed = try #require(
        try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    )
    #expect(parsed["metadata"] == nil)
}

// A format cannot undo the masking, because by the time it is called there is
// nothing left to undo: the entry holds text, and the values are gone.
@Test("No format can print what the tags took out")
func formatsSeeOnlyWhatWasRendered() {
    let sink = CapturingSink()
    let logger = LogChannel(category: .cloud, sinks: [sink], masker: DigestMasker())
    let token = "eyJhbGciOiJI.eyJleHAiOjF9.signature"

    logger.error("refused \(token, .secret)", metadata: ["document": .userText("Diary.pdf")])

    let written = sink.entries[0]
    for format in [MessageFormat(), PlainTextFormat(), JSONLinesFormat()] as [any LogFormatting] {
        let line = format.format(written)
        #expect(!line.contains(token))
        #expect(!line.contains("Diary"))
    }
}

@Test("A sink writes in the format it was given")
func sinksHonourTheirFormat() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "redactlog-format-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sink = FileSink(
        directory: directory,
        name: "test.log",
        format: JSONLinesFormat(),
        minimum: .debug
    )
    sink.write(entry(metadata: ["pages": "3"]))
    await sink.flush()

    let text = try String(contentsOf: directory.appending(path: "test.log"), encoding: .utf8)
    let parsed = try #require(
        try JSONSerialization.jsonObject(
            with: Data(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        ) as? [String: Any]
    )
    #expect(parsed["message"] as? String == "root written")
}
