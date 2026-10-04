// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// What a line looks like by the time it is written down.
///
/// Where a line goes and what it looks like are two decisions, and they were
/// one: the file sink stamped its own lines, the console printed the bare
/// message, and changing either meant editing the sink. They are separate
/// because they vary separately — the same file is wanted as prose by a person
/// and as JSON by whatever collects it, and the unified log already carries
/// the time, the level and the category in columns of its own, so repeating
/// them inside the message would be noise there and information anywhere else.
///
/// A format never decides *what* may be printed. The entry it is handed is
/// already rendered and already masked; a format that could reach a value
/// would be a second place to forget masking, and there is deliberately no
/// such place.
public protocol LogFormatting: Sendable {
    func format(_ entry: LogEntry) -> String
}
