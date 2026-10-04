// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// A line for a person reading a file days later: when, how loud, from where,
/// and what.
///
/// The stamp carries the date as well as the time, because a rotated file
/// spans days and "08:05:44" is no answer to when.
public struct PlainTextFormat: LogFormatting {
    public init() {}

    public func format(_ entry: LogEntry) -> String {
        let stamp = entry.date.formatted(.iso8601.timeSeparator(.colon))
        return "\(stamp) [\(entry.level)] \(entry.category.rawValue): \(entry.text)"
    }
}
