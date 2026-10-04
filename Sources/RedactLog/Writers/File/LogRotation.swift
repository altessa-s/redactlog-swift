// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// When a log file is put aside, what the one put aside is called, and how
/// many of them are kept.
///
/// A log that only grows fills a container it shares with the user's own
/// documents; a log that is truncated loses the run that explains the one
/// being reported. Rotation is the answer to both, and all three numbers
/// belong to whoever installs the sink — the app keeps little, a debugging
/// session on a spike may want a lot.
public struct LogRotation: Sendable {
    /// How large the current file may grow before it is put aside.
    public var maxFileSize: Int
    /// How many older files are kept. Nought means the oldest is dropped at
    /// every rotation and only the current file exists.
    public var maxArchives: Int
    /// What the older files are called.
    public var naming: Naming

    /// The ceiling is `maxFileSize * (maxArchives + 1)` — two megabytes and
    /// three archives put eight at the outside, which is nothing beside the
    /// blob cache in the same container and enough to hold the run before the
    /// one being reported.
    public init(
        maxFileSize: Int = 2 * 1_048_576,
        maxArchives: Int = 3,
        naming: Naming = .numbered
    ) {
        self.maxFileSize = maxFileSize
        self.maxArchives = maxArchives
        self.naming = naming
    }

    /// Frozen: this framework ships in lockstep with what links it, so there
    /// is no ABI to protect — and an exhaustive `switch` over these cases in
    /// the writer is the point. A new case must break its build, not fall
    /// into an `@unknown default`.
    @frozen
    public enum Naming: Sendable {
        /// `<name>.1`, `<name>.2`, … — `.1` is always the most recent.
        /// Every rotation renames every archive, which is cheap at three files
        /// and the reason `maxArchives` is not a hundred.
        case numbered
        /// `<name>_20260827T150501Z_1f3c.log` — the moment it was put aside,
        /// and four characters of a UUID so that two rotations in the same
        /// second cannot collide. Renames nothing, and the archives sort by
        /// name into the order they happened.
        case timestamped
    }
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
extension LogRotation.Naming {
    public static func == (lhs: LogRotation.Naming, rhs: LogRotation.Naming) -> Bool {
        switch (lhs, rhs) {
        case (.numbered, .numbered), (.timestamped, .timestamped): true
        default: false
        }
    }
}
