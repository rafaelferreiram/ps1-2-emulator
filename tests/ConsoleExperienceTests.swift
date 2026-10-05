import AppKit
import SwiftUI

// Standalone test: does not load the launcher or start emulators.
enum Console: String, CaseIterable {
    case ps1, ps2
    var badge: String { self == .ps1 ? "PS1" : "PS2" }
}

@main
@MainActor
struct ConsoleExperienceTests {
    static var assertions = 0
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertions += 1
        guard condition() else { fatalError("FAIL: \(message)") }
    }
    static func main() throws {
        let suite = "local.ps12.tests.experience.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ExperiencePreferences(defaults: defaults)
        require(preferences.startupMode == .full, "existing full startup remains default")
        require(!preferences.soundsEnabled, "new sounds are opt-in")
        require(preferences.soundVolume == 0.35, "gentle default volume")
        require(!preferences.reduceMotion(system: false), "system motion preference is default")
        require(preferences.reduceMotion(system: true), "system reduced motion cannot be overridden")
        preferences.motionMode = .reduced
        require(preferences.reduceMotion(system: false), "app-specific reduced motion can be enabled")
        preferences.startupMode = .short
        preferences.soundsEnabled = true
        preferences.soundVolume = 0.7
        let restored = ExperiencePreferences(defaults: defaults)
        require(restored.startupMode == .short && restored.soundsEnabled && restored.soundVolume == 0.7, "choices persist")
        require(restored.motionMode == .reduced, "motion choice persists")
        require(restored.focusedSetting == .startup, "transient focus is not persisted")
        restored.moveFocus(-1)
        require(restored.focusedSetting == .startup, "focus clamps at the first setting")
        restored.adjust(1)
        require(restored.startupMode == .off, "right cycles startup options")
        restored.adjust(1)
        require(restored.startupMode == .full, "startup choices wrap")
        restored.adjust(-1)
        require(restored.startupMode == .off, "left cycles startup options in reverse")
        restored.moveFocus(1)
        require(!restored.confirmSelection() && !restored.soundsEnabled, "X toggles sound without dismissing")
        restored.moveFocus(1)
        restored.soundVolume = 0.95
        restored.adjust(1)
        require(restored.soundVolume == 1, "controller volume clamps to maximum")
        restored.soundVolume = -1
        require(restored.soundVolume == 0, "negative volume clamps to zero")
        restored.soundVolume = .nan
        require(restored.soundVolume == 0.35, "invalid volume uses safe default")
        restored.moveFocus(100)
        require(restored.focusedSetting == .done && restored.confirmSelection(), "Done signals overlay dismissal")
        require(StartupMode.full.durationLimit == nil && StartupMode.short.durationLimit == 1.4 && StartupMode.off.durationLimit == 0,
                "boot modes expose unambiguous timing semantics")
        var allWaves = Set<Data>()
        for console in Console.allCases {
            for cue in ConsoleSoundCue.allCases {
                let wave = ConsoleSoundPlayer.waveData(cue, console: console)
                require(String(data: wave.prefix(4), encoding: .utf8) == "RIFF", "RIFF header")
                require(String(data: wave[8..<12], encoding: .utf8) == "WAVE", "WAV header")
                require(wave.count > 2_000 && wave.count < 6_000, "cue is short and memory-bounded")
                require(NSSound(data: wave) != nil, "AppKit decodes cue without playback")
                require(wave == ConsoleSoundPlayer.waveData(cue, console: console), "synthesis is deterministic")
                allWaves.insert(wave)
            }
        }
        require(allWaves.count == 6, "six distinct original cues")
        print("PASS: \(assertions) console experience assertions; no audio played or emulator launched.")
    }
}
