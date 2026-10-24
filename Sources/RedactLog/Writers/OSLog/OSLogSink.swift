// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// os.Logger is Apple's system log; that system does not exist on Linux or Windows.
#if canImport(OSLog)
import Foundation
import OSLog
import Synchronization

/// The system log, which every process here has and none has to be given.
///
/// **Everything it writes is `.public`, and that is not an oversight.** The
/// facade has already rendered the line and already masked what needed masking,
/// so what arrives here is a finished string with nothing left in it to hide.
/// Interpolating it privately would replace the whole message with `<private>`
/// — the log would keep the secrets it no longer holds and lose the sentence it
/// was written for.
///
/// A class because the loggers are state now. They used to be a dictionary built
/// in `init` by walking every category there was; a category is a label this
/// package does not enumerate, so there is no list to walk and they are built on
/// first use instead. Still built once each — they are cheap, but not free, and
/// a sink is asked on every line.
public final class OSLogSink: LogSink {
    private let subsystem: String
    private let minimum: LogLevel
    private let format: any LogFormatting
    private let loggers = Mutex<[String: Logger]>([:])

    /// `minimum` is this sink's own business, as every sink's threshold is.
    /// The default takes everything and lets the unified log do its own
    /// filtering, which is what it is good at and what `log stream` expects.
    /// The message alone by default, because the unified log carries the
    /// time, the level and the category in columns of its own — repeating them
    /// inside the message would make `log stream` twice as wide and no more
    /// informative.
    /// `subsystem` has no default, and that is the point: it is the host's own
    /// identity — the string `log stream --predicate 'subsystem == "…"'` names —
    /// and a logging package that invents one sends a process's lines somewhere
    /// nobody is looking. Named from a composition root, like the sinks
    /// themselves.
    public init(
        subsystem: String,
        minimum: LogLevel = .debug,
        format: any LogFormatting = MessageFormat()
    ) {
        self.subsystem = subsystem
        self.minimum = minimum
        self.format = format
    }

    public func accepts(_ level: LogLevel, in category: LogCategory) -> Bool {
        level >= minimum
    }

    public func write(_ entry: LogEntry) {
        let logger = logger(for: entry.category)
        let message = format.format(entry)
        switch entry.level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        case .fault: logger.fault("\(message, privacy: .public)")
        }
    }

    /// One `Logger` per category, made once and kept.
    ///
    /// A category this sink has not seen before is a category it makes a logger
    /// for, rather than a line it drops. The old dictionary could miss — an
    /// entry whose category was not in the walked list went nowhere, silently —
    /// and with the set of categories now open, missing would have become the
    /// normal case rather than the impossible one.
    private func logger(for category: LogCategory) -> Logger {
        loggers.withLock { cache in
            if let made = cache[category.rawValue] { return made }
            let made = Logger(subsystem: subsystem, category: category.rawValue)
            cache[category.rawValue] = made
            return made
        }
    }
}
#endif
