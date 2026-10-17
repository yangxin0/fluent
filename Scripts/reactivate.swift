// After the IME process is killed (make reload), the front app keeps its
// existing text-input session: keyDown still reaches the relaunched IME,
// but modifier-only (flagsChanged) events are not delivered again until
// the input source is re-activated — so the ⇧⇧ toggle silently stops
// working until the user switches apps. Bounce the selection to a
// keyboard layout and back to force that re-activation.
import Carbon
import Foundation

let sourceID = "com.yangxin.inputmethod.Fluent"

func id(of source: TISInputSource) -> String {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      id(of: current) == sourceID
else {
    print("Fluent is not the selected input source; nothing to re-activate.")
    exit(0)
}

guard let layout = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else {
    print("No ASCII-capable keyboard layout to bounce through; switch apps once to re-activate.")
    exit(0)
}

let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
      let ours = list.first
else {
    print("Input source \(sourceID) not found; run `make register`.")
    exit(1)
}

var status = TISSelectInputSource(layout)
guard status == noErr else { print("Could not select \(id(of: layout)): \(status)"); exit(1) }
usleep(200_000)
status = TISSelectInputSource(ours)
guard status == noErr else { print("Could not re-select \(sourceID): \(status)"); exit(1) }
print("Re-activated \(sourceID) (via \(id(of: layout)))")
