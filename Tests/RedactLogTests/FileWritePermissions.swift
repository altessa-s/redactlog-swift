// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

// Windows has no POSIX directory permissions, so block the file path with a
// directory there; both failures exercise the sink's existing open-error path.
func allowWrites(_ allowed: Bool, in directory: URL, name: String) throws {
    let manager = FileManager.default
    #if os(Windows)
    // A read-only file rather than a directory at the path: the sink opens the
    // path once and keeps it, and a directory that is open cannot be removed
    // when the test wants writes back.
    let blocker = directory.appending(path: name)
    if allowed {
        if manager.fileExists(atPath: blocker.path) {
            try? manager.setAttributes([.immutable: false], ofItemAtPath: blocker.path)
            try manager.removeItem(at: blocker)
        }
    } else {
        manager.createFile(atPath: blocker.path, contents: Data())
        try manager.setAttributes([.immutable: true], ofItemAtPath: blocker.path)
    }
    #else
    try manager.setAttributes([.posixPermissions: allowed ? 0o700 : 0o500], ofItemAtPath: directory.path)
    #endif
}
