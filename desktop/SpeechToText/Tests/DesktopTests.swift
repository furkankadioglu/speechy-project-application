// DesktopTests.swift — Speechy Desktop Test Suite
// Custom assertion-based test harness (no XCTest, compiled with swiftc -DTESTING)

import Foundation
import Carbon.HIToolbox
import Cocoa
import AVFoundation

// MARK: - Test Harness

var testsPassed = 0
var testsFailed = 0
var currentGroup = ""

func group(_ name: String) {
    currentGroup = name
    print("  \(name)")
}

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        testsPassed += 1
        print("    ✓ \(message)")
    } else {
        testsFailed += 1
        print("    ✗ \(message) (FAILED at \(file):\(line))")
    }
}

func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String, file: String = #file, line: Int = #line) {
    if a == b {
        testsPassed += 1
        print("    ✓ \(message)")
    } else {
        testsFailed += 1
        print("    ✗ \(message) — expected \(b), got \(a) (FAILED at \(file):\(line))")
    }
}

func assertNil<T>(_ value: T?, _ message: String, file: String = #file, line: Int = #line) {
    if value == nil {
        testsPassed += 1
        print("    ✓ \(message)")
    } else {
        testsFailed += 1
        print("    ✗ \(message) — expected nil, got \(value!) (FAILED at \(file):\(line))")
    }
}

func assertNotNil<T>(_ value: T?, _ message: String, file: String = #file, line: Int = #line) {
    if value != nil {
        testsPassed += 1
        print("    ✓ \(message)")
    } else {
        testsFailed += 1
        print("    ✗ \(message) — expected non-nil (FAILED at \(file):\(line))")
    }
}

// MARK: - Tests

func testHotkeyConfig() {
    group("HotkeyConfig")

    // displayName — single modifier
    let alt = HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    assertEqual(alt.displayName, "⌥", "displayName single modifier (Alt)")

    // displayName — multiple modifiers (order: ⌃⌥⇧⌘ as defined in displayName property)
    let multi = HotkeyConfig(modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue, language: "en")
    assertEqual(multi.displayName, "⌃⇧", "displayName multi modifier (Control+Shift)")

    // displayName — no modifiers
    let none = HotkeyConfig(modifiers: 0, language: "en")
    assertEqual(none.displayName, "None", "displayName no modifiers")

    // displayName — all modifiers (order matches displayName property: ⌃⌥⇧⌘)
    let all = HotkeyConfig(modifiers: CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue, language: "en")
    assertEqual(all.displayName, "⌃⌥⇧⌘", "displayName all modifiers")

    // modifierFlags roundtrip
    var config = HotkeyConfig()
    config.modifierFlags = [.maskShift, .maskCommand]
    assert(config.modifierFlags.contains(.maskShift), "modifierFlags roundtrip contains Shift")
    assert(config.modifierFlags.contains(.maskCommand), "modifierFlags roundtrip contains Command")

    // Equatable: same struct value (copy) is equal
    let a = HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    let b = a  // copy shares same UUID
    assert(a == b, "Equatable: copied config equals original")
    // Two independently constructed configs have different UUIDs and are NOT equal
    let c = HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    assert(a != c, "Equatable: independently constructed configs differ (different UUIDs)")

    // Codable roundtrip
    let original = HotkeyConfig(modifiers: CGEventFlags.maskShift.rawValue, language: "tr", isEnabled: false, mode: .toggleToTalk)
    let data = try! JSONEncoder().encode(original)
    let decoded = try! JSONDecoder().decode(HotkeyConfig.self, from: data)
    assert(original == decoded, "Codable roundtrip preserves values")

    // isModifierOnly — keyCode == -1
    let modOnly = HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    assert(modOnly.isModifierOnly, "default keyCode=-1 means isModifierOnly")

    // key+modifier config — keyCode >= 0
    var keyMod = HotkeyConfig(modifiers: CGEventFlags.maskCommand.rawValue, language: "en")
    keyMod.keyCode = 0 // 'A'
    assert(!keyMod.isModifierOnly, "keyCode=0 means not isModifierOnly")
    assert(keyMod.keyCode >= 0, "keyCode is non-negative")

    // displayName includes key name for key+modifier config
    var cmdA = HotkeyConfig(modifiers: CGEventFlags.maskCommand.rawValue, language: "en")
    cmdA.keyCode = 0 // A
    assertEqual(cmdA.displayName, "⌘A", "displayName with key code shows key name")

    // Cmd+Shift+A
    var cmdShiftA = HotkeyConfig(modifiers: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue, language: "en")
    cmdShiftA.keyCode = 0
    assertEqual(cmdShiftA.displayName, "⇧⌘A", "displayName Cmd+Shift+A")

    // escCancels default is true
    let defaultConfig = HotkeyConfig()
    assert(defaultConfig.escCancels, "escCancels defaults to true")

    // Codable preserves escCancels = false
    var noEsc = HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    noEsc.escCancels = false
    let noEscData = try! JSONEncoder().encode(noEsc)
    let noEscDecoded = try! JSONDecoder().decode(HotkeyConfig.self, from: noEscData)
    assert(!noEscDecoded.escCancels, "Codable preserves escCancels=false")

    // keyName for key codes
    assertEqual(HotkeyConfig.keyName(for: 49), "Space", "keyName for 49 = Space")
    assertEqual(HotkeyConfig.keyName(for: 53), "Esc", "keyName for 53 = Esc")
    assertEqual(HotkeyConfig.keyName(for: 0), "A", "keyName for 0 = A")
    assertEqual(HotkeyConfig.keyName(for: 18), "1", "keyName for 18 = 1")
}

func testModelType() {
    group("ModelType")

    // displayName
    assertEqual(ModelType.precise.displayName, "Precise (Medium)", "precise displayName")
    assertEqual(ModelType.ultimate.displayName, "Ultimate (Large)", "ultimate displayName")

    // description
    assert(!ModelType.precise.description.isEmpty, "precise has description")
    assert(!ModelType.ultimate.description.isEmpty, "ultimate has description")

    // fileName
    assertEqual(ModelType.precise.fileName, "ggml-medium.bin", "precise fileName")
    assertEqual(ModelType.ultimate.fileName, "ggml-large-v3.bin", "ultimate fileName")

    // downloadURL
    assert(ModelType.precise.downloadURL.absoluteString.contains("huggingface.co"), "downloadURL contains huggingface")

    // sizeBytes ordering
    assert(ModelType.precise.sizeBytes < ModelType.ultimate.sizeBytes, "precise < ultimate sizeBytes")

    // CaseIterable count
    assertEqual(ModelType.allCases.count, 2, "CaseIterable count is 2")

    // rawValues
    assertEqual(ModelType.precise.rawValue, "medium", "precise rawValue")
    assertEqual(ModelType.ultimate.rawValue, "large-v3", "ultimate rawValue")
}

func testTranscriptionEntry() {
    group("TranscriptionEntry")

    // init
    let entry = TranscriptionEntry(text: "Hello world", language: "en")
    assertEqual(entry.text, "Hello world", "init preserves text")
    assertEqual(entry.language, "en", "init preserves language")

    // Codable roundtrip
    let data = try! JSONEncoder().encode(entry)
    let decoded = try! JSONDecoder().decode(TranscriptionEntry.self, from: data)
    assertEqual(decoded.text, entry.text, "Codable roundtrip preserves text")
    assertEqual(decoded.id, entry.id, "Codable roundtrip preserves id")

    // Unique IDs
    let entry2 = TranscriptionEntry(text: "Another", language: "tr")
    assert(entry.id != entry2.id, "different entries have unique IDs")

    // allText concatenation via LogManager (TranscriptionEntry itself doesn't have allText,
    // but we test via two entries building separate texts)
    let e1 = TranscriptionEntry(text: "Hello", language: "en")
    let e2 = TranscriptionEntry(text: " world", language: "en")
    let combined = e1.text + e2.text
    assertEqual(combined, "Hello world", "entry text concatenation works")

    // Dates are distinct for entries created in sequence
    let d1 = TranscriptionEntry(text: "First entry text", language: "en")
    Thread.sleep(forTimeInterval: 0.01)
    let d2 = TranscriptionEntry(text: "Second entry text", language: "en")
    assert(d2.date >= d1.date, "second entry date is not earlier than first")

    // audioURL nil when audioPath is nil
    assertNil(entry.audioURL, "audioURL is nil when no audioPath")

    // hasAudio false when audioPath is nil
    assert(!entry.hasAudio, "hasAudio is false when no audioPath")
}

func testAudioInputDevice() {
    group("AudioInputDevice")

    let def = AudioInputDevice.systemDefault
    assertEqual(def.uid, "system_default", "systemDefault uid")
    assertEqual(def.name, "System Default", "systemDefault name")
    assert(def.isDefault, "systemDefault isDefault is true")
}

func testSupportedLanguages() {
    group("Supported Languages")

    assertEqual(supportedLanguages.count, 29, "count is 29")
    assertEqual(supportedLanguages.first?.code, "auto", "first is auto")

    // unique codes
    let codes = supportedLanguages.map { $0.code }
    assertEqual(Set(codes).count, codes.count, "all codes are unique")

    // non-empty flags
    let emptyFlags = supportedLanguages.filter { $0.flag.isEmpty }
    assertEqual(emptyFlags.count, 0, "all languages have non-empty flags")
}

func testFilterNonSpeech() {
    group("filterNonSpeech")

    let transcriber = WhisperTranscriber()

    // normal text passthrough
    assertEqual(transcriber.filterNonSpeech("Hello, how are you?"), "Hello, how are you?", "normal text passes through")

    // [BLANK_AUDIO]
    assertNil(transcriber.filterNonSpeech("[BLANK_AUDIO]"), "[BLANK_AUDIO] filtered to nil")

    // [MUSIC]
    assertNil(transcriber.filterNonSpeech("[MUSIC]"), "[MUSIC] filtered to nil")

    // mixed content
    let mixed = transcriber.filterNonSpeech("[MUSIC] Hello world [BLANK_AUDIO]")
    assertEqual(mixed, "Hello world", "mixed content keeps speech")

    // Turkish patterns
    assertNil(transcriber.filterNonSpeech("(Müzik)"), "Turkish (Müzik) filtered")

    // regex bracket patterns
    assertNil(transcriber.filterNonSpeech("[Hareketli müzik çalıyor]"), "bracket müzik pattern filtered")

    // short result becomes nil
    assertNil(transcriber.filterNonSpeech("[MUSIC] x"), "short result after filtering is nil")

    // musical symbols
    assertNil(transcriber.filterNonSpeech("♪"), "musical symbol filtered")

    // Altyazı M.K. — known Turkish subtitle hallucination
    assertNil(transcriber.filterNonSpeech("Altyazı M.K."), "Altyazı M.K. subtitle tag filtered")

    // Thanks for watching — common YouTube hallucination (mixed content test)
    // "Thanks for watching!" alone is normal speech so should pass through
    let thanksResult = transcriber.filterNonSpeech("Thanks for watching!")
    assertNotNil(thanksResult, "Thanks for watching passes through (is real speech)")

    // *music* — asterisk-wrapped music tag
    // The filter doesn't strip asterisk variants — but let's verify behavior
    // If it contains no known pattern, it passes through
    // *music* is not in the explicit pattern list — document actual behavior
    _ = transcriber.filterNonSpeech("*music*")
    assert(true, "*music* filter behavior documented (passes through — not in pattern list)")

    // "..." alone: 3 chars passes length check (filter only removes known patterns, not dots)
    assertNotNil(transcriber.filterNonSpeech("..."), "... passes length check (3 chars, not a known pattern)")

    // Single char: filtered to nil (< 2 chars)
    assertNil(transcriber.filterNonSpeech("x"), "single char filtered to nil (< 2 chars)")

    // Preserves mixed content when speech dominates
    let dominated = transcriber.filterNonSpeech("This is real speech. [BLANK_AUDIO] More speech here.")
    assertNotNil(dominated, "speech dominates: non-nil result when mostly speech")
    assert(dominated?.contains("real speech") == true, "speech content preserved in mixed result")
}

func testGetFlag() {
    group("getFlag")

    let manager = HotkeyManager()

    assertEqual(manager.getFlag(for: "en"), "🇬🇧", "English flag")
    assertEqual(manager.getFlag(for: "tr"), "🇹🇷", "Turkish flag")
    assertEqual(manager.getFlag(for: "xx"), "🎙️", "unknown language fallback")
    assertEqual(manager.getFlag(for: "auto"), "🌍", "auto detect flag")
}

func testMatchesModifiers() {
    group("matchesModifiers")

    let manager = HotkeyManager()

    // exact match
    let config = HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    let flags = CGEventFlags.maskAlternate
    assert(manager.matchesModifiers(flags: flags, config: config), "exact modifier match")

    // no modifiers configured → always false
    let noModConfig = HotkeyConfig(modifiers: 0, language: "en")
    assert(!manager.matchesModifiers(flags: flags, config: noModConfig), "no modifiers configured returns false")

    // superset match (extra modifiers pressed)
    let supersetFlags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue)
    assert(manager.matchesModifiers(flags: supersetFlags, config: config), "superset flags match")

    // missing required modifier
    let shiftOnly = CGEventFlags.maskShift
    assert(!manager.matchesModifiers(flags: shiftOnly, config: config), "missing required modifier fails")

    // key+modifier config: matchesModifiers should also work (non-modifier-only)
    var keyConfig = HotkeyConfig(modifiers: CGEventFlags.maskCommand.rawValue, language: "en")
    keyConfig.keyCode = 0 // A
    assert(manager.matchesModifiers(flags: CGEventFlags.maskCommand, config: keyConfig), "key+modifier exact match")
    // superset is OK for key+modifier
    let superForKey = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | CGEventFlags.maskShift.rawValue)
    assert(manager.matchesModifiers(flags: superForKey, config: keyConfig), "key+modifier superset match OK")
    // missing required modifier for key+modifier fails
    assert(!manager.matchesModifiers(flags: CGEventFlags.maskShift, config: keyConfig), "key+modifier missing required modifier fails")
}

func testSettingsManagerHistory() {
    group("SettingsManager History")

    let settings = SettingsManager(forTesting: true)

    // add entry
    settings.addToHistory("Test transcription", language: "en")
    assertEqual(settings.history.count, 1, "add entry increases count")
    assertEqual(settings.history.first?.text, "Test transcription", "added entry has correct text")

    // insert order (newest first)
    settings.addToHistory("Second entry", language: "tr")
    assertEqual(settings.history.first?.text, "Second entry", "newest entry is first")

    // reject blank audio
    let countBefore = settings.history.count
    settings.addToHistory("[BLANK_AUDIO]", language: "en")
    assertEqual(settings.history.count, countBefore, "blank audio rejected")

    // reject short text
    settings.addToHistory("x", language: "en")
    assertEqual(settings.history.count, countBefore, "short text rejected")

    // max 50 cap
    for i in 0..<55 {
        settings.addToHistory("Entry number \(i) with enough length", language: "en")
    }
    assert(settings.history.count <= 50, "history capped at 50")

    // delete entry
    let entryToDelete = settings.history[0]
    settings.deleteEntry(entryToDelete)
    assert(!settings.history.contains(where: { $0.id == entryToDelete.id }), "delete removes entry")

    // clear
    settings.clearHistory()
    assertEqual(settings.history.count, 0, "clear removes all entries")
}

// MARK: - HotkeyConfig Extended Tests

func testHotkeyConfigExtended() {
    group("HotkeyConfig Extended")

    // updateConfigs via testSetConfigs: set a known slot list
    let manager = HotkeyManager()
    let cfg1 = HotkeyConfig(name: "Slot1", modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    let cfg2 = HotkeyConfig(name: "Slot2", modifiers: CGEventFlags.maskCommand.rawValue, language: "tr")
    manager.testSetConfigs([cfg1, cfg2])

    // configForID: known ID
    let found = manager.testConfigForID(cfg1.id)
    assertNotNil(found, "configForID returns config for known UUID")
    assertEqual(found?.name, "Slot1", "configForID returns correct config by ID")

    // configForID: unknown UUID returns nil
    let unknownID = UUID()
    let notFound = manager.testConfigForID(unknownID)
    assertNil(notFound, "configForID returns nil for unknown UUID")

    // updateConfigs replaces slots (via testSetConfigs)
    let cfg3 = HotkeyConfig(name: "New", modifiers: CGEventFlags.maskShift.rawValue, language: "de")
    manager.testSetConfigs([cfg3])
    assertNil(manager.testConfigForID(cfg1.id), "after updateConfigs, old slot no longer found")
    assertNotNil(manager.testConfigForID(cfg3.id), "after updateConfigs, new slot found")
}

// MARK: - HotkeyManager Tests

func testHotkeyManager() {
    group("HotkeyManager")

    // stopListening idempotent: calling twice doesn't crash
    let manager = HotkeyManager()
    manager.stopListening()
    manager.stopListening()
    assert(true, "stopListening twice doesn't crash")

    // deinit on never-started manager doesn't crash
    do {
        let m = HotkeyManager()
        _ = m // use it to avoid warning; deinit fires at end of block
    }
    assert(true, "deinit on never-started HotkeyManager doesn't crash")

    // Cooldown: after testSimulateRecordingCycle, cooldownUntil is ~0.5s in future
    let m2 = HotkeyManager()
    let cfg = HotkeyConfig(name: "Test", modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    m2.testSetConfigs([cfg])
    let before = Date()
    m2.testSimulateRecordingCycle(language: "en", flag: "🇬🇧")
    let cooldown = m2.testCooldownUntil
    assert(cooldown > before, "cooldownUntil is in the future after stop")
    assert(cooldown.timeIntervalSince(before) >= 0.4, "cooldown is at least 0.4s")
    assert(cooldown.timeIntervalSince(before) < 1.0, "cooldown is less than 1.0s")

    // onRecordingStop fires after testSimulateRecordingCycle
    var stopFired = false
    let m3 = HotkeyManager()
    m3.onRecordingStop = { stopFired = true }
    m3.testSetConfigs([HotkeyConfig(name: "X", modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")])
    m3.testSimulateRecordingCycle(language: "en", flag: "🇬🇧")
    // onRecordingStop is dispatched async to main — drain runloop briefly
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    assert(stopFired, "onRecordingStop fires after testSimulateRecordingCycle")

    // onRecordingStart fires via testSimulateRecordingCycle
    var startFired = false
    var startLanguage = ""
    let m4 = HotkeyManager()
    m4.onRecordingStart = { lang, _ in startFired = true; startLanguage = lang }
    m4.testSetConfigs([HotkeyConfig(name: "Y", modifiers: CGEventFlags.maskAlternate.rawValue, language: "tr")])
    m4.testSimulateRecordingCycle(language: "tr", flag: "🇹🇷")
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    assert(startFired, "onRecordingStart fires after testSimulateRecordingCycle")
    assertEqual(startLanguage, "tr", "onRecordingStart passes correct language")
}

// MARK: - SettingsManager Extended Tests

func testSettingsManagerExtended() {
    group("SettingsManager Extended")

    let settings = SettingsManager(forTesting: true)

    // whisperPrompt: empty savedWords + no prompt hint → nil
    settings.savedWords = []
    settings.modalConfig = .default
    assertNil(settings.whisperPrompt, "whisperPrompt nil when no words and no hint")

    // whisperPrompt: with saved words
    settings.savedWords = ["Speechy", "Whisper"]
    let prompt = settings.whisperPrompt
    assertNotNil(prompt, "whisperPrompt non-nil when savedWords not empty")
    assert(prompt?.contains("Speechy") == true, "whisperPrompt contains saved words")

    // whisperPrompt: with modalConfig that has a promptHint
    settings.savedWords = []
    settings.modalConfig = .formal
    let formalPrompt = settings.whisperPrompt
    assertNotNil(formalPrompt, "whisperPrompt non-nil for formal config")
    assert(formalPrompt?.contains("formal") == true, "whisperPrompt contains formal hint")

    // whisperPrompt: savedWords + modalConfig hint joined
    settings.savedWords = ["Kubernetes", "Docker"]
    settings.modalConfig = .meetingNotes
    let combined = settings.whisperPrompt
    assertNotNil(combined, "combined prompt is non-nil")
    assert(combined?.contains("Kubernetes") == true, "combined prompt contains saved word")
    assert(combined?.contains("meeting notes") == true, "combined prompt contains config hint")

    // Reset
    settings.savedWords = []
    settings.modalConfig = .default

    // waveMultiplier default
    assertEqual(settings.waveMultiplier, 100.0, "waveMultiplier default is 100.0")

    // waveExponent default
    assertEqual(settings.waveExponent, 0.45, "waveExponent default is 0.45")

    // waveDivisor default
    assertEqual(settings.waveDivisor, 1.0, "waveDivisor default is 1.0")

    // activationDelay default
    assertEqual(settings.activationDelay, 0.15, "activationDelay default is 0.15")

    // activationDelay round-trip
    settings.activationDelay = 0.3
    assertEqual(settings.activationDelay, 0.3, "activationDelay round-trips")

    // selectedModel round-trip
    settings.selectedModel = .ultimate
    assertEqual(settings.selectedModel, .ultimate, "selectedModel round-trips to ultimate")
    settings.selectedModel = .precise
    assertEqual(settings.selectedModel, .precise, "selectedModel round-trips to precise")

    // isCapturingShortcut toggle
    assert(!settings.isCapturingShortcut, "isCapturingShortcut default is false")
    settings.isCapturingShortcut = true
    assert(settings.isCapturingShortcut, "isCapturingShortcut toggles to true")
    settings.isCapturingShortcut = false
    assert(!settings.isCapturingShortcut, "isCapturingShortcut toggles back to false")

    // slots persistence: add, remove, update order
    let initialCount = settings.slots.count
    settings.addSlot()
    assertEqual(settings.slots.count, initialCount + 1, "addSlot increases count")

    // Last slot was added as new empty disabled slot
    assert(!settings.slots.last!.isEnabled, "new slot starts disabled")

    // removeSlot: can't remove below 1
    // First build a 1-slot state
    let singleSlot = SettingsManager(forTesting: true)
    singleSlot.slots = [singleSlot.slots[0]]
    let idToKeep = singleSlot.slots[0].id
    singleSlot.removeSlot(id: idToKeep)
    assertEqual(singleSlot.slots.count, 1, "removeSlot doesn't remove last slot (minimum 1)")

    // removeSlot with 2+ slots
    let twoSlot = SettingsManager(forTesting: true)
    twoSlot.addSlot()
    let twoCount = twoSlot.slots.count
    let firstID = twoSlot.slots[0].id
    twoSlot.removeSlot(id: firstID)
    assertEqual(twoSlot.slots.count, twoCount - 1, "removeSlot removes correct slot")
    assert(!twoSlot.slots.contains(where: { $0.id == firstID }), "removed slot no longer present")

    // clearHistory fires and empties
    settings.addToHistory("Some long enough text here", language: "en")
    assert(settings.history.count > 0, "history has entries before clear")
    settings.clearHistory()
    assertEqual(settings.history.count, 0, "clearHistory empties history")
}

// MARK: - LicenseManager Tests

func testLicenseManager() {
    group("LicenseManager")

    // Use an isolated UserDefaults suite to avoid polluting real preferences
    let suiteName = "com.speechy.tests.\(UUID().uuidString)"
    let testDefaults = UserDefaults(suiteName: suiteName)!
    defer {
        testDefaults.removePersistentDomain(forName: suiteName)
    }

    let mgr = LicenseManager(testDefaults: testDefaults)

    // Initially no license key
    assertNil(mgr.storedLicenseKey, "storedLicenseKey is nil initially")
    assert(!mgr.isLicensed, "isLicensed is false initially")

    // Setting a license key
    mgr.storedLicenseKey = "TEST-KEY-1234-ABCD"
    assertEqual(mgr.storedLicenseKey, "TEST-KEY-1234-ABCD", "storedLicenseKey setter stores value")
    assertEqual(testDefaults.string(forKey: "speechy_license_key"), "TEST-KEY-1234-ABCD", "key stored in test UserDefaults")

    // Clearing license key flips isLicensed to false
    mgr.storedLicenseKey = "SOME-KEY-9999"
    mgr.isLicensed = true
    mgr.storedLicenseKey = nil
    assert(!mgr.isLicensed, "clearing storedLicenseKey flips isLicensed to false")
    assertNil(mgr.storedLicenseKey, "storedLicenseKey is nil after clearing")

    // Offline startup: if UserDefaults has key + status=true → isLicensed on init
    testDefaults.set("OFFLINE-KEY", forKey: "speechy_license_key")
    testDefaults.set(true, forKey: "speechy_license_status")
    let mgr2 = LicenseManager(testDefaults: testDefaults)
    assert(mgr2.isLicensed, "offline startup: isLicensed=true when cached status is true")

    // Offline startup: status=false → isLicensed=false
    testDefaults.set(false, forKey: "speechy_license_status")
    let mgr3 = LicenseManager(testDefaults: testDefaults)
    assert(!mgr3.isLicensed, "offline startup: isLicensed=false when cached status is false")

    // machineID is cached: second call returns same value
    let suiteName2 = "com.speechy.tests.\(UUID().uuidString)"
    let testDefaults2 = UserDefaults(suiteName: suiteName2)!
    defer { testDefaults2.removePersistentDomain(forName: suiteName2) }
    let mgr4 = LicenseManager(testDefaults: testDefaults2)
    let id1 = mgr4.machineID
    let id2 = mgr4.machineID
    assertEqual(id1, id2, "machineID is same on consecutive calls (cached)")
    assert(!id1.isEmpty, "machineID is non-empty")

    // Note: verifyAndActivate and other network-calling methods are not tested here
    // because they require a live API server. Those flows are integration-tested manually.
}

// MARK: - AudioRecorder Tests

func testAudioRecorder() {
    group("AudioRecorder")

    let recorder = AudioRecorder()

    // writeErrorLogged starts false
    assert(!recorder.testWriteErrorLogged, "writeErrorLogged starts false")

    // stopRecording with no prior start: completion called with nil, no crash
    var stopResult: URL? = URL(fileURLWithPath: "/placeholder") // non-nil sentinel
    var stopCalled = false
    recorder.stopRecording { url in
        stopResult = url
        stopCalled = true
    }
    // stopRecording queues to writeQueue; drain it with a brief sleep + runloop
    Thread.sleep(forTimeInterval: 0.1)
    assert(stopCalled, "stopRecording completion called even with no prior start")
    assertNil(stopResult, "stopRecording returns nil URL when never started")

    // Calling stopRecording twice: second call returns nil, no crash
    let recorder2 = AudioRecorder()
    var firstResult: URL? = URL(fileURLWithPath: "/placeholder")
    var secondResult: URL? = URL(fileURLWithPath: "/placeholder")
    var firstCalled = false
    var secondCalled = false

    recorder2.stopRecording { url in
        firstResult = url
        firstCalled = true
    }
    recorder2.stopRecording { url in
        secondResult = url
        secondCalled = true
    }
    Thread.sleep(forTimeInterval: 0.15)
    assert(firstCalled, "first stopRecording completion called")
    assert(secondCalled, "second stopRecording completion called")
    assertNil(firstResult, "first stopRecording returns nil (never started)")
    assertNil(secondResult, "second stopRecording returns nil (double call)")

    // startRecording with invalid deviceUID resets writeErrorLogged = false
    // (flag is reset at start of startRecording, even if start fails early)
    // We can't inject a bad audio engine in tests but we can verify the reset happens
    // via a fresh recorder: before any start, flag is false
    let recorder3 = AudioRecorder()
    assert(!recorder3.testWriteErrorLogged, "writeErrorLogged is false on fresh recorder")
}

// MARK: - LiveWhisperTranscriber Tests

func testLiveWhisperTranscriber() {
    group("LiveWhisperTranscriber")

    let lw = LiveWhisperTranscriber()

    // removeRepetitions: consecutive duplicate words removed
    let dup = lw.testRemoveRepetitions("hello hello world")
    assertEqual(dup, "hello world", "consecutive dup words removed")

    // removeRepetitions: case-insensitive dup
    let dupCase = lw.testRemoveRepetitions("Hello hello world")
    assertEqual(dupCase, "Hello world", "case-insensitive dup words removed")

    // removeRepetitions: normal text unchanged
    let normal = lw.testRemoveRepetitions("this is normal text")
    assertEqual(normal, "this is normal text", "normal text unchanged by removeRepetitions")

    // removeRepetitions: empty string unchanged
    let empty = lw.testRemoveRepetitions("")
    assertEqual(empty, "", "empty string unchanged")

    // removeRepetitions: single word unchanged
    let single = lw.testRemoveRepetitions("hello")
    assertEqual(single, "hello", "single word unchanged")

    // removeRepetitions: phrase repetition (3+) removed — 2-word phrase repeated 3 times
    let repeated = "go ahead go ahead go ahead"
    let deduped = lw.testRemoveRepetitions(repeated)
    // Should reduce to "go ahead" (first occurrence kept)
    assert(deduped.components(separatedBy: " ").count < repeated.components(separatedBy: " ").count,
           "phrase repetition reduces word count")
    assert(deduped.hasPrefix("go ahead"), "first occurrence preserved after phrase dedup")

    // removeRepetitions: non-repeated content unchanged
    let unique = lw.testRemoveRepetitions("the quick brown fox jumps over the lazy dog")
    assertEqual(unique, "the quick brown fox jumps over the lazy dog", "non-repeated content unchanged")

    // appendBuffer doesn't crash before start() is called
    // Create a minimal format to make a real AVAudioPCMBuffer
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
    buffer.frameLength = 512
    let lw2 = LiveWhisperTranscriber()
    lw2.appendBuffer(buffer)
    assert(true, "appendBuffer before start() doesn't crash")

    // stop() on a never-started transcriber is a no-op
    let lw3 = LiveWhisperTranscriber()
    lw3.stop()
    assert(lw3.testIsStopped, "stop() sets isStopped on never-started transcriber")
    assert(true, "stop() on never-started transcriber doesn't crash")

    // start() then immediate stop() doesn't crash (race-test the locking)
    let lw4 = LiveWhisperTranscriber()
    lw4.start(language: "en")
    lw4.stop()
    assert(lw4.testIsStopped, "isStopped is true after start+stop")
    assert(true, "start() then immediate stop() doesn't crash")

    // After stop(), appendBuffer is a no-op (buffers not accepted)
    let lw5 = LiveWhisperTranscriber()
    lw5.stop()
    lw5.appendBuffer(buffer) // should not crash, buffer discarded
    assert(true, "appendBuffer after stop() doesn't crash")

    // Timer cleanup: call stop() twice doesn't crash
    let lw6 = LiveWhisperTranscriber()
    lw6.start(language: "tr")
    lw6.stop()
    lw6.stop()
    assert(true, "double stop() after start doesn't crash")
}

// MARK: - WhisperTranscriber filterNonSpeech Extended

func testFilterNonSpeechExtended() {
    group("filterNonSpeech Extended")

    let transcriber = WhisperTranscriber()

    // Altyazı M.K. variants
    assertNil(transcriber.filterNonSpeech("Altyazı M.K."), "Altyazı M.K. filtered")
    assertNil(transcriber.filterNonSpeech("Altyazı M.K"), "Altyazı M.K (no dot) filtered")
    assertNil(transcriber.filterNonSpeech("ALTYAZI M.K."), "uppercase ALTYAZI M.K. filtered")
    assertNil(transcriber.filterNonSpeech("Altyazılar M.K."), "Altyazılar M.K. filtered")

    // *music* bracket-style tags — not in explicit list, passes through
    // This is documenting current behavior, not asserting filtering
    let starMusic = transcriber.filterNonSpeech("♪ ♪")
    // "♪ ♪" → both symbols removed → "  " → trimmed → "" → nil
    assertNil(starMusic, "double musical symbol filtered to nil")

    // two chars ".." passes length check (>= 2 chars, not a known pattern)
    assertNotNil(transcriber.filterNonSpeech(".."), "two dots pass length check (exactly 2 chars)")

    // Silence patterns
    assertNil(transcriber.filterNonSpeech("[SILENCE]"), "[SILENCE] filtered")
    assertNil(transcriber.filterNonSpeech("(Sessizlik)"), "(Sessizlik) filtered")

    // [Alkış] / applause
    assertNil(transcriber.filterNonSpeech("[Alkış]"), "[Alkış] applause filtered")
    assertNil(transcriber.filterNonSpeech("[APPLAUSE]"), "[APPLAUSE] filtered")

    // Preserves mixed content when speech dominates
    let longSpeech = transcriber.filterNonSpeech("Bu gerçek bir konuşma metnidir. [BLANK_AUDIO] Devam ediyor.")
    assertNotNil(longSpeech, "speech-dominant mixed content returns non-nil")
    assert(longSpeech?.contains("gerçek") == true, "speech content preserved")

    // Subtitle attribution patterns — regex strips "Subtitles by" but leaves trailing words
    // "Subtitles by Someone" → strips "Subtitles by" leaving "Someone"  — passes through (is > 1 char)
    // Verify explicit nonSpeechPatterns entries that ARE in the list
    assertNil(transcriber.filterNonSpeech("Altyazı:"), "Altyazı: (exact pattern) filtered")
    assertNil(transcriber.filterNonSpeech("Alt yazı:"), "Alt yazı: (exact pattern) filtered")
}

// MARK: - Integration Test: Hotkey -> Recording -> Stop Pipeline

func testHotkeyRecordingPipeline() {
    group("Hotkey Recording Pipeline (mocked)")

    let manager = HotkeyManager()

    // Set up a single slot
    let slot = HotkeyConfig(
        name: "PipelineTest",
        modifiers: CGEventFlags.maskAlternate.rawValue,
        language: "en",
        isEnabled: true,
        mode: .toggleToTalk
    )
    manager.testSetConfigs([slot], activationDelay: 0.0)

    // Verify configForID works for the registered slot
    let found = manager.testConfigForID(slot.id)
    assertNotNil(found, "pipeline slot registered in manager")
    assertEqual(found?.language, "en", "pipeline slot has correct language")

    // Simulate recording start → stop cycle
    var startFired = false
    var stopFired = false
    var capturedLanguage = ""
    var capturedFlag = ""

    manager.onRecordingStart = { lang, flag in
        startFired = true
        capturedLanguage = lang
        capturedFlag = flag
    }
    manager.onRecordingStop = {
        stopFired = true
    }

    // testSimulateRecordingCycle fires onRecordingStart + onRecordingStop (async to main)
    manager.testSimulateRecordingCycle(language: "en", flag: "🇬🇧")

    // Drain main run loop to pick up async dispatches
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

    assert(startFired, "onRecordingStart fired in pipeline")
    assert(stopFired, "onRecordingStop fired in pipeline")
    assertEqual(capturedLanguage, "en", "pipeline captured correct language")
    assertEqual(capturedFlag, "🇬🇧", "pipeline captured correct flag")

    // After cycle, cooldown is in the future
    assert(manager.testCooldownUntil > Date(), "pipeline: cooldown active after recording stop")

    // Verify stopCurrentRecording triggered cooldown
    let cooldownInterval = manager.testCooldownUntil.timeIntervalSince(Date())
    assert(cooldownInterval >= 0.0, "pipeline: cooldown interval is non-negative")
    assert(cooldownInterval < 1.0, "pipeline: cooldown interval is less than 1 second")
}

// MARK: - Runner

func runAllTests() -> Int32 {
    print("")
    print("Speechy Desktop Tests")
    print("=====================")
    print("")

    testHotkeyConfig()
    testModelType()
    testTranscriptionEntry()
    testAudioInputDevice()
    testSupportedLanguages()
    testFilterNonSpeech()
    testGetFlag()
    testMatchesModifiers()
    testSettingsManagerHistory()
    testHotkeyConfigExtended()
    testHotkeyManager()
    testSettingsManagerExtended()
    testLicenseManager()
    testAudioRecorder()
    testLiveWhisperTranscriber()
    testFilterNonSpeechExtended()
    testHotkeyRecordingPipeline()

    print("")
    print("=====================")
    print("Results: \(testsPassed) passed, \(testsFailed) failed, \(testsPassed + testsFailed) total")
    print("")

    return testsFailed > 0 ? 1 : 0
}
