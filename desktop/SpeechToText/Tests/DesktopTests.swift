// DesktopTests.swift — Speechy Desktop Test Suite
// Custom assertion-based test harness (no XCTest, compiled with swiftc -DTESTING)

import Foundation
import Carbon.HIToolbox
import Cocoa

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

    // displayName — multiple modifiers
    let multi = HotkeyConfig(modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue, language: "en")
    assertEqual(multi.displayName, "⇧⌃", "displayName multi modifier (Shift+Control)")

    // displayName — no modifiers
    let none = HotkeyConfig(modifiers: 0, language: "en")
    assertEqual(none.displayName, "None", "displayName no modifiers")

    // displayName — all modifiers
    let all = HotkeyConfig(modifiers: CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue, language: "en")
    assertEqual(all.displayName, "⇧⌃⌥⌘", "displayName all modifiers")

    // modifierFlags roundtrip
    var config = HotkeyConfig()
    config.modifierFlags = [.maskShift, .maskCommand]
    assert(config.modifierFlags.contains(.maskShift), "modifierFlags roundtrip contains Shift")
    assert(config.modifierFlags.contains(.maskCommand), "modifierFlags roundtrip contains Command")

    // Equatable
    let a = HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    let b = HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    assert(a == b, "Equatable: identical configs are equal")

    // Codable roundtrip
    let original = HotkeyConfig(modifiers: CGEventFlags.maskShift.rawValue, language: "tr", isEnabled: false, mode: .toggleToTalk)
    let data = try! JSONEncoder().encode(original)
    let decoded = try! JSONDecoder().decode(HotkeyConfig.self, from: data)
    assert(original == decoded, "Codable roundtrip preserves values")
}

func testModelType() {
    group("ModelType")

    // displayName
    assertEqual(ModelType.fast.displayName, "Fast (Base)", "fast displayName")
    assertEqual(ModelType.accurate.displayName, "Accurate (Small)", "accurate displayName")
    assertEqual(ModelType.precise.displayName, "Precise (Medium)", "precise displayName")

    // description
    assert(!ModelType.fast.description.isEmpty, "fast has description")

    // fileName
    assertEqual(ModelType.fast.fileName, "ggml-base.bin", "fast fileName")
    assertEqual(ModelType.accurate.fileName, "ggml-small.bin", "accurate fileName")

    // downloadURL
    assert(ModelType.fast.downloadURL.absoluteString.contains("huggingface.co"), "downloadURL contains huggingface")

    // sizeDescription
    assert(ModelType.fast.sizeDescription.contains("150"), "fast sizeDescription")

    // sizeBytes ordering
    assert(ModelType.fast.sizeBytes < ModelType.accurate.sizeBytes, "fast < accurate sizeBytes")
    assert(ModelType.accurate.sizeBytes < ModelType.precise.sizeBytes, "accurate < precise sizeBytes")

    // CaseIterable count
    assertEqual(ModelType.allCases.count, 3, "CaseIterable count is 3")

    // rawValues
    assertEqual(ModelType.fast.rawValue, "base", "fast rawValue")
    assertEqual(ModelType.accurate.rawValue, "small", "accurate rawValue")
    assertEqual(ModelType.precise.rawValue, "medium", "precise rawValue")
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
}

func testGetFlag() {
    group("getFlag")

    let manager = HotkeyManager()

    assertEqual(manager.getFlag(for: "en"), "🇬🇧", "English flag")
    assertEqual(manager.getFlag(for: "tr"), "🇹🇷", "Turkish flag")
    assertEqual(manager.getFlag(for: "xx"), "🎙️", "unknown language fallback")
    assertEqual(manager.getFlag(for: "auto"), "🌍", "auto detect flag")
}

func testMatchesConfig() {
    group("matchesConfig")

    let manager = HotkeyManager()

    // exact match
    let config = HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en")
    let flags = CGEventFlags.maskAlternate
    assert(manager.matchesConfig(flags: flags, config: config), "exact modifier match")

    // no modifiers configured → always false
    let noModConfig = HotkeyConfig(modifiers: 0, language: "en")
    assert(!manager.matchesConfig(flags: flags, config: noModConfig), "no modifiers configured returns false")

    // superset match (extra modifiers pressed)
    let supersetFlags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskShift.rawValue)
    assert(manager.matchesConfig(flags: supersetFlags, config: config), "superset flags match")

    // missing required modifier
    let shiftOnly = CGEventFlags.maskShift
    assert(!manager.matchesConfig(flags: shiftOnly, config: config), "missing required modifier fails")
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
    testMatchesConfig()
    testSettingsManagerHistory()

    print("")
    print("=====================")
    print("Results: \(testsPassed) passed, \(testsFailed) failed, \(testsPassed + testsFailed) total")
    print("")

    return testsFailed > 0 ? 1 : 0
}
