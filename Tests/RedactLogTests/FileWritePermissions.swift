// Copyright 2026 ALTESSA SOLUTIONS INC.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file.

import Foundation

// Windows has no POSIX directory permissions, so block the file path with a
// directory there; both failures exercise the sink's existing open-error path.
func allowWrites(_ allowed: Bool, in directory: URL, name: String) throws {
    let manager = FileManager.default
    #if os(Windows)
    let blocker = directory.appending(path: name)
    if allowed {
        try manager.removeItem(at: blocker)
    } else {
        try manager.createDirectory(at: blocker, withIntermediateDirectories: false)
    }
    #else
    try manager.setAttributes([.posixPermissions: allowed ? 0o700 : 0o500], ofItemAtPath: directory.path)
    #endif
}
