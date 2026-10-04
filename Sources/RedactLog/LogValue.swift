// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// One field of a line's metadata, carrying what may be done with it.
///
/// Metadata is the part of a line worth filtering on later — which document,
/// which generation, how many — and it is exactly as dangerous as a message:
/// a document's name is a document's name whether it sits in prose or under a
/// key. So it goes through the same tags, and through the same masker, at the
/// same moment.
///
/// The default is the same one too. `LogValue(id)` without a word about what
/// `id` is renders as `<redacted>`, because a value nobody classified is a
/// value nobody thought about.
public struct LogValue: Sendable, ExpressibleByStringLiteral {
    let text: String
    let tag: LogMessage.Tag

    public init(_ value: some CustomStringConvertible, _ tag: LogMessage.Tag = .redacted) {
        text = value.description
        self.tag = tag
    }

    /// A literal is ours, written in the source — the one kind of text that
    /// belongs to nobody's account.
    public init(stringLiteral value: String) {
        text = value
        tag = .public
    }

    /// Ours, or the protocol's: a path, a status, a count.
    public static func `public`(_ value: some CustomStringConvertible) -> LogValue {
        LogValue(value, .public)
    }

    /// A token or anything else that grants access.
    public static func secret(_ value: some CustomStringConvertible) -> LogValue {
        LogValue(value, .secret)
    }

    /// The user's own words — something they typed or named.
    public static func userText(_ value: some CustomStringConvertible) -> LogValue {
        LogValue(value, .userText)
    }

    func rendered(with masker: any SecretMasking) -> String {
        LogMessage.render(text: text, tag: tag, with: masker)
    }
}
