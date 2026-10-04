// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// How much a line matters, and nothing else.
///
/// A mirror of `OSLogType`, deliberately: a scale of our own — the `trace` and
/// `warn` other libraries carry — would have to be mapped back to this one in
/// the sink that actually writes to the system log, and would buy nothing on
/// the way. Comparable because a sink decides what it accepts by comparing.
///
/// Frozen: this framework ships in lockstep with what links it, so there is
/// no ABI to protect — and an exhaustive `switch` over these cases in a
/// consumer is the point. A new case must break its build, not fall into an
/// `@unknown default`.
@frozen
public enum LogLevel: Int, Comparable, Sendable, CaseIterable {
    case debug
    case info
    case notice
    case error
    case fault

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

// Equality spelled out rather than synthesised.
//
// `@frozen` lets a consumer compare two values directly, through the witness
// the compiler derives — and that witness is internal, so it is absent from
// this module's symbol table when RedactLog is linked as a binary framework. The
// reference resolves in a release build, where the comparison is inlined, and
// fails to link in a debug one. Declaring `==` here puts the comparison
// behind an exported symbol, which costs nothing and keeps `@frozen`: a new
// case must still break a consumer's build rather than fall into an
// `@unknown default`.
extension LogLevel {
    public static func == (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue == rhs.rawValue
    }
}
