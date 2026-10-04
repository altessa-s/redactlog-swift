// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// One JSON object per line, for whatever reads logs by machine.
///
/// Line-delimited rather than an array, because a log has no end while it is
/// being written and a reader must not have to wait for one. Keys sorted, so
/// two runs of the same code compare.
public struct JSONLinesFormat: LogFormatting {
    public init() {}

    public func format(_ entry: LogEntry) -> String {
        let line = Line(
            time: entry.date.formatted(.iso8601),
            level: String(describing: entry.level),
            category: entry.category.rawValue,
            message: entry.message,
            metadata: entry.metadata.isEmpty ? nil : entry.metadata
        )
        guard let data = try? Self.encoder.encode(line),
              let text = String(data: data, encoding: .utf8)
        else {
            // A log that goes silent because its own encoder failed would hide
            // the failure it was written to explain.
            return entry.text
        }
        return text
    }

    /// Made once: an encoder is a handful of allocations, and this runs on
    /// every line. Configured here and never touched again, which is what
    /// makes sharing it across the isolations a sink is fed from sound.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    /// The fields, spelled once. `metadata` is left out when there is none:
    /// an empty object in every line is noise for a reader and bytes for a
    /// file that rotates by size.
    private struct Line: Encodable {
        let time: String
        let level: String
        let category: String
        let message: String
        let metadata: [String: String]?
    }
}
