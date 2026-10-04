// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
import Synchronization

/// Process logs. What may be printed and what must be masked is decided per
/// value, in `LogMessage`, and settled before a line reaches any sink.
///
/// Where the code writes to is not here. The named channels — `Log.sync` and
/// the rest — are the parts a particular product is divided into, and they live
/// with it; what is here is the installation every one of them resolves
/// through. Resolved per call rather than stored, because `bootstrap` runs after
/// this type is first touched in at least one host, and a stored logger would
/// have been built from the default and kept it.
public enum Log {
    // MARK: - Where lines go

    /// Name the sinks and the masker for this process. Once, at its start.
    ///
    /// Hosts want different things and none of them is wrong: a long-running
    /// application can write a file, a sandboxed extension has nowhere to put
    /// one and the system log instead, a command-line tool has a terminal in
    /// front of a person. That is a decision of the composition root, and the
    /// composition root is exactly where this is
    /// called from — and nowhere else, which is what the once-only rule is
    /// for. A second caller is ignored rather than obeyed: two bootstraps mean
    /// two opinions, and the later one would silently win in whatever order
    /// the processes happened to start their work.
    ///
    /// Not called at all is a supported state, and then nothing is written.
    /// Silence rather than a guess: a default sink would have had to name a
    /// subsystem for the system log, and that is the host's identity, not
    /// something this package can invent. What is not optional is the masking —
    /// an installation without sinks still has its masker, so a host that
    /// installs one later cannot end up with a sink and no masker.
    public static func bootstrap(
        sinks: [any LogSink],
        masker: any SecretMasking = DigestMasker()
    ) {
        let alreadyDone = installation.withLock { current -> Bool in
            guard !current.bootstrapped else { return true }
            current = Installation(sinks: sinks, masker: masker, bootstrapped: true)
            return false
        }
        // Said out loud rather than swallowed. Ignoring the second caller is
        // right — the first one is the composition root and the second is a
        // mistake — but a mistake that leaves no trace is one somebody spends
        // an afternoon on, wondering why their sink never receives anything.
        if alreadyDone {
            logger(.redactlog).notice("a second logging bootstrap was ignored; the first one stands")
        }
    }

    /// The logger for a category, built from whatever this process installed.
    ///
    /// Built per call, not cached: caching the four loggers in the
    /// installation looks like an obvious win — a dictionary lookup instead
    /// of a construction — but costs more on this path, 374 ns against 343
    /// for a line nobody takes, because hashing an enum key costs more than
    /// copying a struct of three fields.
    public static func logger(_ category: LogCategory) -> LogChannel {
        let current = installation.withLock { $0 }
        return LogChannel(category: category, sinks: current.sinks, masker: current.masker)
    }

    /// Wait for every sink to finish what it has in flight.
    ///
    /// For a process that is about to end. A long-running one never needs
    /// this — its sinks catch up while it works — but a command-line tool exits
    /// a second after it starts, and a file written in the background is a file
    /// with nothing in it by then.
    public static func flush() async {
        for sink in installation.withLock({ $0.sinks }) { await sink.flush() }
    }

    /// The same, unconditionally, for a test that needs its own sink.
    ///
    /// Internal: a test reaches it through `@testable`, and nothing shipped
    /// can. `bootstrap` refuses a second opinion, which is right for a process
    /// and useless for a suite where every case wants a fresh recorder.
    static func install(sinks: [any LogSink], masker: any SecretMasking = DigestMasker()) {
        installation.withLock { $0 = Installation(sinks: sinks, masker: masker, bootstrapped: true) }
    }

    /// What this process logs through. A `Mutex` rather than a `let`, because
    /// it is written once at start and read from every isolation there is.
    private static let installation = Mutex(Installation.default)

    private struct Installation: Sendable {
        var sinks: [any LogSink]
        var masker: any SecretMasking
        var bootstrapped: Bool

        static var `default`: Installation {
            Installation(sinks: [], masker: DigestMasker(), bootstrapped: false)
        }
    }

    // MARK: - Masking

    /// A secret for the log: its length and a short digest, never any of its
    /// characters.
    ///
    /// The body lives in the installed masker — one masker, named and
    /// swappable, is what lets a sink be added without a way to leak through
    /// it. This stays for the callers that mask outside a message and do not
    /// hold a logger to ask, and it asks the same masker the lines go through:
    /// a host that installed its own would otherwise be running two policies,
    /// and the one it did not choose would be the one on this path.
    public static func masked(_ secret: String) -> String {
        installation.withLock { $0.masker }.masked(secret)
    }

    /// The user's own words for the log: the length and, for a file name, the
    /// extension only. What they wrote is their private data, not our
    /// telemetry.
    public static func maskedUserText(_ name: String) -> String {
        installation.withLock { $0.masker }.maskedUserText(name)
    }
}
