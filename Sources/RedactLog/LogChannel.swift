// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

/// What a caller holds: one category, the sinks listening to it, and the
/// masker every line goes through on the way out.
///
/// A value, not an actor. Logging is called from every isolation a host has —
/// actors, the main actor, detached work — and a line must never be a
/// suspension point: `await channel.debug(…)` would make the cheapest
/// statement in the code the one that reorders everything around it. The
/// sinks carry their own synchronisation instead, and the ones that write
/// anywhere slow do it without making the caller wait.
public struct LogChannel: Sendable {
    private let category: LogCategory
    private let sinks: [any LogSink]
    private let masker: any SecretMasking

    public init(category: LogCategory, sinks: [any LogSink], masker: any SecretMasking) {
        self.category = category
        self.sinks = sinks
        self.masker = masker
    }

    public func debug(
        _ message: @autoclosure () -> LogMessage,
        metadata: @autoclosure () -> [String: LogValue] = [:]
    ) { emit(.debug, message, metadata) }

    public func info(
        _ message: @autoclosure () -> LogMessage,
        metadata: @autoclosure () -> [String: LogValue] = [:]
    ) { emit(.info, message, metadata) }

    public func notice(
        _ message: @autoclosure () -> LogMessage,
        metadata: @autoclosure () -> [String: LogValue] = [:]
    ) { emit(.notice, message, metadata) }

    public func error(
        _ message: @autoclosure () -> LogMessage,
        metadata: @autoclosure () -> [String: LogValue] = [:]
    ) { emit(.error, message, metadata) }

    public func fault(
        _ message: @autoclosure () -> LogMessage,
        metadata: @autoclosure () -> [String: LogValue] = [:]
    ) { emit(.fault, message, metadata) }

    /// Ask first, build second.
    ///
    /// `os_log` has always had this: the message is an autoclosure the system
    /// never calls when nothing is listening, so a `debug` line in a hot loop
    /// costs a check. Rendering our own text takes that away unless it is put
    /// back deliberately — hence the closure, and hence asking every sink
    /// before any of them is written to.
    private func emit(
        _ level: LogLevel,
        _ message: () -> LogMessage,
        _ metadata: () -> [String: LogValue]
    ) {
        // Asked twice rather than collected once: `accepts` is a comparison,
        // and an array of the sinks that said yes is an allocation on every
        // line — including the lines that are then thrown away. At the line
        // volumes this handles the two approaches cost the same; this one
        // stays because one fewer allocation and one fewer local is simpler,
        // not because it is faster.
        guard sinks.contains(where: { $0.accepts(level, in: category) }) else { return }
        let entry = LogEntry(
            level: level,
            category: category,
            message: message().rendered(with: masker),
            metadata: metadata().mapValues { $0.rendered(with: masker) },
            date: Date()
        )
        for sink in sinks where sink.accepts(level, in: category) { sink.write(entry) }
    }
}
