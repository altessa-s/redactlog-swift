// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

extension LogChannel {
    /// `try?` with a line in the log.
    ///
    /// The failure is still swallowed — the caller has a default and goes on
    /// — but it is named: a hundred bare `try?` in one host were a hundred
    /// places where a read that failed looked like there being nothing to
    /// read, and a write that failed looked like a choice the user never made.
    /// `nil` is the answer either way; what changes is that the log can say
    /// which of the two happened.
    public func noting<T>(_ what: String, _ body: () throws -> T) -> T? {
        do {
            return try body()
        } catch {
            self.error("\(what, .public): \(Self.summary(of: error), .public)")
            return nil
        }
    }

    /// Runs on the caller's actor: the closure usually reads the caller's
    /// own state, and a helper that hopped executors would be a data race
    /// the compiler names.
    public func noting<T>(
        _ what: String,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async -> T? {
        do {
            return try await body()
        } catch {
            self.error("\(what, .public): \(Self.summary(of: error), .public)")
            return nil
        }
    }

    /// The same for a body that answers with an optional of its own: one
    /// level of `nil`, not two, so a missing value and a failed read meet the
    /// caller's `??` the same way.
    public func noting<T>(_ what: String, _ body: () throws -> T?) -> T? {
        do {
            return try body()
        } catch {
            self.error("\(what, .public): \(Self.summary(of: error), .public)")
            return nil
        }
    }

    public func noting<T>(
        _ what: String,
        isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T?
    ) async -> T? {
        do {
            return try await body()
        } catch {
            self.error("\(what, .public): \(Self.summary(of: error), .public)")
            return nil
        }
    }

    /// What may be said about an error in a line tagged `.public`.
    ///
    /// Not its description. An error from the platform — a file that is not
    /// there, a URL that would not load — carries the path or the URL in its
    /// user info and prints it, and a path is the name of somebody's
    /// document. So an `NSError` is reduced to its domain and its code, which
    /// name the failure and nothing else. A Swift error is printed as it is:
    /// its description is the host's own declaration, written in the source
    /// the way a literal is, and what it chose to carry in an associated
    /// value is the host's to tag.
    static func summary(of error: any Error) -> String {
        if type(of: error) is NSError.Type {
            let failure = error as NSError
            return "\(failure.domain) \(failure.code)"
        }
        return String(describing: error)
    }
}
