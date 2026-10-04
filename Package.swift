// swift-tools-version: 6.3
// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

// Process logs: a facade a host installs once, channels the code writes to,
// tagged messages whose secrets meet a masker exactly once, and sinks for the
// system log, a rotating file and a terminal.
//
// It depends on nothing, and that is the whole of its design. Nothing here names
// a product: not the categories a process is divided into, not the subsystem the
// system log answers to, not the file a sink writes. Each of those is the host's,
// named from a composition root, and not called at all is a supported state —
// then nothing is written, because a library that logs somewhere nobody asked
// for is a library that has to be worked around.
import PackageDescription

let package = Package(
    name: "RedactLog",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "RedactLog", targets: ["RedactLog"]),
    ],
    targets: [
        .target(
            name: "RedactLog",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "RedactLogTests",
            dependencies: ["RedactLog"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
