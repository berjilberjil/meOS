import Foundation
import os

/// The app had no logging at all — no print, no NSLog, no os_log — which meant
/// a bug that only reproduces on device was invisible. These go to the unified
/// log, so `log stream --predicate 'subsystem == "com.berjil.meos"'` (or
/// Console.app) shows them live without attaching a debugger.
enum Log {
    private static let subsystem = "com.berjil.meos"

    static let notes = Logger(subsystem: subsystem, category: "notes")
    static let sync  = Logger(subsystem: subsystem, category: "sync")
    static let media = Logger(subsystem: subsystem, category: "media")
}
