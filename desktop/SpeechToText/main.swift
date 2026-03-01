import Cocoa
import SwiftUI
import AVFoundation
import CoreAudio
import Carbon.HIToolbox
import Combine
import ServiceManagement

// MARK: - Logger
func log(_ message: String) {
    let logFile = "/tmp/speechy_debug.log"
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(timestamp)] \(message)\n"
    let url = URL(fileURLWithPath: logFile)
    if let handle = try? FileHandle(forWritingTo: url) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        try? handle.close()
    } else {
        try? line.write(toFile: logFile, atomically: true, encoding: .utf8)
    }
}

// MARK: - Data Models
enum HotkeyMode: String, Codable {
    case pushToTalk
    case toggleToTalk
}

struct HotkeyConfig: Equatable, Codable {
    var modifiers: UInt64 = CGEventFlags.maskAlternate.rawValue
    var language: String = "en"
    var isEnabled: Bool = true
    var mode: HotkeyMode = .pushToTalk

    var modifierFlags: CGEventFlags {
        get { CGEventFlags(rawValue: modifiers) }
        set { modifiers = newValue.rawValue }
    }

    var displayName: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        return parts.isEmpty ? "None" : parts.joined()
    }
}

struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let language: String
    let date: Date

    init(text: String, language: String) {
        self.id = UUID()
        self.text = text
        self.language = language
        self.date = Date()
    }
}

enum ModelType: String, Codable, CaseIterable {
    case fast = "base"
    case accurate = "small"
    case precise = "medium"
    case ultimate = "large-v3"

    var displayName: String {
        switch self {
        case .fast: return "Fast (Base)"
        case .accurate: return "Accurate (Small)"
        case .precise: return "Precise (Medium)"
        case .ultimate: return "Ultimate (Large)"
        }
    }

    var description: String {
        switch self {
        case .fast: return "Fastest, for everyday use"
        case .accurate: return "Balanced speed and accuracy"
        case .precise: return "Slowest but most accurate"
        case .ultimate: return "Maximum accuracy, requires more resources"
        }
    }

    var fileName: String {
        return "ggml-\(self.rawValue).bin"
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    var sizeDescription: String {
        switch self {
        case .fast: return "~150 MB"
        case .accurate: return "~500 MB"
        case .precise: return "~1.5 GB"
        case .ultimate: return "~3.1 GB"
        }
    }

    var sizeBytes: Int64 {
        switch self {
        case .fast: return 150_000_000
        case .accurate: return 500_000_000
        case .precise: return 1_500_000_000
        case .ultimate: return 3_100_000_000
        }
    }
}

// MARK: - Audio Input Device
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isDefault: Bool

    static let systemDefault = AudioInputDevice(id: 0, uid: "system_default", name: "System Default", isDefault: true)
}

// MARK: - Audio Device Manager
class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published var availableDevices: [AudioInputDevice] = [AudioInputDevice.systemDefault]

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        refreshDevices()
        installDeviceChangeListener()
    }

    func refreshDevices() {
        var devices = [AudioInputDevice.systemDefault]

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr else {
            log("[Speechy] Failed to get audio devices data size: \(status)")
            DispatchQueue.main.async { self.availableDevices = devices }
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else {
            log("[Speechy] Failed to get audio devices: \(status)")
            DispatchQueue.main.async { self.availableDevices = devices }
            return
        }

        for deviceID in deviceIDs {
            // Check if device has input channels
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var streamSize: UInt32 = 0
            status = AudioObjectGetPropertyDataSize(deviceID, &streamAddress, 0, nil, &streamSize)
            guard status == noErr, streamSize > 0 else { continue }

            let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferListPointer.deallocate() }
            status = AudioObjectGetPropertyData(deviceID, &streamAddress, 0, nil, &streamSize, bufferListPointer)
            guard status == noErr else { continue }

            let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
            let inputChannels = bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
            guard inputChannels > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceNameCFString,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &nameRef)
            let name = nameRef?.takeRetainedValue() as String? ?? "Unknown"

            // Get device UID
            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var uidRef: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            AudioObjectGetPropertyData(deviceID, &uidAddress, 0, nil, &uidSize, &uidRef)
            let uid = uidRef?.takeRetainedValue() as String? ?? ""
            guard !uid.isEmpty else { continue }

            devices.append(AudioInputDevice(id: deviceID, uid: uid, name: name, isDefault: false))
        }

        log("[Speechy] Found \(devices.count - 1) input device(s)")
        DispatchQueue.main.async {
            self.availableDevices = devices
        }
    }

    func installDeviceChangeListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            log("[Speechy] Audio device configuration changed")
            self?.refreshDevices()
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, DispatchQueue.main, block)
    }

    func deviceID(forUID uid: String) -> AudioDeviceID? {
        if uid == "system_default" { return nil }
        guard let device = availableDevices.first(where: { $0.uid == uid }), device.id != 0 else {
            log("[Speechy] Device UID '\(uid)' not found in available devices")
            return nil
        }
        return device.id
    }
}

// MARK: - Model Download Manager
class ModelDownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = ModelDownloadManager()

    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0
    @Published var downloadingModel: ModelType?
    @Published var downloadError: String?

    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession!

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let speechyDir = appSupport.appendingPathComponent("Speechy/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: speechyDir, withIntermediateDirectories: true)
        return speechyDir
    }

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    func modelExists(_ model: ModelType) -> Bool {
        let path = Self.modelsDirectory.appendingPathComponent(model.fileName)
        return FileManager.default.fileExists(atPath: path.path)
    }

    func modelPath(_ model: ModelType) -> String {
        return Self.modelsDirectory.appendingPathComponent(model.fileName).path
    }

    func downloadModel(_ model: ModelType, completion: ((Bool) -> Void)? = nil) {
        guard !isDownloading else { return }

        isDownloading = true
        downloadProgress = 0
        downloadingModel = model
        downloadError = nil

        log("[Speechy] Starting download: \(model.displayName) from \(model.downloadURL)")

        let task = session.downloadTask(with: model.downloadURL)
        self.downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        isDownloading = false
        downloadingModel = nil
        downloadProgress = 0
    }

    // URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let model = downloadingModel else { return }

        let destination = Self.modelsDirectory.appendingPathComponent(model.fileName)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            log("[Speechy] Model downloaded successfully: \(destination.path)")

            DispatchQueue.main.async {
                self.isDownloading = false
                self.downloadingModel = nil
                self.downloadProgress = 1.0
            }
        } catch {
            log("[Speechy] Error saving model: \(error)")
            DispatchQueue.main.async {
                self.downloadError = error.localizedDescription
                self.isDownloading = false
                self.downloadingModel = nil
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.downloadProgress = progress
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            log("[Speechy] Download error: \(error)")
            DispatchQueue.main.async {
                self.downloadError = error.localizedDescription
                self.isDownloading = false
                self.downloadingModel = nil
            }
        }
    }
}

let supportedLanguages: [(code: String, name: String, flag: String)] = [
    ("auto", "Auto Detect", "🌍"),
    ("en", "English", "🇬🇧"),
    ("tr", "Türkçe", "🇹🇷"),
    ("de", "Deutsch", "🇩🇪"),
    ("fr", "Français", "🇫🇷"),
    ("es", "Español", "🇪🇸"),
    ("it", "Italiano", "🇮🇹"),
    ("pt", "Português", "🇵🇹"),
    ("nl", "Nederlands", "🇳🇱"),
    ("pl", "Polski", "🇵🇱"),
    ("ru", "Русский", "🇷🇺"),
    ("uk", "Українська", "🇺🇦"),
    ("ja", "日本語", "🇯🇵"),
    ("zh", "中文", "🇨🇳"),
    ("ko", "한국어", "🇰🇷"),
    ("ar", "العربية", "🇸🇦"),
    ("hi", "हिन्दी", "🇮🇳"),
    ("sv", "Svenska", "🇸🇪"),
    ("da", "Dansk", "🇩🇰"),
    ("no", "Norsk", "🇳🇴"),
    ("fi", "Suomi", "🇫🇮"),
    ("el", "Ελληνικά", "🇬🇷"),
    ("cs", "Čeština", "🇨🇿"),
    ("ro", "Română", "🇷🇴"),
    ("hu", "Magyar", "🇭🇺"),
    ("he", "עברית", "🇮🇱"),
    ("id", "Indonesia", "🇮🇩"),
    ("vi", "Tiếng Việt", "🇻🇳"),
    ("th", "ไทย", "🇹🇭"),
]

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var slot1: HotkeyConfig
    @Published var slot2: HotkeyConfig
    @Published var slot3: HotkeyConfig
    @Published var slot4: HotkeyConfig
    @Published var activationDelay: Double
    @Published var selectedModel: ModelType
    @Published var history: [TranscriptionEntry]
    @Published var selectedInputDeviceUID: String
    @Published var hasCompletedOnboarding: Bool
    @Published var launchAtLogin: Bool {
        didSet {
            setLaunchAtLogin(launchAtLogin)
        }
    }
    @Published var waveMultiplier: Double
    @Published var waveExponent: Double
    @Published var waveDivisor: Double

    var onSettingsChanged: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Load saved settings
        let defaults = UserDefaults.standard

        // Initialize all stored properties first
        if let data = defaults.data(forKey: "slot1"), let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            _slot1 = Published(initialValue: config)
        } else {
            _slot1 = Published(initialValue: HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en"))
        }

        if let data = defaults.data(forKey: "slot2"), let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            _slot2 = Published(initialValue: config)
        } else {
            _slot2 = Published(initialValue: HotkeyConfig(modifiers: CGEventFlags.maskShift.rawValue, language: "tr"))
        }

        if let data = defaults.data(forKey: "slot3"), let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            _slot3 = Published(initialValue: config)
        } else {
            _slot3 = Published(initialValue: HotkeyConfig(modifiers: CGEventFlags.maskControl.rawValue, language: "en", isEnabled: true, mode: .toggleToTalk))
        }

        if let data = defaults.data(forKey: "slot4"), let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            _slot4 = Published(initialValue: config)
        } else {
            _slot4 = Published(initialValue: HotkeyConfig(modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue, language: "tr", isEnabled: true, mode: .toggleToTalk))
        }

        let delay = defaults.double(forKey: "activationDelay")
        _activationDelay = Published(initialValue: delay == 0 ? 0.15 : delay)

        if let modelRaw = defaults.string(forKey: "selectedModel"), let model = ModelType(rawValue: modelRaw) {
            _selectedModel = Published(initialValue: model)
        } else {
            _selectedModel = Published(initialValue: .fast)
        }

        if let data = defaults.data(forKey: "history"), let h = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) {
            _history = Published(initialValue: h)
        } else {
            _history = Published(initialValue: [])
        }

        _selectedInputDeviceUID = Published(initialValue: defaults.string(forKey: "selectedInputDeviceUID") ?? "system_default")

        _hasCompletedOnboarding = Published(initialValue: defaults.bool(forKey: "hasCompletedOnboarding"))

        // Check current launch at login status
        if #available(macOS 13.0, *) {
            _launchAtLogin = Published(initialValue: SMAppService.mainApp.status == .enabled)
        } else {
            _launchAtLogin = Published(initialValue: false)
        }

        let savedMultiplier = defaults.double(forKey: "waveMultiplier")
        _waveMultiplier = Published(initialValue: savedMultiplier == 0 ? 100.0 : savedMultiplier)
        let savedExponent = defaults.double(forKey: "waveExponent")
        _waveExponent = Published(initialValue: savedExponent == 0 ? 0.45 : savedExponent)
        let savedDivisor = defaults.double(forKey: "waveDivisor")
        _waveDivisor = Published(initialValue: savedDivisor == 0 ? 1.0 : savedDivisor)

        // Auto-save and notify on changes
        $slot1.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save(); self?.onSettingsChanged?() }.store(in: &cancellables)
        $slot2.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save(); self?.onSettingsChanged?() }.store(in: &cancellables)
        $slot3.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save(); self?.onSettingsChanged?() }.store(in: &cancellables)
        $slot4.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save(); self?.onSettingsChanged?() }.store(in: &cancellables)
        $activationDelay.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save(); self?.onSettingsChanged?() }.store(in: &cancellables)
        $selectedModel.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save(); self?.onSettingsChanged?() }.store(in: &cancellables)
        $selectedInputDeviceUID.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }.store(in: &cancellables)
        $hasCompletedOnboarding.dropFirst()
            .sink { val in UserDefaults.standard.set(val, forKey: "hasCompletedOnboarding") }.store(in: &cancellables)
        $waveMultiplier.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }.store(in: &cancellables)
        $waveExponent.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }.store(in: &cancellables)
        $waveDivisor.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.save() }.store(in: &cancellables)
    }

    #if TESTING
    init(forTesting: Bool) {
        _slot1 = Published(initialValue: HotkeyConfig(modifiers: CGEventFlags.maskAlternate.rawValue, language: "en"))
        _slot2 = Published(initialValue: HotkeyConfig(modifiers: CGEventFlags.maskShift.rawValue, language: "tr"))
        _slot3 = Published(initialValue: HotkeyConfig(modifiers: CGEventFlags.maskControl.rawValue, language: "en", isEnabled: true, mode: .toggleToTalk))
        _slot4 = Published(initialValue: HotkeyConfig(modifiers: CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue, language: "tr", isEnabled: true, mode: .toggleToTalk))
        _activationDelay = Published(initialValue: 0.15)
        _selectedModel = Published(initialValue: .fast)
        _history = Published(initialValue: [])
        _selectedInputDeviceUID = Published(initialValue: "system_default")
        _hasCompletedOnboarding = Published(initialValue: false)
        _launchAtLogin = Published(initialValue: false)
        _waveMultiplier = Published(initialValue: 100.0)
        _waveExponent = Published(initialValue: 0.45)
        _waveDivisor = Published(initialValue: 1.0)
    }
    #endif

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(slot1) { defaults.set(data, forKey: "slot1") }
        if let data = try? JSONEncoder().encode(slot2) { defaults.set(data, forKey: "slot2") }
        if let data = try? JSONEncoder().encode(slot3) { defaults.set(data, forKey: "slot3") }
        if let data = try? JSONEncoder().encode(slot4) { defaults.set(data, forKey: "slot4") }
        defaults.set(activationDelay, forKey: "activationDelay")
        defaults.set(selectedModel.rawValue, forKey: "selectedModel")
        defaults.set(selectedInputDeviceUID, forKey: "selectedInputDeviceUID")
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "history") }
        defaults.set(waveMultiplier, forKey: "waveMultiplier")
        defaults.set(waveExponent, forKey: "waveExponent")
        defaults.set(waveDivisor, forKey: "waveDivisor")
    }

    func addToHistory(_ text: String, language: String) {
        // Don't add blank audio or very short texts
        if text.contains("[BLANK_AUDIO]") || text.count < 2 { return }
        let entry = TranscriptionEntry(text: text, language: language)
        history.insert(entry, at: 0)
        if history.count > 50 { history = Array(history.prefix(50)) }
        save()
    }

    func clearHistory() {
        history.removeAll()
        save()
    }

    func deleteEntry(_ entry: TranscriptionEntry) {
        history.removeAll { $0.id == entry.id }
        save()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    log("[Speechy] Launch at login enabled")
                } else {
                    try SMAppService.mainApp.unregister()
                    log("[Speechy] Launch at login disabled")
                }
            } catch {
                log("[Speechy] Failed to set launch at login: \(error)")
            }
        }
    }
}

// MARK: - Onboarding View
struct OnboardingView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var currentPage = 0
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Content
            TabView(selection: $currentPage) {
                // Page 1: Welcome
                VStack(spacing: 20) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)

                    Text("Welcome to Speechy")
                        .font(.largeTitle.bold())

                    Text("The fastest way to convert speech to text")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 12) {
                        FeatureRow(icon: "keyboard", text: "Instant recording with hotkeys")
                        FeatureRow(icon: "globe", text: "29 language support")
                        FeatureRow(icon: "bolt.fill", text: "Fast AI-powered transcription")
                    }
                    .padding(.top, 20)
                }
                .tag(0)

                // Page 2: Permissions
                VStack(spacing: 20) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)

                    Text("Permissions Required")
                        .font(.title.bold())

                    VStack(alignment: .leading, spacing: 16) {
                        PermissionCard(
                            icon: "mic.fill",
                            title: "Microphone Access",
                            description: "Microphone access is required to record your voice.",
                            color: .blue
                        )

                        PermissionCard(
                            icon: "hand.raised.fill",
                            title: "Accessibility",
                            description: "Accessibility permission is required to detect hotkeys. Enable Speechy in System Settings > Privacy & Security > Accessibility.",
                            color: .orange
                        )
                    }
                    .padding()
                }
                .tag(1)

                // Page 3: Setup
                VStack(spacing: 20) {
                    Image(systemName: "gearshape.2.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.purple)

                    Text("How to Use")
                        .font(.title.bold())

                    VStack(alignment: .leading, spacing: 16) {
                        HowToCard(step: "1", text: "Click the 🎤 icon in the menu bar")
                        HowToCard(step: "2", text: "Configure your hotkeys")
                        HowToCard(step: "3", text: "Hold the hotkey and speak")
                        HowToCard(step: "4", text: "Release to paste the text!")
                    }
                    .padding()

                    Text("Default: ⌥ Option → English, ⇧ Shift → Turkish")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .tag(2)
            }
            .tabViewStyle(.automatic)
            .frame(height: 400)

            // Navigation
            HStack {
                if currentPage > 0 {
                    Button("Back") {
                        withAnimation { currentPage -= 1 }
                    }
                }

                Spacer()

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(i == currentPage ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                Spacer()

                if currentPage < 2 {
                    Button("Next") {
                        withAnimation { currentPage += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        settings.hasCompletedOnboarding = true
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 500)
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(text)
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct HowToCard: View {
    let step: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(step)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.purple)
                .clipShape(Circle())
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Splash Screen View
struct SplashView: View {
    @State private var progress: Double = 0
    @State private var opacity: Double = 1
    var onComplete: () -> Void

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.15),
                    Color(red: 0.05, green: 0.05, blue: 0.1)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // App icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.blue.opacity(0.5), radius: 20, x: 0, y: 10)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 50, weight: .medium))
                        .foregroundColor(.white)
                }

                // App name
                Text("Speechy")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Text("Speech to Text")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()

                // Progress bar
                VStack(spacing: 12) {
                    ZStack(alignment: .leading) {
                        // Background track
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 200, height: 6)

                        // Progress fill
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 200 * progress, height: 6)
                            .animation(.easeInOut(duration: 0.1), value: progress)
                    }

                    Text("Loading...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .padding(.bottom, 60)
            }
        }
        .opacity(opacity)
        .onAppear {
            // Animate the progress bar over 2 seconds
            Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
                if progress < 1 {
                    progress += 0.01
                } else {
                    timer.invalidate()
                    // Fade out and complete
                    withAnimation(.easeOut(duration: 0.3)) {
                        opacity = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onComplete()
                    }
                }
            }
        }
    }
}

// MARK: - Custom Tab Button
struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    } else {
                        Color.clear
                    }
                }
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.clear : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sidebar Item
struct SidebarItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color.clear
                    }
                }
            )
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main Settings View
struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var selectedTab = 0
    var onQuit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 0) {
                // Logo & App Name
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)
                        Image(systemName: "mic.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.white)
                    }
                    Text("Speechy")
                        .font(.system(size: 15, weight: .bold))
                }
                .padding(.top, 20)
                .padding(.bottom, 24)

                // Navigation Items
                VStack(spacing: 4) {
                    SidebarItem(
                        title: "Settings",
                        icon: "gearshape.fill",
                        isSelected: selectedTab == 0,
                        action: { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = 0 } }
                    )
                    SidebarItem(
                        title: "Advanced",
                        icon: "slider.horizontal.3",
                        isSelected: selectedTab == 1,
                        action: { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = 1 } }
                    )
                    SidebarItem(
                        title: "History",
                        icon: "clock.fill",
                        isSelected: selectedTab == 2,
                        action: { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = 2 } }
                    )
                }
                .padding(.horizontal, 8)

                Spacer()

                // Quit button at bottom
                Button(action: onQuit) {
                    HStack(spacing: 8) {
                        Image(systemName: "power")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Quit")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.red.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 16)
            }
            .frame(width: 140, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(width: 1)

            // Main Content
            VStack(spacing: 0) {
                switch selectedTab {
                case 0:
                    SettingsTab(settings: settings)
                case 1:
                    AdvancedTab(settings: settings)
                default:
                    HistoryTab(settings: settings)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 680)
    }
}

struct SettingsTab: View {
    @ObservedObject var settings: SettingsManager

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section: Hotkeys
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "keyboard", title: "Hotkeys", color: .blue)

                    SlotConfigView(title: "Hotkey 1", config: Binding(
                        get: { settings.slot1 },
                        set: { settings.slot1 = $0 }
                    ), accentColor: .blue)

                    SlotConfigView(title: "Hotkey 2", config: Binding(
                        get: { settings.slot2 },
                        set: { settings.slot2 = $0 }
                    ), accentColor: .green)
                }

                // Section: Toggle Hotkeys
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "keyboard.badge.ellipsis", title: "Toggle Hotkeys (press again to stop)", color: .orange)

                    SlotConfigView(title: "Toggle 1", config: Binding(
                        get: { settings.slot3 },
                        set: { settings.slot3 = $0 }
                    ), accentColor: .orange)

                    SlotConfigView(title: "Toggle 2", config: Binding(
                        get: { settings.slot4 },
                        set: { settings.slot4 = $0 }
                    ), accentColor: .red)
                }
            }
            .padding()
        }
    }
}

struct AdvancedTab: View {
    @ObservedObject var settings: SettingsManager
    @ObservedObject var downloadManager = ModelDownloadManager.shared
    @ObservedObject var deviceManager = AudioDeviceManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section: Model Selection
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "cpu", title: "AI Model", color: .purple)

                    VStack(spacing: 8) {
                        ForEach(ModelType.allCases, id: \.self) { model in
                            ModelOptionRow(
                                model: model,
                                isSelected: settings.selectedModel == model,
                                isDownloaded: downloadManager.modelExists(model),
                                isDownloading: downloadManager.downloadingModel == model,
                                downloadProgress: downloadManager.downloadingModel == model ? downloadManager.downloadProgress : 0,
                                onSelect: {
                                    if downloadManager.modelExists(model) {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            settings.selectedModel = model
                                        }
                                    }
                                },
                                onDownload: {
                                    downloadManager.downloadModel(model)
                                }
                            )
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)

                    if let error = downloadManager.downloadError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                }

                // Section: Activation Delay
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "timer", title: "Activation Delay", color: .orange)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Delay Duration")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(settings.activationDelay * 1000)) ms")
                                .font(.system(.subheadline, design: .rounded).bold())
                                .foregroundColor(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(6)
                        }

                        Slider(value: $settings.activationDelay, in: 0...0.5, step: 0.05)
                            .tint(.orange)

                        Text("Hold the hotkey for this duration to prevent accidental triggers")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }

                // Section: Voice Input
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "mic.fill", title: "Voice Input", color: .cyan)

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "waveform")
                                .font(.system(size: 16))
                                .foregroundColor(.cyan)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Input Device")
                                    .font(.subheadline.weight(.medium))
                                Text("Select which microphone to use for recording")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }

                        Picker("", selection: $settings.selectedInputDeviceUID) {
                            ForEach(deviceManager.availableDevices) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }
                        .labelsHidden()

                        // Warning if saved device is disconnected
                        if settings.selectedInputDeviceUID != "system_default" &&
                           !deviceManager.availableDevices.contains(where: { $0.uid == settings.selectedInputDeviceUID }) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 14))
                                Text("Selected device is disconnected. Recording will use the system default.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .padding(10)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }

                // Section: Waveform Tuning
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "waveform.path.ecg", title: "Waveform Sensitivity", color: .green)

                    VStack(alignment: .leading, spacing: 14) {
                        // Multiplier
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Multiplier")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.0f", settings.waveMultiplier))
                                    .font(.system(.subheadline, design: .rounded).bold())
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.15))
                                    .cornerRadius(6)
                            }
                            Slider(value: $settings.waveMultiplier, in: 100...2000, step: 50)
                                .tint(.green)
                        }

                        // Exponent
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Exponent")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", settings.waveExponent))
                                    .font(.system(.subheadline, design: .rounded).bold())
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.15))
                                    .cornerRadius(6)
                            }
                            Slider(value: $settings.waveExponent, in: 0.05...0.5, step: 0.01)
                                .tint(.green)
                        }

                        // Divisor
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Divisor")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.2f", settings.waveDivisor))
                                    .font(.system(.subheadline, design: .rounded).bold())
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.15))
                                    .cornerRadius(6)
                            }
                            Slider(value: $settings.waveDivisor, in: 0.1...1.0, step: 0.05)
                                .tint(.green)
                        }

                        Text("Adjust waveform visualization sensitivity. Higher multiplier & lower exponent = more sensitive.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }

                // Section: General
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(icon: "gear", title: "General", color: .gray)

                    VStack(spacing: 0) {
                        HStack {
                            Image(systemName: "sunrise.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.yellow)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Launch at Login")
                                    .font(.subheadline.weight(.medium))
                                Text("Start Speechy automatically when you log in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: $settings.launchAtLogin)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                                .labelsHidden()
                        }
                        .padding()
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
    }
}

struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            Text(title)
                .font(.headline)
            Spacer()
        }
    }
}

struct ModelOptionRow: View {
    let model: ModelType
    let isSelected: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    let onSelect: () -> Void
    let onDownload: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Selection indicator
            ZStack {
                Circle()
                    .stroke(isSelected ? Color.purple : Color.secondary.opacity(0.3), lineWidth: 2)
                    .frame(width: 22, height: 22)
                if isSelected {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 14, height: 14)
                }
            }
            .opacity(isDownloaded ? 1 : 0.3)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    if !isDownloaded && !isDownloading {
                        Text(model.sizeDescription)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if isDownloading {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                        .frame(height: 4)
                    Text("\(Int(downloadProgress * 100))% downloading...")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            if isDownloaded {
                Button(action: onSelect) {
                    Text(model == .fast ? "⚡️" : model == .accurate ? "🎯" : "🔬")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            } else if isDownloading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Button(action: onDownload) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected && isDownloaded ? Color.purple.opacity(0.1) : (isHovering ? Color.primary.opacity(0.03) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected && isDownloaded ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isDownloaded {
                onSelect()
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}

struct HistoryTab: View {
    @ObservedObject var settings: SettingsManager
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if settings.history.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No recordings yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Your transcriptions will appear here")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(settings.history) { entry in
                            HistoryRow(entry: entry, onDelete: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    settings.deleteEntry(entry)
                                }
                            })
                        }
                    }
                    .padding()
                }

                // Footer with clear all button
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(settings.history.count) items")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(action: { showClearConfirmation = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.caption)
                                Text("Clear All")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.85))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .alert("Clear History", isPresented: $showClearConfirmation) {
                            Button("Cancel", role: .cancel) { }
                            Button("Delete", role: .destructive) {
                                withAnimation { settings.clearHistory() }
                            }
                        } message: {
                            Text("All recordings will be deleted. This action cannot be undone.")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            }
        }
    }
}

struct HistoryRow: View {
    let entry: TranscriptionEntry
    let onDelete: () -> Void
    @State private var isHovering = false
    @State private var showCopied = false

    var flag: String {
        supportedLanguages.first { $0.code == entry.language }?.flag ?? "🌍"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with flag and time
            HStack {
                Text(flag)
                    .font(.title3)
                Text(entry.date, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()

                // Action buttons
                HStack(spacing: 4) {
                    // Copy button
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                        showCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopied = false
                        }
                    }) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(showCopied ? .green : .secondary)
                            .frame(width: 28, height: 28)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Copy")

                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
                .opacity(isHovering ? 1 : 0.6)
            }

            // Text content
            Text(entry.text)
                .font(.body)
                .lineLimit(3)
                .foregroundColor(.primary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(isHovering ? 0.1 : 0.05), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

struct SlotConfigView: View {
    let title: String
    @Binding var config: HotkeyConfig
    let accentColor: Color

    var currentFlag: String {
        supportedLanguages.first { $0.code == config.language }?.flag ?? "🌍"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                // Toggle switch
                Toggle("", isOn: $config.isEnabled)
                    .toggleStyle(SwitchToggleStyle(tint: accentColor))
                    .labelsHidden()
                    .scaleEffect(0.8)

                HStack(spacing: 8) {
                    Circle()
                        .fill(config.isEnabled ? accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 10, height: 10)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(config.isEnabled ? .primary : .secondary)
                }

                Spacer()

                // Current shortcut display
                HStack(spacing: 6) {
                    Text(config.displayName)
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    Text(currentFlag)

                    Text(config.mode == .pushToTalk ? "Hold" : "Toggle")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(config.mode == .pushToTalk ? .blue : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((config.mode == .pushToTalk ? Color.blue : Color.orange).opacity(0.15))
                        .cornerRadius(4)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(accentColor.opacity(config.isEnabled ? 0.1 : 0.05))
                .cornerRadius(8)
                .opacity(config.isEnabled ? 1 : 0.5)
            }

            // Modifier keys
            HStack(spacing: 6) {
                ModifierToggle(label: "⇧", fullLabel: "Shift", flag: .maskShift, config: $config, accentColor: accentColor)
                ModifierToggle(label: "⌃", fullLabel: "Control", flag: .maskControl, config: $config, accentColor: accentColor)
                ModifierToggle(label: "⌥", fullLabel: "Option", flag: .maskAlternate, config: $config, accentColor: accentColor)
                ModifierToggle(label: "⌘", fullLabel: "Command", flag: .maskCommand, config: $config, accentColor: accentColor)
            }
            .opacity(config.isEnabled ? 1 : 0.4)
            .disabled(!config.isEnabled)

            // Language picker
            HStack(spacing: 10) {
                Image(systemName: "globe")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Picker("", selection: $config.language) {
                    ForEach(supportedLanguages, id: \.code) { lang in
                        Text("\(lang.flag) \(lang.name)").tag(lang.code)
                    }
                }
                .labelsHidden()
                .disabled(!config.isEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
            .opacity(config.isEnabled ? 1 : 0.4)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(config.isEnabled ? 1 : 0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(config.isEnabled ? 0.2 : 0.1), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: config.isEnabled)
    }
}

struct ModifierToggle: View {
    let label: String
    let fullLabel: String
    let flag: CGEventFlags
    @Binding var config: HotkeyConfig
    let accentColor: Color
    @State private var isHovering = false

    var isOn: Bool {
        config.modifierFlags.contains(flag)
    }

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.1)) {
                var flags = config.modifierFlags
                if isOn {
                    flags.remove(flag)
                } else {
                    flags.insert(flag)
                }
                config.modifierFlags = flags
            }
        }) {
            Text(label)
                .font(.system(size: 18, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn ? accentColor : (isHovering ? Color.primary.opacity(0.05) : Color(NSColor.windowBackgroundColor)))
                )
                .foregroundColor(isOn ? .white : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isOn ? accentColor : Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(fullLabel)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Waveform View
class WaveformView: NSView {
    private let barCount = 11
    private let weights: [Float] = [0.3, 0.4, 0.55, 0.7, 0.85, 1.0, 0.85, 0.7, 0.55, 0.4, 0.3]
    private var currentLevel: Float = 0
    private var barLayers: [CAGradientLayer] = []
    private var glowLayers: [CALayer] = []

    private let turquoise = NSColor(red: 0/255, green: 191/255, blue: 165/255, alpha: 1.0)
    private let green = NSColor(red: 76/255, green: 175/255, blue: 80/255, alpha: 1.0)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupBars()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupBars() {
        let barWidth: CGFloat = 4
        let spacing: CGFloat = 2.5
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        let startX = (bounds.width - totalWidth) / 2

        for i in 0..<barCount {
            let x = startX + CGFloat(i) * (barWidth + spacing)

            // Glow layer behind bar
            let glow = CALayer()
            glow.backgroundColor = turquoise.withAlphaComponent(0.4).cgColor
            glow.cornerRadius = 2
            glow.shadowColor = turquoise.cgColor
            glow.shadowRadius = 3
            glow.shadowOpacity = 0.4
            glow.shadowOffset = .zero
            glow.frame = CGRect(x: x, y: (bounds.height - 3) / 2, width: barWidth, height: 3)
            layer?.addSublayer(glow)
            glowLayers.append(glow)

            // Gradient bar
            let bar = CAGradientLayer()
            bar.colors = [turquoise.cgColor, green.cgColor]
            bar.startPoint = CGPoint(x: 0.5, y: 0)
            bar.endPoint = CGPoint(x: 0.5, y: 1)
            bar.cornerRadius = 2
            bar.frame = CGRect(x: x, y: (bounds.height - 3) / 2, width: barWidth, height: 3)
            layer?.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    func updateLevel(_ level: Float) {
        currentLevel = level
        let maxHeight = bounds.height

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        for i in 0..<barCount {
            let div = Float(SettingsManager.shared.waveDivisor)
            let normalized = min(level * weights[i] / div, 1.0)
            let height = max(CGFloat(normalized) * maxHeight, 3)
            let y = (maxHeight - height) / 2

            barLayers[i].frame = CGRect(
                x: barLayers[i].frame.origin.x,
                y: y,
                width: barLayers[i].frame.width,
                height: height
            )

            // Blend gradient based on height ratio
            let ratio = height / maxHeight
            let midColor = NSColor(
                red: turquoise.redComponent * (1 - ratio) + green.redComponent * ratio,
                green: turquoise.greenComponent * (1 - ratio) + green.greenComponent * ratio,
                blue: turquoise.blueComponent * (1 - ratio) + green.blueComponent * ratio,
                alpha: 1.0
            )
            barLayers[i].colors = [turquoise.cgColor, midColor.cgColor]

            glowLayers[i].frame = CGRect(
                x: glowLayers[i].frame.origin.x,
                y: y,
                width: glowLayers[i].frame.width,
                height: height
            )
        }

        CATransaction.commit()
    }

    func reset() {
        currentLevel = 0
        updateLevel(0)
    }
}

// MARK: - Speechy Icon View
class SpeechyIconView: NSView {
    private let circleLayer = CAGradientLayer()
    private let micImageView = NSImageView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private let badgeBg = NSView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupIcon()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupIcon() {
        // Gradient circle background
        circleLayer.frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        circleLayer.cornerRadius = 24
        circleLayer.colors = [
            NSColor(red: 0/255, green: 191/255, blue: 165/255, alpha: 1.0).cgColor,   // #00BFA5
            NSColor(red: 33/255, green: 150/255, blue: 243/255, alpha: 1.0).cgColor    // #2196F3
        ]
        circleLayer.startPoint = CGPoint(x: 0, y: 0)
        circleLayer.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(circleLayer)

        // Mic icon (SF Symbol)
        if let micImage = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
            micImageView.image = micImage.withSymbolConfiguration(config)
            micImageView.contentTintColor = .white
        }
        micImageView.frame = NSRect(x: 12, y: 12, width: 24, height: 24)
        addSubview(micImageView)

        // Badge background (small semi-transparent circle)
        badgeBg.wantsLayer = true
        badgeBg.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        badgeBg.layer?.cornerRadius = 10
        badgeBg.frame = NSRect(x: 28, y: -4, width: 20, height: 20)
        addSubview(badgeBg)

        // Flag badge
        badgeLabel.font = NSFont.systemFont(ofSize: 12)
        badgeLabel.alignment = .center
        badgeLabel.frame = NSRect(x: 28, y: -4, width: 20, height: 20)
        addSubview(badgeLabel)
    }

    func setFlag(_ flag: String) {
        badgeLabel.stringValue = flag
        badgeBg.isHidden = flag.isEmpty
        badgeLabel.isHidden = flag.isEmpty
    }
}

// MARK: - Overlay Window
class OverlayWindow: NSWindow {
    private let speechyIcon: SpeechyIconView
    private var spinner: NSProgressIndicator?
    private let waveformView: WaveformView

    enum State { case hidden, recording, processing }

    init() {
        speechyIcon = SpeechyIconView(frame: NSRect(x: 36, y: 55, width: 48, height: 48))
        waveformView = WaveformView(frame: NSRect(x: 10, y: 15, width: 100, height: 28))

        let windowSize = NSSize(width: 120, height: 150)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let windowOrigin = NSPoint(x: screenFrame.midX - windowSize.width / 2, y: screenFrame.minY + 80)

        super.init(contentRect: NSRect(origin: windowOrigin, size: windowSize),
                   styleMask: .borderless, backing: .buffered, defer: false)

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.ignoresMouseEvents = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 150))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        container.layer?.cornerRadius = 20
        container.addSubview(speechyIcon)
        waveformView.isHidden = true
        container.addSubview(waveformView)
        self.contentView = container
    }

    func updateLevel(_ level: Float) {
        waveformView.updateLevel(level)
    }

    func setState(_ state: State, flag: String? = nil) {
        DispatchQueue.main.async {
            switch state {
            case .hidden:
                self.orderOut(nil)
                self.spinner?.stopAnimation(nil)
                self.spinner?.removeFromSuperview()
                self.spinner = nil
                self.speechyIcon.isHidden = true
                self.waveformView.isHidden = true
                self.waveformView.reset()
            case .recording:
                self.spinner?.removeFromSuperview()
                self.spinner = nil
                self.speechyIcon.setFlag(flag ?? "")
                self.speechyIcon.isHidden = false
                self.waveformView.isHidden = false
                self.orderFront(nil)
            case .processing:
                self.speechyIcon.isHidden = true
                self.waveformView.isHidden = true
                self.waveformView.reset()
                if self.spinner == nil {
                    let s = NSProgressIndicator()
                    s.style = .spinning
                    s.frame = NSRect(x: 40, y: 55, width: 40, height: 40)
                    s.appearance = NSAppearance(named: .darkAqua)
                    self.contentView?.addSubview(s)
                    self.spinner = s
                }
                self.spinner?.startAnimation(nil)
                self.orderFront(nil)
            }
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var hotkeyManager: HotkeyManager!
    var audioRecorder: AudioRecorder!
    var whisperTranscriber: WhisperTranscriber!
    var overlayWindow: OverlayWindow!
    var mainWindow: NSWindow?
    var splashWindow: NSWindow?

    var activeLanguage = "en"
    var activeFlag = "🇬🇧"

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("[Speechy] App starting...")

        // Show splash screen first
        showSplashScreen()
    }

    func showSplashScreen() {
        log("[Speechy] Showing splash screen...")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let splashView = SplashView { [weak self] in
            log("[Speechy] Splash complete, initializing app...")
            DispatchQueue.main.async {
                self?.splashWindow?.orderOut(nil)
                self?.splashWindow = nil
                self?.initializeApp()
            }
        }

        window.contentView = NSHostingView(rootView: splashView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        splashWindow = window

        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func initializeApp() {
        overlayWindow = OverlayWindow()
        audioRecorder = AudioRecorder()
        whisperTranscriber = WhisperTranscriber()
        hotkeyManager = HotkeyManager()

        setupStatusBar()
        setupHotkeyManager()
        requestPermissions()

        SettingsManager.shared.onSettingsChanged = { [weak self] in
            self?.hotkeyManager.updateConfigs()
            self?.whisperTranscriber.updateModel()
        }

        // Show onboarding or settings
        if !SettingsManager.shared.hasCompletedOnboarding {
            showOnboarding()
        }

        // Auto-download base model if no models exist
        checkAndDownloadModel()

        log("[Speechy] App initialized")
    }

    func checkAndDownloadModel() {
        let downloadManager = ModelDownloadManager.shared
        let hasAnyModel = ModelType.allCases.contains { downloadManager.modelExists($0) }

        if !hasAnyModel {
            log("[Speechy] No models found, starting auto-download of base model...")
            downloadManager.downloadModel(.fast)
            // Make sure the selected model is set to fast
            SettingsManager.shared.selectedModel = .fast
        } else {
            // Ensure selected model exists, otherwise switch to an available one
            if !downloadManager.modelExists(SettingsManager.shared.selectedModel) {
                if let availableModel = ModelType.allCases.first(where: { downloadManager.modelExists($0) }) {
                    log("[Speechy] Selected model not found, switching to \(availableModel.displayName)")
                    SettingsManager.shared.selectedModel = availableModel
                }
            }
        }
    }

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Speechy")
            button.action = #selector(statusBarClicked)
            button.target = self
        }
    }

    @objc func statusBarClicked() {
        openSettings()
    }

    func setupHotkeyManager() {
        hotkeyManager.onRecordingStart = { [weak self] lang, flag in
            self?.startRecording(language: lang, flag: flag)
        }
        hotkeyManager.onRecordingStop = { [weak self] in
            self?.stopRecording()
        }
        hotkeyManager.updateConfigs()
    }

    func requestPermissions() {
        hotkeyManager.startListening()

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        log("[Speechy] Mic permission status: \(status.rawValue)")
        if status != .authorized {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                log("[Speechy] Mic permission granted: \(granted)")
            }
        }

        // Listen for open settings notification
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings), name: NSNotification.Name("OpenSettings"), object: nil)
    }

    func showOnboarding() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = OnboardingView { [weak self] in
            window.close()
            self?.openSettings()
        }
        window.contentView = NSHostingView(rootView: view)
        window.title = "Welcome to Speechy"
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
    }

    @objc func openSettings() {
        if mainWindow == nil || !mainWindow!.isVisible {
            mainWindow = nil
            let view = SettingsView { [weak self] in
                self?.quit()
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 680),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: view)
            window.title = "Speechy"
            window.center()
            window.isReleasedWhenClosed = false
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func startRecording(language: String, flag: String) {
        activeLanguage = language
        activeFlag = flag
        log("[Speechy] Recording started - lang: \(language)")
        DispatchQueue.main.async {
            self.overlayWindow.setState(.recording, flag: flag)
        }
        audioRecorder.onAudioLevel = { [weak self] level in
            self?.overlayWindow.updateLevel(level)
        }
        let uid = SettingsManager.shared.selectedInputDeviceUID
        audioRecorder.startRecording(deviceUID: uid == "system_default" ? nil : uid)
    }

    func stopRecording() {
        log("[Speechy] Recording stopped")
        audioRecorder.onAudioLevel = nil
        DispatchQueue.main.async {
            self.overlayWindow.setState(.processing)
        }

        audioRecorder.stopRecording { [weak self] url in
            guard let self = self, let audioURL = url else {
                DispatchQueue.main.async {
                    self?.overlayWindow.setState(.hidden)
                }
                return
            }

            self.whisperTranscriber.transcribe(audioURL: audioURL, language: self.activeLanguage) { result in
                DispatchQueue.main.async {
                    self.overlayWindow.setState(.hidden)
                    if let text = result, !text.isEmpty {
                        SettingsManager.shared.addToHistory(text, language: self.activeLanguage)
                        self.pasteText(text)
                    }
                }
                try? FileManager.default.removeItem(at: audioURL)
            }
        }
    }

    func pasteText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let src = CGEventSource(stateID: .hidSystemState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            down?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            up?.flags = .maskCommand
            up?.post(tap: .cghidEventTap)
        }
    }

    @objc func quit() {
        hotkeyManager.stopListening()
        NSApp.terminate(nil)
    }
}

// MARK: - Hotkey Manager
class HotkeyManager {
    var onRecordingStart: ((String, String) -> Void)?
    var onRecordingStop: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var slot1Config = HotkeyConfig()
    private var slot2Config = HotkeyConfig()
    private var slot3Config = HotkeyConfig()
    private var slot4Config = HotkeyConfig()
    private var activationDelay: Double = 0.15

    private var activeSlot: Int? = nil
    private var delayTimer: Timer?
    private var isRecording = false
    private var isToggleMode = false
    private var toggleStopIgnoreRelease = false

    func updateConfigs() {
        let settings = SettingsManager.shared
        slot1Config = settings.slot1
        slot2Config = settings.slot2
        slot3Config = settings.slot3
        slot4Config = settings.slot4
        activationDelay = settings.activationDelay
        log("[Speechy] Configs updated - slot1: \(slot1Config.displayName), slot2: \(slot2Config.displayName), slot3: \(slot3Config.displayName), slot4: \(slot4Config.displayName)")
    }

    func startListening() {
        stopListening()
        log("[Speechy] Attempting to start hotkey listener...")

        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
            return manager.handleEvent(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("[Speechy] ERROR: Failed to create event tap - need Accessibility permission")
            showAccessibilityPrompt()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("[Speechy] Hotkey listener started successfully")
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it was disabled by timeout
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                log("[Speechy] Event tap re-enabled after disable")
            }
            return Unmanaged.passUnretained(event)
        }

        // Escape key (keyCode 53) stops toggle recording
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 && isRecording && isToggleMode {
                log("[Speechy] Escape pressed, stopping toggle recording")
                isRecording = false
                isToggleMode = false
                activeSlot = nil
                DispatchQueue.main.async { self.onRecordingStop?() }
                return nil // consume the Escape key
            }
            return Unmanaged.passUnretained(event)
        }

        // flagsChanged handling
        let flags = event.flags

        let slot1Match = slot1Config.isEnabled && matchesConfig(flags: flags, config: slot1Config)
        let slot2Match = slot2Config.isEnabled && matchesConfig(flags: flags, config: slot2Config)
        let slot3Match = slot3Config.isEnabled && matchesConfig(flags: flags, config: slot3Config)
        let slot4Match = slot4Config.isEnabled && matchesConfig(flags: flags, config: slot4Config)

        // Toggle mode: if recording, pressing the same modifier again stops it
        if isRecording && isToggleMode {
            let activeConfig: HotkeyConfig
            switch activeSlot {
            case 3: activeConfig = slot3Config
            case 4: activeConfig = slot4Config
            default: activeConfig = slot3Config
            }
            if matchesConfig(flags: flags, config: activeConfig) && !toggleStopIgnoreRelease {
                log("[Speechy] Toggle modifier re-pressed, stopping toggle recording")
                toggleStopIgnoreRelease = true
                isRecording = false
                isToggleMode = false
                activeSlot = nil
                DispatchQueue.main.async { self.onRecordingStop?() }
                return Unmanaged.passUnretained(event)
            }
            if !matchesConfig(flags: flags, config: activeConfig) {
                toggleStopIgnoreRelease = false
            }
            return Unmanaged.passUnretained(event)
        }

        if activeSlot == nil && !isRecording {
            // Check push-to-talk slots first
            if slot1Match {
                activeSlot = 1
                isToggleMode = false
                startDelayTimer(language: slot1Config.language, flag: getFlag(for: slot1Config.language))
            } else if slot2Match {
                activeSlot = 2
                isToggleMode = false
                startDelayTimer(language: slot2Config.language, flag: getFlag(for: slot2Config.language))
            } else if slot3Match {
                activeSlot = 3
                isToggleMode = true
                toggleStopIgnoreRelease = true
                startDelayTimer(language: slot3Config.language, flag: getFlag(for: slot3Config.language))
            } else if slot4Match {
                activeSlot = 4
                isToggleMode = true
                toggleStopIgnoreRelease = true
                startDelayTimer(language: slot4Config.language, flag: getFlag(for: slot4Config.language))
            }
        } else if activeSlot != nil && !isToggleMode {
            // Push-to-talk: stop on modifier release
            let activeConfig: HotkeyConfig
            switch activeSlot {
            case 1: activeConfig = slot1Config
            case 2: activeConfig = slot2Config
            default: activeConfig = slot1Config
            }
            if !matchesConfig(flags: flags, config: activeConfig) {
                if isRecording {
                    isRecording = false
                    activeSlot = nil
                    DispatchQueue.main.async { self.onRecordingStop?() }
                } else {
                    delayTimer?.invalidate()
                    delayTimer = nil
                    activeSlot = nil
                }
            }
        }
        // Toggle mode before recording: ignore modifier releases, let delay timer fire
        // Toggle mode while recording: ignore modifier releases (wait for same modifier re-press)

        return Unmanaged.passUnretained(event)
    }

    func matchesConfig(flags: CGEventFlags, config: HotkeyConfig) -> Bool {
        let required = config.modifierFlags
        if required.rawValue == 0 { return false }

        if required.contains(.maskControl) && !flags.contains(.maskControl) { return false }
        if required.contains(.maskAlternate) && !flags.contains(.maskAlternate) { return false }
        if required.contains(.maskShift) && !flags.contains(.maskShift) { return false }
        if required.contains(.maskCommand) && !flags.contains(.maskCommand) { return false }

        return true
    }

    private func startDelayTimer(language: String, flag: String) {
        delayTimer?.invalidate()
        delayTimer = Timer.scheduledTimer(withTimeInterval: activationDelay, repeats: false) { [weak self] _ in
            guard let self = self, self.activeSlot != nil else { return }
            self.isRecording = true
            if self.isToggleMode {
                self.toggleStopIgnoreRelease = false
            }
            log("[Speechy] Delay passed, starting recording")
            DispatchQueue.main.async {
                self.onRecordingStart?(language, flag)
            }
        }
    }

    func getFlag(for language: String) -> String {
        supportedLanguages.first { $0.code == language }?.flag ?? "🎙️"
    }

    private var permissionCheckTimer: Timer?

    private func showAccessibilityPrompt() {
        DispatchQueue.main.async { [weak self] in
            self?.startPermissionPolling()

            let alert = NSAlert()
            alert.messageText = "Accessibility Permission Required"
            alert.informativeText = "Speechy needs Accessibility permission to detect hotkeys. Please enable it in System Settings > Privacy & Security > Accessibility.\n\nThe app will start automatically once permission is granted."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }

    private func startPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let testMask = 1 << CGEventType.flagsChanged.rawValue
            if let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(testMask),
                callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
                userInfo: nil
            ) {
                CFMachPortInvalidate(tap)
                self.permissionCheckTimer?.invalidate()
                self.permissionCheckTimer = nil
                log("[Speechy] Accessibility permission granted, starting listener...")
                self.startListening()
            }
        }
    }

    func stopListening() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
        delayTimer?.invalidate()
        delayTimer = nil
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }
}

// MARK: - Audio Recorder
class AudioRecorder {
    private var engine: AVAudioEngine?
    private var nativeFile: AVAudioFile?
    private var nativeURL: URL?
    private var finalURL: URL?
    private let writeQueue = DispatchQueue(label: "com.speechy.audiowrite")
    var onAudioLevel: ((Float) -> Void)?

    func startRecording(deviceUID: String? = nil) {
        let engine = AVAudioEngine()

        // Set input device if specified
        if let uid = deviceUID {
            setInputDevice(uid: uid, on: engine)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Record in native format first, convert to whisper format after stopping
        let nativeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_native.caf")
        self.nativeURL = nativeURL
        self.finalURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")

        do {
            nativeFile = try AVAudioFile(forWriting: nativeURL, settings: inputFormat.settings)
        } catch {
            log("[Speechy] Failed to create native audio file: \(error)")
            return
        }

        // Tap captures audio and writes to file off the realtime thread
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            let channelCount = Int(buffer.format.channelCount)

            // Copy buffer data (buffer is only valid during this callback)
            let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)!
            copy.frameLength = buffer.frameLength
            for ch in 0..<channelCount {
                memcpy(copy.floatChannelData![ch], channelData[ch], frameLength * MemoryLayout<Float>.size)
            }

            // Calculate RMS audio level
            var sumOfSquares: Float = 0
            let ptr = channelData[0]
            for i in 0..<frameLength {
                let sample = ptr[i]
                sumOfSquares += sample * sample
            }
            let rms = sqrtf(sumOfSquares / Float(max(frameLength, 1)))
            // Boost audio levels using configurable power curve
            let mult = Float(SettingsManager.shared.waveMultiplier)
            let exp = Float(SettingsManager.shared.waveExponent)
            let boosted = powf(rms * mult, exp)
            let onLevel = self.onAudioLevel
            if onLevel != nil {
                DispatchQueue.main.async { onLevel?(boosted) }
            }

            self.writeQueue.async { [weak self] in
                try? self?.nativeFile?.write(from: copy)
            }
        }

        do {
            try engine.start()
            self.engine = engine
            log("[Speechy] AVAudioEngine started, device: \(deviceUID ?? "system default"), input format: \(inputFormat)")
        } catch {
            log("[Speechy] Failed to start AVAudioEngine: \(error)")
            inputNode.removeTap(onBus: 0)
            nativeFile = nil
        }
    }

    private func setInputDevice(uid: String, on engine: AVAudioEngine) {
        let deviceManager = AudioDeviceManager.shared
        guard let deviceID = deviceManager.deviceID(forUID: uid) else {
            log("[Speechy] Could not resolve device UID '\(uid)', using system default")
            return
        }

        var deviceIDValue = deviceID
        let status = AudioUnitSetProperty(
            engine.inputNode.audioUnit!,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDValue,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            log("[Speechy] Set input device to ID \(deviceID) (UID: \(uid))")
        } else {
            log("[Speechy] Failed to set input device (status: \(status)), using system default")
        }
    }

    func stopRecording(completion: @escaping (URL?) -> Void) {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil

        let nativeFile = self.nativeFile
        let nativeURL = self.nativeURL
        let finalURL = self.finalURL
        self.nativeFile = nil

        guard let nativeURL = nativeURL, let finalURL = finalURL else {
            completion(nil)
            return
        }

        // Wait for pending writes to finish, then convert offline
        writeQueue.async {
            // Keep reference alive until writes complete
            _ = nativeFile

            self.convertToWhisperFormat(sourceURL: nativeURL, destinationURL: finalURL)
            try? FileManager.default.removeItem(at: nativeURL)
            completion(finalURL)
        }
    }

    private func convertToWhisperFormat(sourceURL: URL, destinationURL: URL) {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let sourceFormat = sourceFile.processingFormat

            guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else {
                log("[Speechy] Failed to create output format")
                return
            }
            guard let converter = AVAudioConverter(from: sourceFormat, to: outputFormat) else {
                log("[Speechy] Failed to create converter \(sourceFormat) -> \(outputFormat)")
                return
            }

            let outputSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]
            let outputFile = try AVAudioFile(forWriting: destinationURL, settings: outputSettings)

            let bufferSize: AVAudioFrameCount = 4096
            let ratio = 16000.0 / sourceFormat.sampleRate

            while sourceFile.framePosition < sourceFile.length {
                let remainingFrames = AVAudioFrameCount(sourceFile.length - sourceFile.framePosition)
                let framesToRead = min(bufferSize, remainingFrames)
                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: framesToRead) else { break }
                try sourceFile.read(into: inputBuffer)

                let outputFrames = max(AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio) + 1, 1)
                guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrames) else { break }

                var error: NSError?
                var inputConsumed = false
                converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                    if !inputConsumed {
                        inputConsumed = true
                        outStatus.pointee = .haveData
                        return inputBuffer
                    }
                    outStatus.pointee = .noDataNow
                    return nil
                }

                if let error = error {
                    log("[Speechy] Conversion error: \(error)")
                    break
                }

                if outputBuffer.frameLength > 0 {
                    try outputFile.write(from: outputBuffer)
                }
            }

            log("[Speechy] Audio converted: \(sourceFile.length) frames @ \(sourceFormat.sampleRate)Hz -> 16kHz WAV")
        } catch {
            log("[Speechy] Format conversion failed: \(error)")
        }
    }
}

// MARK: - Whisper Transcriber
class WhisperTranscriber {
    private let whisperPath = "/opt/homebrew/opt/whisper-cpp/bin/whisper-cli"
    private var currentModel: ModelType = .fast

    // Patterns to filter out (music, silence, non-speech)
    private let nonSpeechPatterns: [String] = [
        "[BLANK_AUDIO]",
        "[MUSIC]",
        "[MÜZİK]",
        "(Müzik)",
        "(müzik)",
        "(Music)",
        "(music)",
        "[Müzik]",
        "[müzik]",
        "[Music]",
        "[music]",
        "(Gerilim müziği)",
        "(Hareketli müzik)",
        "[MÜZİK ÇALIYOR]",
        "[...müzik çalıyor...]",
        "(...müzik çalıyor...)",
        "[Sessizlik]",
        "(Sessizlik)",
        "[SILENCE]",
        "(silence)",
        "[Alkış]",
        "(Alkış)",
        "[APPLAUSE]",
        "♪",
        "🎵",
    ]

    init() {
        updateModel()
    }

    func updateModel() {
        currentModel = SettingsManager.shared.selectedModel
        log("[Speechy] Model changed to: \(currentModel.displayName)")
    }

    private func showModelNotFoundNotification(model: ModelType) {
        let alert = NSAlert()
        alert.messageText = "Model Not Downloaded"
        alert.informativeText = "The \(model.displayName) model needs to be downloaded first. Go to Settings to download it."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")

        if alert.runModal() == .alertFirstButtonReturn {
            // Post notification to open settings
            NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
        }
    }

    private var modelPath: String {
        return ModelDownloadManager.shared.modelPath(currentModel)
    }

    func filterNonSpeech(_ text: String) -> String? {
        var filtered = text

        // Remove non-speech patterns
        for pattern in nonSpeechPatterns {
            filtered = filtered.replacingOccurrences(of: pattern, with: "")
        }

        // Remove anything in brackets that looks like a description: [something], (something)
        // But keep actual speech content
        let bracketPattern = #"\[(?:[^\]]*(?:müzik|music|audio|blank|silence|alkış|applause)[^\]]*)\]"#
        let parenPattern = #"\((?:[^\)]*(?:müzik|music|audio|blank|silence|alkış|applause)[^\)]*)\)"#

        if let bracketRegex = try? NSRegularExpression(pattern: bracketPattern, options: .caseInsensitive) {
            filtered = bracketRegex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(filtered.startIndex..., in: filtered), withTemplate: "")
        }

        if let parenRegex = try? NSRegularExpression(pattern: parenPattern, options: .caseInsensitive) {
            filtered = parenRegex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(filtered.startIndex..., in: filtered), withTemplate: "")
        }

        // Clean up whitespace
        filtered = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        filtered = filtered.replacingOccurrences(of: "  ", with: " ")

        // If the result is too short or empty, return nil
        if filtered.isEmpty || filtered.count < 2 {
            return nil
        }

        return filtered
    }

    func transcribe(audioURL: URL, language: String, completion: @escaping (String?) -> Void) {
        // Capture current model at transcription time
        let modelToUse = currentModel

        DispatchQueue.global(qos: .userInitiated).async {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int) ?? 0
            log("[Speechy] Whisper - lang: \(language), model: \(modelToUse.rawValue), audio size: \(fileSize) bytes")

            let modelPath = ModelDownloadManager.shared.modelPath(modelToUse)

            guard ModelDownloadManager.shared.modelExists(modelToUse) else {
                log("[Speechy] ERROR: Model not found at \(modelPath)")
                DispatchQueue.main.async {
                    self.showModelNotFoundNotification(model: modelToUse)
                }
                completion(nil)
                return
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.whisperPath)
            process.arguments = ["-m", modelPath, "-l", language, "-nt", "-np", audioURL.path]

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()

                let exitCode = process.terminationStatus
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                let rawText = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                log("[Speechy] Whisper exit: \(exitCode)")
                log("[Speechy] Raw result: \(rawText.isEmpty ? "(empty)" : String(rawText.prefix(80)))")

                // Filter out non-speech content
                let filteredText = self.filterNonSpeech(rawText)

                if let text = filteredText {
                    log("[Speechy] Filtered result: \(text.prefix(80))")
                    completion(text)
                } else {
                    log("[Speechy] Result filtered out (non-speech)")
                    completion(nil)
                }
            } catch {
                log("[Speechy] Whisper error: \(error)")
                completion(nil)
            }
        }
    }
}

// MARK: - Main
#if TESTING
exit(runAllTests())
#else
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
#endif
