// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// Which part of a process is speaking — a label, and nothing this package
/// looks inside of.
///
/// A sink is handed the category with every entry, so a threshold can differ
/// per category without anybody upstream knowing that it does. What the
/// categories *are* is not a fact about logging: it is a fact about whatever is
/// being logged. So the names live with their owners — a package names its own
/// channel, an application names the parts it is divided into — and this type
/// carries them without understanding them.
///
/// Open rather than an enum, and that trade is worth stating. A closed set
/// would have made a typo a compile error; it would also have put every
/// product's vocabulary inside the logger, which is the one thing this package
/// must not know. The replacement for the compiler's help is a rule:
///
/// **Never spell `init(rawValue:)` at the point of use.** Declare each category
/// once, as a constant beside the code that logs under it, and log through the
/// constant. A category built inline is a category one letter away from a
/// silent second channel nobody reads.
///
/// **The raw value is a contract with the outside world, not an identifier.**
/// It becomes the category of the unified log — the one in
/// `log stream --predicate 'category == "…"'` — and the `category` column of
/// every line already written to a file. Changing one breaks every predicate
/// anybody has written down and splits a log's history in two, and no build
/// will say so. Spell it out even where it matches the constant's own name, so
/// that the string is never a by-product of a rename.
public struct LogCategory: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension LogCategory {
    /// This package's own voice — the one or two things it has to say about
    /// itself rather than on anybody's behalf, such as a second bootstrap it
    /// ignored.
    ///
    /// The only category declared here, and it has to be: a package that says
    /// something out loud must have somewhere to say it, and borrowing a host's
    /// channel for it would be exactly the knowledge this type exists not to
    /// have. Named after the package and not after anything using it, so that a
    /// host filtering its own channels never trips over this one.
    static let redactlog = LogCategory(rawValue: "redactlog")
}
