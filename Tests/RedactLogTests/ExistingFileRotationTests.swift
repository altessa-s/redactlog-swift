// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import RedactLog
import Testing

@Test("The first write rotates a full existing log", arguments: [0, 1], [LogRotation.Naming.numbered, .timestamped])
func rotationAfterReopening(archives: Int, naming: LogRotation.Naming) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "log-audit-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appending(path: "test.log")
    try Data(repeating: 65, count: 100).write(to: file)
    let sink = FileSink(
        directory: directory, name: "test.log",
        rotation: LogRotation(maxFileSize: 100, maxArchives: archives, naming: naming)
    )
    sink.write(LogEntry(level: .info, category: .sync, message: "new", date: Date()))
    await sink.flush()
    let archived = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.lastPathComponent != "test.log" }
    #expect(archived.count == archives)
    if let previous = archived.first {
        #expect(try Data(contentsOf: previous) == Data(repeating: 65, count: 100))
    }
    #expect(try Data(contentsOf: file).count <= 100)
    #expect(try String(contentsOf: file, encoding: .utf8).contains("new"))
}
