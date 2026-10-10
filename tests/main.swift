import Foundation

var assertions = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    guard condition() else { fatalError(message) }
}
let suiteName = "ThatMirroring.Tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suiteName)!
defer { defaults.removePersistentDomain(forName: suiteName) }
for key in legacyRecordingKeys { defaults.set(["old", "malformed"], forKey: key) }
defaults.set(true, forKey: "PlayDeviceAudio")
defaults.set("usb-camera", forKey: "SelectedDeviceID")
defaults.set("Giant Circle", forKey: "SelectedAnimation")
defaults.set(false, forKey: "AutoCropBlackBars")
defaults.set("ignored", forKey: "UnknownLegacyRecordingOption")
migrateLegacyRecordingSettings(defaults)
for key in legacyRecordingKeys { expect(defaults.object(forKey: key) == nil, "legacy key remains") }
expect(defaults.bool(forKey: "PlayDeviceAudio"), "audio setting lost")
expect(defaults.string(forKey: "SelectedDeviceID") == "usb-camera", "device lost")
expect(defaults.string(forKey: "SelectedAnimation") == "Giant Circle", "highlight lost")
expect(defaults.object(forKey: "AutoCropBlackBars") as? Bool == false, "crop lost")
migrateLegacyRecordingSettings(defaults)
expect(defaults.string(forKey: "UnknownLegacyRecordingOption") == "ignored", "unknown option should be harmless")
print("\(assertions) assertions passed")
