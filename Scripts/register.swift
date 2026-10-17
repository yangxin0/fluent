// Registers (and tries to enable) the installed input source. `make install`
// runs it every time:  swift Scripts/register.swift
import Carbon
import Foundation

let bundlePath = NSString(string: "~/Library/Input Methods/Fluent-Input.app").expandingTildeInPath
let bundleURL = URL(fileURLWithPath: bundlePath)

guard FileManager.default.fileExists(atPath: bundlePath) else {
    print("Not installed at \(bundlePath) — run `make install` first.")
    exit(1)
}

let status = TISRegisterInputSource(bundleURL as CFURL)
guard status == noErr else {
    print("TISRegisterInputSource failed: \(status)")
    exit(1)
}
print("Registered \(bundlePath)")

// Best effort: enable it so it shows in the input menu without a trip to
// System Settings. Selecting it is still up to the user.
let sourceID = "com.yangxin.inputmethod.Fluent"
let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
if let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
   let source = list.first {
    let enableStatus = TISEnableInputSource(source)
    if enableStatus == noErr {
        print("Enabled input source \(sourceID)")
    } else {
        print("Could not auto-enable (status \(enableStatus)) — add it in System Settings ▸ Keyboard ▸ Input Sources.")
    }
} else {
    print("Registered, but source not found yet — add it in System Settings ▸ Keyboard ▸ Input Sources (under English).")
}
