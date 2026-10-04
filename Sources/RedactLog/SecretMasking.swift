// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import CryptoKit
import Foundation

/// What turns a secret into something a log may hold.
///
/// A protocol rather than two free functions, because the whole design of this
/// logging rests on one property: masking happens **once, before the message
/// reaches any sink**. A sink is handed rendered text and never a value, so a
/// new sink cannot leak a token by forgetting to mask — there is no token
/// within its reach to forget about. That property is only worth stating if
/// the masker is a thing that can be named, passed and swapped.
public protocol SecretMasking: Sendable {
    /// A secret for the log: enough to tell two of them apart, nowhere near
    /// enough to walk back to either.
    func masked(_ secret: String) -> String
    /// The user's own words: their length and, if they name a file, its
    /// extension — never the words themselves.
    func maskedUserText(_ name: String) -> String
}

/// The masker this product ships, and the one every process gets unless it
/// says otherwise.
///
/// Why a digest rather than the first few characters: every JWT the service
/// issues begins `eyJ`, so the leading characters of two different tokens
/// look the same — exactly what masking is supposed to tell apart.
///
/// Why a keyed one: four bytes of a plain hash are enough to tell two tokens
/// apart, and also enough to confirm a guess. A token has more entropy than
/// anybody can enumerate; a password or a PIN does not, and a table of the
/// digests of every four-digit PIN is a small table. The key is drawn once
/// per process and never written anywhere, so the same secret masks the same
/// way for the length of a run — which is what a reader following one token
/// through a log needs — and differently in the next, which is what a reader
/// holding a guess must not have.
public struct DigestMasker: SecretMasking {
    public init() {}

    public func masked(_ secret: String) -> String {
        guard !secret.isEmpty else { return "<empty>" }
        return "<len:\(secret.count)>#\(Self.digest(of: secret))"
    }

    /// The extension is kept only when it looks like one. `pathExtension`
    /// answers with whatever follows the last dot, and for `plan.MergerWithAcme`
    /// that is the user's own words, which is the one thing this must not
    /// print. A real extension is short and plain: letters and digits, and
    /// not many of them.
    public func maskedUserText(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        let plain = !ext.isEmpty && ext.count <= Self.longestExtension
            && ext.utf8.allSatisfy { $0.isASCIILetterOrDigit }
        return plain ? "<name:\(name.count)>.\(ext)" : "<name:\(name.count)>"
    }

    /// Long enough for `jsonld` and `sqlite`, not for a sentence.
    private static let longestExtension = 8

    /// Four bytes of an HMAC over the secret: enough to tell two tokens apart
    /// in a log and nowhere near enough to walk back to either.
    private static func digest(of value: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: key)
            .prefix(4)
            .hexString
    }

    /// Drawn once per process. Static rather than stored, so that every
    /// `DigestMasker()` in the process — the installed one and the one behind
    /// `Log.masked` — agrees about what a secret looks like.
    private static let key = SymmetricKey(size: .bits256)
}

private extension UInt8 {
    var isASCIILetterOrDigit: Bool {
        (0x30...0x39).contains(self) || (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self)
    }
}
