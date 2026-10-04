// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// A line on its way to the log, with every interpolated value carrying what
/// may be done with it.
///
/// Written like an ordinary string — `"root \(hash, .public) refused"` — and
/// rendered exactly once, by the facade, with the facade's masker. What comes
/// out the other side is text, and text is the only thing a sink ever sees.
///
/// **Untagged means redacted.** Until now the unified log did this for us: an
/// interpolated value it was not told about came out `<private>`, which is why
/// nothing has ever leaked through a forgotten annotation. Pre-rendering the
/// line takes that away — the system log cannot redact what it is handed as a
/// finished string — so the same default lives here instead. A value nobody
/// classified is a value nobody thought about, and the safe reading of an
/// unthought-about value is that it belongs to the user.
public struct LogMessage: ExpressibleByStringInterpolation, Sendable {
    /// What may be done with an interpolated value.
    ///
    /// Frozen: this framework ships in lockstep with what links it, so there
    /// is no ABI to protect — and an exhaustive `switch` over these cases in a
    /// masker is the point. A new case must break its build, not fall into an
    /// `@unknown default`.
    @frozen
    public enum Tag: Sendable {
        /// Ours, or the protocol's: a path, a status, a count. Printed.
        case `public`
        /// A token or anything else that grants access. Through `masked`.
        case secret
        /// The user's own words — something they typed or named. Through
        /// `maskedUserText`.
        case userText
        /// Nobody said. Printed as a placeholder, and this is the default.
        case redacted
    }

    struct Segment: Sendable {
        let text: String
        let tag: Tag
    }

    var segments: [Segment]

    public init(stringLiteral value: String) {
        segments = [Segment(text: value, tag: .public)]
    }

    public init(stringInterpolation: StringInterpolation) {
        segments = stringInterpolation.segments
    }

    public struct StringInterpolation: StringInterpolationProtocol, Sendable {
        var segments: [Segment] = []

        public init(literalCapacity: Int, interpolationCount: Int) {
            segments.reserveCapacity(interpolationCount * 2 + 1)
        }

        /// The text of the message itself — ours, written in the source, and
        /// never anybody's data.
        public mutating func appendLiteral(_ literal: String) {
            segments.append(Segment(text: literal, tag: .public))
        }

        /// A value nobody classified. See the note above the type: this is
        /// where the old `<private>` default went.
        public mutating func appendInterpolation(_ value: some CustomStringConvertible) {
            segments.append(Segment(text: value.description, tag: .redacted))
        }

        /// A value with a say in what happens to it.
        public mutating func appendInterpolation(
            _ value: some CustomStringConvertible,
            _ tag: Tag
        ) {
            segments.append(Segment(text: value.description, tag: tag))
        }
    }

    /// The finished line. The one place a secret meets its masker, and the one
    /// moment at which it does.
    public func rendered(with masker: any SecretMasking) -> String {
        segments.map { Self.render(text: $0.text, tag: $0.tag, with: masker) }.joined()
    }

    /// What a tag means, in one place. A value under a metadata key is exactly
    /// as dangerous as the same value in prose, so both come through here.
    static func render(text: String, tag: Tag, with masker: any SecretMasking) -> String {
        switch tag {
        case .public: text
        case .secret: masker.masked(text)
        case .userText: masker.maskedUserText(text)
        case .redacted: "<redacted>"
        }
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
extension LogMessage.Tag {
    public static func == (lhs: LogMessage.Tag, rhs: LogMessage.Tag) -> Bool {
        switch (lhs, rhs) {
        case (.public, .public), (.secret, .secret), (.userText, .userText), (.redacted, .redacted):
            true
        default:
            false
        }
    }
}
