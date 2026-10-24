// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// A directory of its own per case, removed after it.
func temporaryDirectory() throws -> URL {
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
func contents(of file: URL) -> [String] {
    ((try? String(contentsOf: file, encoding: .utf8)) ?? "")
        .split(separator: "\n").map(String.init)
}
