# Unlimited Hotkey Slots Refactor

## Date
2026-03-17

## Summary
Major refactor of the Speechy macOS desktop app to replace the fixed 4-slot hotkey system with a fully dynamic, unlimited hotkey slots system.

## Changes Made

### 1. HotkeyConfig (Data Model)
- Added `id: UUID` field for unique identification (conforms to `Identifiable`)
- Added `name: String` field (user can name slots, e.g., "Turkish", "English Meeting")
- Added `escCancels: Bool = true` - per-slot setting for whether ESC stops toggle recording
- Backward compatible: old configs missing new fields get sensible defaults via Codable

### 2. SettingsManager
- Replaced `slot1`, `slot2`, `slot3`, `slot4` properties with single `@Published var slots: [HotkeyConfig]`
- Default: 2 slots (one push-to-talk English with Alt, one toggle-to-talk Turkish with Ctrl)
- **Migration**: `migrateOldSlots()` reads old `slot1`/`slot2`/`slot3`/`slot4` keys from UserDefaults, converts to array, and cleans up old keys
- Save/load as JSON array under key `"hotkeySlots"`
- Single `$slots` observer replaces 4 individual slot observers
- `addSlot()` method - adds a new disabled slot with defaults
- `removeSlot(id:)` method - removes by UUID (minimum 1 slot enforced)
- Updated `save()` to serialize the slots array instead of individual slots
- Updated `#if TESTING init(forTesting:)` to use `_slots`

### 3. SettingsTab (UI)
- Replaced hardcoded 4 SlotConfigView instances with `ForEach` over `settings.slots`
- "Add Hotkey" button with gradient styling (blue-to-purple)
- No more separate "Push-to-talk" and "Toggle" sections - each slot has its own mode
- Accent colors cycle through: blue, green, orange, purple, red, cyan, pink, yellow, mint, teal, indigo, brown

### 4. SlotConfigView (Per-Slot UI)
- Added editable name text field at top
- Added mode selector as segmented picker (Push-to-Talk / Toggle)
- Added ESC cancel toggle (shown only for toggle-to-talk mode)
- Added delete button (red trash icon, visible only when >1 slot exists)
- All existing functionality preserved (shortcut recorder, language picker, enable toggle)

### 5. HotkeyManager (Event Handling)
- Replaced `slot1Config`, `slot2Config`, `slot3Config`, `slot4Config` with `slotConfigs: [HotkeyConfig]`
- `activeSlot: Int?` changed to `activeSlotID: UUID?` for identification
- `configForID()` helper to look up slot by UUID
- All match logic iterates `slotConfigs` array instead of checking individual slots
- ESC cancellation respects per-slot `escCancels` setting
- `updateConfigs()` reads from `SettingsManager.shared.slots`

### 6. AppDelegate
- No direct references to slot1/2/3/4 existed in AppDelegate (it delegated to HotkeyManager)
- `setupHotkeyManager()` and settings change observer work unchanged with dynamic slots

## Migration Strategy
- On first load, checks for new `"hotkeySlots"` key in UserDefaults
- If not found, checks for old `"slot1"`-`"slot4"` keys and migrates them
- After migration, old keys are removed from UserDefaults
- If neither exists, creates default 2-slot configuration

## Build
```bash
cd desktop/SpeechToText && swiftc main.swift -o SpeechyApp -framework Cocoa -framework AVFoundation -framework Carbon -framework CoreAudio
```
Build succeeds with zero errors.
