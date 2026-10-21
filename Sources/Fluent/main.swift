import Cocoa
import InputMethodKit
import os.log

let log = Logger(subsystem: "com.yangxin.inputmethod.Fluent", category: "server")

// Must match InputMethodConnectionName in Info.plist, or IMK never connects.
let connectionName = (Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String)
    ?? "com.yangxin.inputmethod.Fluent_Connection"

// Retained globally so the server lives for the process lifetime.
var server: IMKServer?

autoreleasepool {
    let app = NSApplication.shared
    server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
    if server == nil {
        log.error("IMKServer failed to start for connection \(connectionName, privacy: .public)")
        exit(1)
    }
    log.info("Fluent IMKServer started (\(connectionName, privacy: .public))")
    ShiftTapMonitor.shared.start()
    InputSourceWatcher.shared.start()
    ChineseInput.preload()
    app.run()
}
