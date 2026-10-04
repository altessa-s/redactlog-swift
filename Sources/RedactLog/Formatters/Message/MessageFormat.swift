// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// The message and its fields, and nothing else.
///
/// For a sink whose destination keeps the rest: the unified log has the time,
/// the level and the category as columns, and a terminal in front of a person
/// running one command wants the sentence rather than a ledger.
public struct MessageFormat: LogFormatting {
    public init() {}

    public func format(_ entry: LogEntry) -> String { entry.text }
}
