# RedactLog

Process logs with masking built into the message: a facade a host installs once, channels the code writes to, lines whose every
interpolated value carries what may be done with it, and sinks for the unified log, a rotating file and a terminal.

A Swift package for Apple platforms, Linux and Windows, using `Foundation` and `Synchronization`.
Apple builds use `OSLog` and `CryptoKit`; Linux and Windows use `Crypto` from `apple/swift-crypto`.

## Why it exists

A logger is the last thing a layered system should have to share through its domain. Kept at the bottom of an application,
under everything, it ties every package that logs to that application; and the packages that most need their diagnostics — the
ones that hold tokens and talk to a network — are the ones whose logs must prove that a token never reached a line.

So the logging lives outside any domain, and what makes that work is that **nothing here knows what it is logging for**.

## What it depends on

`apple/swift-crypto` supplies hashing on Linux and Windows. Apple builds prefer the system `CryptoKit` module.
`OSLogSink` is available only where `OSLog` can be imported: `os.Logger` is Apple's system log,
and that system does not exist on Linux or Windows. Use `FileSink`, `ConsoleSink` and `CollapsingSink` there.

The host supplies three things that the package cannot choose for it:

- **The categories come from outside.** `LogCategory` is a label — a string in a wrapper, with no cases. What the parts of a
  process are is a fact about that process, so a host declares its own, and a package that logs declares its own channel. The
  one category here is `redactlog`, for the one or two things this package has to say about itself.
- **On Apple platforms, the subsystem comes from outside.** `OSLogSink(subsystem:)` has no default:
  that string is the host's identity — the one
  `log stream --predicate 'subsystem == "…"'` names — and a logger that invents one sends a process's lines somewhere nobody is
  looking.
- **The file name comes from outside.** `FileSink(directory:name:)` likewise.

And **not installing anything is a supported state**: then nothing is written. Silence rather than a guess, because a library
that logs somewhere nobody asked for is a library that has to be worked around.

## Design

**Untagged means redacted.** A line is written like an ordinary string — `"root \(hash, .public) refused"` — and every
interpolated value carries a tag. A value nobody classified comes out `<redacted>`, and that default is the whole safety
argument. The unified log used to do this for us: a value it was not told about printed as `<private>`, which is why nothing
ever leaked through a forgotten annotation. Rendering the line ourselves takes that away unless the same default is put back
here, and a value nobody thought about is one that belongs to the user.

**A secret meets its masker exactly once.** The facade renders the line, with the masker the host installed, and what reaches a
sink is finished text. So a sink cannot leak — there is nothing left in it to leak — and adding one does not add a way to.
`DigestMasker` is the default: a secret becomes its length and a short keyed digest — the key is drawn once per process, so the
same token reads the same way through one run and a guess cannot be confirmed against a file — and the user's own words become
their length and, for a file name, its extension.

**Ask first, build second.** Messages are autoclosures, and every sink is asked before any of them is written to. `os_log` has
always worked this way; rendering our own text would have lost it, so a `debug` line in a hot loop still costs a comparison.

**A line is never a suspension point.** `LogChannel` is a value, not an actor. Logging is called from every isolation a host
has, and `await channel.debug(…)` would make the cheapest statement in the code the one that reorders everything around it. The
sinks carry their own synchronisation instead, and the ones that write anywhere slow do it without making the caller wait —
`FileSink` hands lines to a stream and one task behind it writes them, in order.

**A category's raw value is a contract with the outside world.** It becomes the category of the unified log and the `category`
column of every line already in a file. Changing one breaks every predicate anybody has written down and splits a log's history
in two, and no build will say so. Declare each category once, as a constant, spell the string out even where it matches the
constant's own name, and never write `LogCategory(rawValue:)` at the point of use — an open set of labels is one letter away
from a second channel nobody reads.

**Repetition is the failure case.** `CollapsingSink` says a repeated line once and then counts, with the span: a poller meeting
an unreachable host writes the same sentence every thirty seconds for as long as the network is away, and those are the runs a
log is read for and the runs it is least readable in.

## What is in it

| | |
|---|---|
| `Log` | The facade. `bootstrap(sinks:masker:)` once from a composition root, `logger(_:)` for a channel, `flush()` for a process about to end. |
| `LogChannel` | One category, its sinks, its masker. `debug`/`info`/`notice`/`error`/`fault`, and `noting(_:_:)` — `try?` with a line, so a swallowed failure is at least named. |
| `LogMessage`, `LogValue` | The line and its fields. Tags: `.public`, `.secret`, `.userText`, `.redacted` (the default). |
| `LogCategory`, `LogLevel`, `LogEntry` | A label, a scale mirroring `OSLogType`, and what a sink receives. |
| `SecretMasking`, `DigestMasker` | The one place a secret is turned into something printable. |
| `OSLogSink`, `FileSink`, `ConsoleSink`, `CollapsingSink` | Where lines go. `OSLogSink` is Apple-only. The file sink rotates, by count or by timestamp. |
| `MessageFormat`, `PlainTextFormat`, `JSONLinesFormat` | What a line looks like once it gets there. |

## Using it

```swift
import RedactLog

extension LogCategory {
    static let sync = LogCategory(rawValue: "sync")
}

extension Log {
    static var sync: LogChannel { logger(.sync) }
}

// Once, at the start of the process, from its composition root.
var sinks: [any LogSink] = []
#if canImport(OSLog)
// Apple's system log does not exist on Linux or Windows.
sinks.append(OSLogSink(subsystem: "com.example.app"))
#endif
sinks.append(CollapsingSink(FileSink(directory: logDirectory, name: "app.log")))
Log.bootstrap(sinks: sinks)

Log.sync.notice("root \(hash, .public) refused for \(name, .userText)")
```

A second `bootstrap` is ignored rather than obeyed — two of them mean two opinions, and the later one would win in whatever
order the processes happened to start. It says so on the `redactlog` channel rather than passing in silence.

As a source dependency:

```swift
dependencies: [
    .package(url: "https://github.com/altessa-s/redactlog-swift.git", from: "0.10.0"),
],
```

Or as the `RedactLog.xcframework` a release attaches — dynamic and universal, and Apple
platforms only: an `.xcframework` is an Apple bundle, so a Linux or Windows host takes the
source dependency above. Building it and cutting a release are below.
**One copy per process**, whichever way it comes in: two copies of `LogSink` in one process means a sink installed through one
of them never receives the lines written through the other — silently, at run time, with nothing in a build to say so. A host
that embeds this framework once and links it from everywhere else is a host where that cannot happen.

A binary module carries no testability, so a consumer's tests see the public API only. A test that needs the inside of this
package belongs in this repository.

## Building the framework

```sh
Scripts/build-xcframework.sh                              # -> build/RedactLog.xcframework
Scripts/build-xcframework.sh ../some-app/Frameworks
```

`Package.swift` is the real project; `project.yml` beside it declares the same sources once more as a framework target, because
SwiftPM cannot produce a framework — archiving its library product leaves a bare `.o`. The script generates that project with
XcodeGen, archives it for macOS (arm64 and x86_64), checks that what came out is a dynamic framework of both slices, and wraps
it.

## Releasing

Releases follow gitflow: work lands in `develop`, a `release/x.y.z` branch is cut from it and merged
into `main` with `--no-ff`, and the tag goes on `main` — a tag on `develop` names a commit that
is not the release.

Push the tag. `1.2.0` and `v1.2.0` both work, and a hyphen makes it a pre-release (`1.2.0-beta.2`).

```sh
git tag 1.2.0 && git push origin 1.2.0
```

The tag runs the tests first — a release is the one artefact nobody re-reads, it is linked — then builds the framework, zips it
with `ditto` (an `.xcframework` is a bundle of symlinks, and a plain `zip` unpacks into something Xcode declines), and publishes
it with the lines a consumer pastes:

```swift
.binaryTarget(
    name: "RedactLog",
    url: "https://github.com/altessa-s/redactlog-swift/releases/download/v1.2.0/RedactLog.xcframework.zip",
    checksum: "…"
)
```

The checksum is computed in the same step from the very bytes that are uploaded, which is the reason this is a workflow and
nothing anybody does by hand: a remote binary target resolves by `url` **and** `checksum`, and one worked out on somebody's
laptop is a checksum of what was on that laptop.

The tag is also the version the framework declares. `project.yml` carries 0.0.0 — a number that says only "not a
release", and the release overrides it — a framework in a 1.2.0 release that calls itself anything else is a discrepancy
nothing would report. To reproduce a release build locally:

```sh
REDACTLOG_VERSION=1.2.0 Scripts/build-xcframework.sh
```

## Tests

```sh
swift test
```

CI runs them on macOS and, in the `swift:6.3` image, on Linux. Windows has no
image to pull and the toolchain installer resolved no version, so it is checked
by hand in a Windows VM.

What they are mostly about is what must *not* happen: that a token never reached a line, that a value nobody
classified came out redacted, that a rotation put a file aside instead of losing it, that a level nobody listens to costs
nothing, that a flush under a storm comes back. Each one gives the facade a recording sink and asks what it received.

They also name their own categories, in `TestCategories.swift`, for the same reason everything else does.
