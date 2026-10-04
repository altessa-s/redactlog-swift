// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation
@testable import RedactLog
import Synchronization
import Testing

// The unified log redacts what nobody classified, and that is what has
// kept a token out of a line all this time. Rendering the line ourselves takes
// the redaction away unless we put it back, so what the renderer does with
// each tag — and with no tag at all — is held here as tightly as the wire
// log's own masking is.

@Test("A value nobody classified is not printed")
func untaggedValuesAreRedacted() {
    let masker = DigestMasker()
    let token = "eyJhbGciOiJI.eyJleHAiOjF9.signature"
    let message: LogMessage = "token \(token) refused"

    let line = message.rendered(with: masker)
    #expect(line == "token <redacted> refused")
    #expect(!line.contains(token))
}

@Test("Each tag is rendered by what it means")
func tagsDecideTheRendering() {
    let masker = DigestMasker()
    let token = "eyJhbGciOiJI.eyJleHAiOjF9.signature"

    // Written the way a call site writes it, because that is the half that
    // has to be right: a tag is a word somebody types next to a value.
    let message: LogMessage = """
        path \("/sync/v4/root", .public), token \(token, .secret), \
        document \("Как пасти котов.pdf", .userText)
        """
    let line = message.rendered(with: masker)

    #expect(line.contains("path /sync/v4/root"))
    // The secret is unrecognisable but still tells two tokens apart.
    #expect(!line.contains(token))
    #expect(line.contains(masker.masked(token)))
    // The name is a length and an extension, never the words.
    #expect(!line.contains("котов"))
    #expect(line.contains(".pdf"))
}

@Test("The literal text of a message is not a value and is never redacted")
func literalsSurvive() {
    let line: LogMessage = "root read refused: no such path"
    #expect(line.rendered(with: DigestMasker()) == "root read refused: no such path")
}

// `os_log` never built a message nobody would read, and that is why a `debug`
// line in a walk of ten thousand documents costs nothing. Rendering our own
// text would have thrown that away silently.
@Test("A line nobody accepts is never built")
func nothingIsRenderedForAnEmptyAudience() {
    let built = Mutex(0)
    let deaf = CapturingSink(minimum: .error)
    let logger = LogChannel(category: .cloud, sinks: [deaf], masker: DigestMasker())

    logger.debug({
        built.withLock { $0 += 1 }
        return "expensive"
    }())

    #expect(built.withLock { $0 } == 0, "the message was built for a sink that refused it")
    #expect(deaf.entries.isEmpty)

    // And the same sink at a level it does take builds exactly once.
    logger.error({
        built.withLock { $0 += 1 }
        return "cheap"
    }())
    #expect(built.withLock { $0 } == 1)
    #expect(deaf.messages == ["cheap"])
}

@Test("A line goes to every sink that takes it, and to no others")
func linesFanOutByThreshold() {
    let everything = CapturingSink()
    let loudOnly = CapturingSink(minimum: .notice)
    let otherCategory = CapturingSink(only: .render)
    let logger = LogChannel(
        category: .cloud,
        sinks: [everything, loudOnly, otherCategory],
        masker: DigestMasker()
    )

    logger.debug("quiet")
    logger.error("loud")

    #expect(everything.messages == ["quiet", "loud"])
    #expect(loudOnly.messages == ["loud"])
    #expect(otherCategory.messages.isEmpty)
    // The entry carries where it came from, which is how a sink can sort.
    #expect(everything.entries.allSatisfy { $0.category == .cloud })
    #expect(everything.entries.map(\.level) == [.debug, .error])
}

// The masking moved out of `Log` into a type; what it produces must not have
// moved with it. These are the properties the old tests hold, asked of the new
// home.
@Test("The digest masker says what the old masking said")
func theMaskerIsUnchanged() {
    let masker = DigestMasker()
    let token = "eyJhbGciOiJI.eyJleHAiOjF9.signature"

    // Two maskers made separately agree: the key is the process's, not the
    // instance's, so a token reads the same wherever in a run it was masked.
    #expect(masker.masked(token) == DigestMasker().masked(token))
    #expect(masker.maskedUserText("Notes.pdf") == DigestMasker().maskedUserText("Notes.pdf"))
    #expect(masker.masked("") == "<empty>")
    // The digest is a digest: none of the token's own characters survive.
    #expect(!masker.masked(token).contains("eyJ"))
    // Two tokens that differ only in their claims must not mask alike: every
    // JWT this service issues begins the same way.
    let other = "eyJhbGciOiJI.eyJleHAiOjJ9.signature"
    #expect(masker.masked(token) != masker.masked(other))
    // A name keeps its extension and its length, and nothing else.
    #expect(masker.maskedUserText("Как пасти котов.pdf") == "<name:19>.pdf")
    #expect(masker.maskedUserText("Inbox") == "<name:5>")
}

@Test("An extension is kept only when it looks like one")
func onlyRealExtensionsSurvive() {
    let masker = DigestMasker()
    // What follows the last dot is the user's words as often as it is a
    // format, and the words are the one thing that must not be printed.
    #expect(masker.maskedUserText("plan.MergerWithAcme") == "<name:19>")
    #expect(masker.maskedUserText("Отчёт.пдф") == "<name:9>")
    #expect(masker.maskedUserText("notes.tar.gz") == "<name:12>.gz")
    #expect(masker.maskedUserText("data.jsonld") == "<name:11>.jsonld")
    #expect(masker.maskedUserText("trailing.") == "<name:9>")
}

@Test("A line is one line, whatever a value carried")
func controlCharactersAreSpelledOut() {
    let sink = CapturingSink()
    let logger = LogChannel(category: .cloud, sinks: [sink], masker: DigestMasker())
    let body = "refused\n2026-08-27T15:05:01Z [notice] cloud: token accepted"

    logger.error("server said \(body, .public)", metadata: ["detail": .public("a\rb\u{07}c")])

    let text = sink.entries[0].text
    #expect(!text.contains("\n") && !text.contains("\r"))
    #expect(text.hasPrefix("server said refused\\n2026-08-27"))
    #expect(text.hasSuffix("{detail=a\\rb\\u{7}c}"))
    // A tab is layout, not a line, and stays.
    #expect(LogEntry.oneLine("a\tb") == "a\tb")
    // JSON spells its own escapes; the raw message is still what it encodes.
    #expect(sink.entries[0].message.contains("\n"))
}

// Metadata is the half of a line worth filtering on later, and it is exactly
// as dangerous as the prose: a document's name is a document's name whether it
// sits in a sentence or under a key.

@Test("A field is masked by its tag, like everything else in the line")
func metadataFollowsTheSameTags() throws {
    let sink = CapturingSink()
    let logger = LogChannel(category: .sync, sinks: [sink], masker: DigestMasker())
    let token = "eyJhbGciOiJI.eyJleHAiOjF9.signature"

    logger.info("document read", metadata: [
        "pages": .public(12),
        "document": .userText("Как пасти котов.pdf"),
        "token": .secret(token),
        "generation": LogValue(1_787_757_030_311_897),
    ])

    let entry = try #require(sink.entries.first)
    #expect(entry.metadata["pages"] == "12")
    #expect(entry.metadata["document"] == "<name:19>.pdf")
    #expect(entry.metadata["token"] == DigestMasker().masked(token))
    // Untagged is redacted here for the same reason it is in the message: a
    // value nobody classified is a value nobody thought about.
    #expect(entry.metadata["generation"] == "<redacted>")
    #expect(!entry.text.contains(token))
    #expect(!entry.text.contains("котов"))
}

@Test("The fields are printed after the message, sorted, and only when there are any")
func metadataIsPrintedWithTheLine() throws {
    let sink = CapturingSink()
    let logger = LogChannel(category: .cloud, sinks: [sink], masker: DigestMasker())

    logger.notice("root written", metadata: ["to": .public("v3"), "from": .public("v4")])
    logger.notice("nothing to add")

    // `key=value` pairs, sorted by key: the shape every log-reading tool
    // already greps for, and two runs of the same code compare by eye.
    #expect(sink.entries[0].text == "root written {from=v4 to=v3}")
    // And a line with no fields is the line, with nothing appended.
    #expect(sink.entries[1].text == "nothing to add")
    #expect(sink.entries[1].metadata.isEmpty)
}

@Test("Fields are not built for a line nobody accepts")
func metadataIsLazyToo() {
    let built = Mutex(0)
    let deaf = CapturingSink(minimum: .error)
    let logger = LogChannel(category: .cloud, sinks: [deaf], masker: DigestMasker())

    logger.debug("quiet", metadata: {
        built.withLock { $0 += 1 }
        return ["expensive": .public("field")]
    }())

    #expect(built.withLock { $0 } == 0, "fields were built for a sink that refused the line")
}

/// The two cases about what a whole process installed, and they are the only
/// ones here that write to something shared. Serialized because of it: the
/// suite runs in parallel by default, and a second case swapping the sinks
/// half way through the first would fail it for a reason that is not the
/// property under test.
@Suite("The installation of a process", .serialized)
struct LogInstallationTests {
    @Test("A process that never bootstraps still logs, and still masks")
    func theDefaultIsSafe() {
        // Whatever the suite has installed by now, asking for a logger answers
        // with one rather than with nil, and masking works with no bootstrap
        // at all — a process that never calls it is a supported state.
        Log.logger(.sync).debug("a line that goes to whatever this process installed")
        #expect(Log.masked("secret") != "secret")
    }

    @Test("Bootstrap is once; a second opinion is ignored")
    func bootstrapIsOnce() {
        let first = CapturingSink()
        let second = CapturingSink()
        // `install` is the test-only door: `bootstrap` refuses to be re-run,
        // which is the property being checked, and a suite cannot check it
        // twice from a clean state without one.
        Log.install(sinks: [first])
        Log.bootstrap(sinks: [second])

        Log.logger(.cloud).notice("after")

        #expect(second.messages.isEmpty, "a second bootstrap replaced the first")
        // The refusal is said out loud through whatever was installed first:
        // a bootstrap that is ignored in silence costs somebody an afternoon.
        #expect(first.messages.contains { $0.contains("second logging bootstrap was ignored") })
        #expect(first.messages.contains("after"))

        // Left as it was found — no sinks — so the order of the suite decides
        // nothing, and no test writes to the unified log of the machine it
        // runs on.
        Log.install(sinks: [])
    }

    @Test("Masking outside a message goes through the masker the process installed")
    func maskedAsksTheInstalledMasker() {
        struct Loud: SecretMasking {
            func masked(_ secret: String) -> String { "<masked>" }
            func maskedUserText(_ name: String) -> String { "<name>" }
        }
        Log.install(sinks: [], masker: Loud())
        defer { Log.install(sinks: []) }

        // A host that chose its own masker has one policy, not two: the path
        // that masks without a logger asks the same one the lines go through.
        #expect(Log.masked("token") == "<masked>")
        #expect(Log.maskedUserText("Diary.pdf") == "<name>")
    }
}

@Test("A noted failure is swallowed as try? would, and named in the log")
func notingSwallowsAndNames() async {
    struct Refused: Error {}
    let sink = CapturingSink(minimum: .error)
    let logger = LogChannel(category: .sync, sinks: [sink], masker: DigestMasker())

    let answered: Int? = logger.noting("count not read") { 7 }
    let failed: Int? = logger.noting("count not read") { throw Refused() }
    // A body that answers with an optional of its own comes back one level
    // deep: a missing value and a failed read meet the caller's `??` alike.
    let missing: String? = logger.noting("name not read") { nil as String? }
    // A body that suspends, so that the overload taken is the async one and
    // not the sync one with an `await` nobody needed.
    let late: Int? = await logger.noting("late count not read") {
        await Task.yield()
        throw Refused()
    }

    #expect(answered == 7)
    #expect(failed == nil)
    #expect(missing == nil)
    #expect(late == nil)
    #expect(sink.messages.count == 2)
    #expect(sink.text.contains("count not read: Refused()"))
    #expect(sink.text.contains("late count not read: Refused()"))
}

@Test("A platform error is named by its domain and code, never by what it carries")
func notingDoesNotPrintAnErrorsUserInfo() {
    let sink = CapturingSink(minimum: .error)
    let logger = LogChannel(category: .sync, sinks: [sink], masker: DigestMasker())
    let path = "/Users/someone/Documents/Diary.pdf"

    // What Foundation hands back for a missing file: the path is in the user
    // info and in the description, and the description is not ours to print.
    let missing: Data? = logger.noting("document not read") {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: path])
    }
    let unreachable: Data? = logger.noting("root not fetched") {
        throw URLError(.badURL, userInfo: [NSURLErrorFailingURLStringErrorKey: "https://h/secret"])
    }

    #expect(missing == nil && unreachable == nil)
    #expect(sink.messages == ["document not read: NSCocoaErrorDomain 4", "root not fetched: NSURLErrorDomain -1000"])
    #expect(!sink.text.contains("Diary") && !sink.text.contains("secret"))
}
