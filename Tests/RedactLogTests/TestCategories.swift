// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

@testable import RedactLog

/// The categories these suites log under.
///
/// A category is a label this package does not own — a host names the parts it
/// is divided into — so the tests name their own. The names are the ones the
/// suites were written with, back when they lived in an application and the
/// categories were an enum there: what each line is about still reads, and the
/// one raw value a test asserts on is asserted here rather than taken on trust
/// from somebody else's vocabulary.
extension LogCategory {
    static let cloud = LogCategory(rawValue: "cloud")
    static let sync = LogCategory(rawValue: "sync")
    static let render = LogCategory(rawValue: "render")
    static let fileProvider = LogCategory(rawValue: "fileprovider")
}
