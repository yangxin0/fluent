import Cocoa
import InputMethodKit
import os.log

let log = Logger(subsystem: "com.yangxin.inputmethod.EnglishInput", category: "server")

// Must match InputMethodConnectionName in Info.plist, or IMK never connects.
let connectionName = (Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String)
    ?? "com.yangxin.inputmethod.EnglishInput_Connection"

// Retained globally so the server lives for the process lifetime.
var server: IMKServer?

autoreleasepool {
    let app = NSApplication.shared
    server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
    if server == nil {
        log.error("IMKServer failed to start for connection \(connectionName, privacy: .public)")
        exit(1)
    }
    log.info("EnglishInput IMKServer started (\(connectionName, privacy: .public))")
    ShiftTapMonitor.shared.start()
    Shuangpin.preload()
    app.run()
}
