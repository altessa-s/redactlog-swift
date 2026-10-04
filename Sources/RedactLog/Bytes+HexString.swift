// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

/// The bytes as lowercase hex, two characters each.
///
/// Internal: carrying a dependency for twelve lines, or making a spelling of a
/// digest part of this package's surface, would not be worth it. Only the
/// masker uses it, and only to name a secret it will not print.
extension Sequence where Element == UInt8 {
    var hexString: String {
        // A table and two shifts per byte, not `String(format:)`: the formatter
        // is fine for a digest of thirty-two bytes and is minutes for a
        // megabyte, and the same spelling serves both.
        var out = ""
        for byte in self {
            out.append(hexDigits[Int(byte >> 4)])
            out.append(hexDigits[Int(byte & 0x0F)])
        }
        return out
    }
}

/// Built once, not on every call: this runs for every secret in every line.
private let hexDigits: [Character] = Array("0123456789abcdef")
