import Foundation

// 1.3.3 had no persisted GIF options. Explicitly discard known older recording
// preferences; unknown obsolete keys are never read by the display-only app.
let legacyRecordingKeys = ["IsRecording", "RecordingEnabled", "RecordingFormat", "RecordingQuality",
                           "RecordingPath", "RecordingDuration", "GIFDuration", "GIFFrameRate",
                           "GIFRecordingEnabled", "RecordAudio", "AutoStartRecording"]
func migrateLegacyRecordingSettings(_ defaults: UserDefaults) {
    for key in legacyRecordingKeys { defaults.removeObject(forKey: key) }
}
