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

struct HotkeyConfig: Equatable, Codable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var modifiers: UInt64 = CGEventFlags.maskAlternate.rawValue
    var language: String = "en"
    var isEnabled: Bool = true
    var mode: HotkeyMode = .pushToTalk
    var keyCode: Int64 = -1  // -1 = modifier-only mode, >= 0 = specific key required
    var escCancels: Bool = true  // Whether ESC stops this slot's toggle recording

    var modifierFlags: CGEventFlags {
        get { CGEventFlags(rawValue: modifiers) }
        set { modifiers = newValue.rawValue }
    }

    var isModifierOnly: Bool { keyCode == -1 }

    var displayName: String {
        var parts: [String] = []
        let flags = CGEventFlags(rawValue: modifiers)
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        if keyCode >= 0 {
            parts.append(HotkeyConfig.keyName(for: keyCode))
        }
        return parts.isEmpty ? "None" : parts.joined()
    }

    /// Convert a virtual key code to a human-readable display string
    static func keyName(for keyCode: Int64) -> String {
        switch keyCode {
        // Letters
        case 0x00: return "A"
        case 0x01: return "S"
        case 0x02: return "D"
        case 0x03: return "F"
        case 0x04: return "H"
        case 0x05: return "G"
        case 0x06: return "Z"
        case 0x07: return "X"
        case 0x08: return "C"
        case 0x09: return "V"
        case 0x0B: return "B"
        case 0x0C: return "Q"
        case 0x0D: return "W"
        case 0x0E: return "E"
        case 0x0F: return "R"
        case 0x10: return "Y"
        case 0x11: return "T"
        case 0x20: return "U"
        case 0x22: return "I"
        case 0x1F: return "O"  // Also ']' on US keyboard
        case 0x23: return "P"
        case 0x25: return "L"
        case 0x26: return "J"
        case 0x28: return "K"
        case 0x2D: return "N"
        case 0x2E: return "M"
        // Numbers
        case 0x12: return "1"
        case 0x13: return "2"
        case 0x14: return "3"
        case 0x15: return "4"
        case 0x17: return "5"
        case 0x16: return "6"
        case 0x1A: return "7"
        case 0x1C: return "8"
        case 0x19: return "9"
        case 0x1D: return "0"
        case 0x1E: return "]"
        // Special keys
        case 0x24: return "Return"
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x33: return "Delete"
        case 0x35: return "Esc"
        case 0x75: return "Fwd Del"
        case 0x72: return "Help"
        case 0x73: return "Home"
        case 0x77: return "End"
        case 0x74: return "Page Up"
        case 0x79: return "Page Down"
        // Arrow keys
        case 0x7B: return "Left"
        case 0x7C: return "Right"
        case 0x7D: return "Down"
        case 0x7E: return "Up"
        // F-keys
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        case 0x69: return "F13"
        case 0x6B: return "F14"
        case 0x71: return "F15"
        // Punctuation / other
        case 0x18: return "="
        case 0x1B: return "-"
        case 0x21: return "["
        case 0x27: return "'"
        case 0x29: return ";"
        case 0x2A: return "\\"
        case 0x2B: return ","
        case 0x2C: return "/"
        case 0x2F: return "."
        case 0x32: return "`"
        default: return "Key\(keyCode)"
        }
    }
}

struct TranscriptionEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let language: String
    let date: Date
    var audioPath: String?

    init(text: String, language: String, audioPath: String? = nil) {
        self.id = UUID()
        self.text = text
        self.language = language
        self.date = Date()
        self.audioPath = audioPath
    }

    var audioURL: URL? {
        guard let path = audioPath else { return nil }
        return URL(fileURLWithPath: path)
    }

    var hasAudio: Bool {
        guard let path = audioPath else { return false }
        return FileManager.default.fileExists(atPath: path)
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

// MARK: - License Manager
class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    private let baseURL = "https://speechy.frkn.com.tr"
    private let licenseKeyKey = "speechy_license_key"
    private let licenseStatusKey = "speechy_license_status"
    private let lastVerifiedKey = "speechy_last_verified"

    @Published var isLicensed = false
    @Published var licenseStatus: String = ""
    @Published var licenseType: String = ""
    @Published var expiresAt: String = ""

    var storedLicenseKey: String? {
        get { UserDefaults.standard.string(forKey: licenseKeyKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: licenseKeyKey)
            if newValue == nil {
                isLicensed = false
                licenseStatus = ""
            }
        }
    }

    var machineID: String {
        // Use hardware UUID as unique machine identifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        // Extract IOPlatformUUID
        if let range = output.range(of: "IOPlatformUUID\" = \"") {
            let start = range.upperBound
            if let end = output[start...].firstIndex(of: "\"") {
                return String(output[start..<end])
            }
        }
        // Fallback: generate and persist a UUID
        if let saved = UserDefaults.standard.string(forKey: "speechy_machine_id") { return saved }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: "speechy_machine_id")
        return newID
    }

    var machineName: String {
        Host.current().localizedName ?? "Mac"
    }

    init() {
        // Check cached license status (for offline startup)
        if storedLicenseKey != nil {
            isLicensed = UserDefaults.standard.bool(forKey: licenseStatusKey)
        }
    }

    func verifyAndActivate(licenseKey: String, completion: @escaping (Bool, String) -> Void) {
        // First verify the license
        let verifyURL = URL(string: "\(baseURL)/api/license/verify")!
        var verifyRequest = URLRequest(url: verifyURL)
        verifyRequest.httpMethod = "POST"
        verifyRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        verifyRequest.httpBody = try? JSONSerialization.data(withJSONObject: ["license_key": licenseKey])
        verifyRequest.timeoutInterval = 15

        URLSession.shared.dataTask(with: verifyRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                log("[Speechy] License verify error: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false, "Connection failed. Check your internet.") }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(false, "Invalid server response.") }
                return
            }

            // Check for error
            if let errorMsg = json["error"] as? String {
                DispatchQueue.main.async { completion(false, errorMsg) }
                return
            }

            guard let valid = json["valid"] as? Bool, valid,
                  let license = json["license"] as? [String: Any],
                  let status = license["status"] as? String, status == "active" else {
                let license = json["license"] as? [String: Any]
                let status = license?["status"] as? String ?? "invalid"
                DispatchQueue.main.async { completion(false, "License is \(status).") }
                return
            }

            // License is valid, now activate on this device
            self.activate(licenseKey: licenseKey) { activated, message in
                if activated {
                    self.storedLicenseKey = licenseKey
                    UserDefaults.standard.set(true, forKey: self.licenseStatusKey)
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastVerifiedKey)
                    DispatchQueue.main.async {
                        self.isLicensed = true
                        self.licenseStatus = status
                        self.licenseType = license["license_type"] as? String ?? ""
                        self.expiresAt = license["expires_at"] as? String ?? ""
                        completion(true, message)
                    }
                } else {
                    DispatchQueue.main.async { completion(false, message) }
                }
            }
        }.resume()
    }

    private func activate(licenseKey: String, completion: @escaping (Bool, String) -> Void) {
        let activateURL = URL(string: "\(baseURL)/api/license/activate")!
        var request = URLRequest(url: activateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: String] = [
            "license_key": licenseKey,
            "machine_id": machineID,
            "machine_label": machineName,
            "app_platform": "macos",
            "app_version": "1.0.0",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                log("[Speechy] License activate error: \(error.localizedDescription)")
                completion(false, "Activation failed. Check your internet.")
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(false, "Invalid server response.")
                return
            }

            if let errorMsg = json["error"] as? String {
                completion(false, errorMsg)
                return
            }

            if let activated = json["activated"] as? Bool, activated {
                let msg = json["message"] as? String ?? "Activated"
                log("[Speechy] License activated: \(msg)")
                completion(true, msg)
            } else {
                completion(false, "Activation failed.")
            }
        }.resume()
    }

    func verifyInBackground() {
        guard let key = storedLicenseKey else { return }

        // Only re-verify every 24 hours
        let lastVerified = UserDefaults.standard.double(forKey: lastVerifiedKey)
        if Date().timeIntervalSince1970 - lastVerified < 86400 { return }

        let verifyURL = URL(string: "\(baseURL)/api/license/verify")!
        var request = URLRequest(url: verifyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["license_key": key])
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let valid = json["valid"] as? Bool else { return }

            DispatchQueue.main.async {
                if valid {
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: self.lastVerifiedKey)
                    UserDefaults.standard.set(true, forKey: self.licenseStatusKey)
                    if let license = json["license"] as? [String: Any] {
                        self.licenseType = license["license_type"] as? String ?? ""
                        self.expiresAt = license["expires_at"] as? String ?? ""
                    }
                } else {
                    log("[Speechy] License no longer valid, revoking")
                    self.isLicensed = false
                    UserDefaults.standard.set(false, forKey: self.licenseStatusKey)
                }
            }
        }.resume()
    }

    func deactivateAndClear() {
        guard let key = storedLicenseKey else { return }

        let deactivateURL = URL(string: "\(baseURL)/api/license/deactivate")!
        var request = URLRequest(url: deactivateURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "license_key": key,
            "machine_id": machineID,
        ])
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, _, _ in
            log("[Speechy] License deactivated on server")
        }.resume()

        storedLicenseKey = nil
        UserDefaults.standard.set(false, forKey: licenseStatusKey)
        isLicensed = false
    }
}

// MARK: - License View
struct LicenseView: View {
    @ObservedObject var licenseManager = LicenseManager.shared
    @State private var licenseKey = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    var onActivated: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                Image(systemName: "mic.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 16)

            Text("Speechy")
                .font(.system(size: 28, weight: .bold))
                .padding(.bottom, 4)

            Text("Enter your license key to get started")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .padding(.bottom, 32)

            // License key input
            VStack(alignment: .leading, spacing: 8) {
                Text("License Key")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                TextField("Paste your license key here", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14, design: .monospaced))
                    .disabled(isLoading)
                    .onSubmit { activateLicense() }
            }
            .frame(width: 340)
            .padding(.bottom, 16)

            // Error message
            if !errorMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .padding(.bottom, 12)
            }

            // Success message
            if showSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                    Text("License activated successfully!")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }
                .padding(.bottom, 12)
            }

            // Activate button
            Button(action: activateLicense) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.8)
                    }
                    Text(isLoading ? "Verifying..." : "Activate License")
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(width: 340, height: 40)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            .opacity(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)

            Spacer()

            // Footer
            VStack(spacing: 4) {
                Text("Don't have a license?")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Button("Get a free trial at speechy.frkn.com.tr") {
                    NSWorkspace.shared.open(URL(string: "https://speechy.frkn.com.tr")!)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.blue)
            }
            .padding(.bottom, 24)
        }
        .frame(width: 440, height: 480)
    }

    private func activateLicense() {
        let key = licenseKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }

        isLoading = true
        errorMessage = ""
        showSuccess = false

        licenseManager.verifyAndActivate(licenseKey: key) { success, message in
            isLoading = false
            if success {
                showSuccess = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onActivated()
                }
            } else {
                errorMessage = message
            }
        }
    }
}

// MARK: - Permission Checker
func checkPermissions() -> (accessibility: Bool, microphone: Bool) {
    let accessibility = AXIsProcessTrusted()
    let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    let microphone = (micStatus == .authorized)
    return (accessibility: accessibility, microphone: microphone)
}

func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    if status == .notDetermined {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    } else {
        completion(status == .authorized)
    }
}

// MARK: - Permission Check View
struct PermissionCheckView: View {
    @State private var accessibilityGranted: Bool
    @State private var microphoneGranted: Bool
    var onAllGranted: () -> Void

    init(accessibility: Bool, microphone: Bool, onAllGranted: @escaping () -> Void) {
        _accessibilityGranted = State(initialValue: accessibility)
        _microphoneGranted = State(initialValue: microphone)
        self.onAllGranted = onAllGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 32)

            // Header icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange, Color.red]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.white)
            }
            .padding(.bottom, 16)

            Text("Permissions Required")
                .font(.system(size: 24, weight: .bold))
                .padding(.bottom, 6)

            Text("Speechy needs the following permissions to work properly.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 28)

            // Permission rows
            VStack(spacing: 12) {
                // Accessibility
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(accessibilityGranted ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(accessibilityGranted ? .green : .red)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Accessibility")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Required to detect global hotkeys for recording.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    if accessibilityGranted {
                        Text("Granted")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                    } else {
                        Text("Missing")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                // Microphone
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(microphoneGranted ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: microphoneGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(microphoneGranted ? .green : .red)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Microphone")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Required to record your voice for transcription.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    if microphoneGranted {
                        Text("Granted")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(6)
                    } else {
                        Text("Missing")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)

            // Buttons
            VStack(spacing: 10) {
                if !accessibilityGranted || !microphoneGranted {
                    Button(action: {
                        if !accessibilityGranted {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        } else if !microphoneGranted {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "gear")
                                .font(.system(size: 13, weight: .medium))
                            Text("Open System Settings")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(width: 300, height: 40)
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    // If mic is notDetermined, request it first
                    requestMicrophonePermission { granted in
                        microphoneGranted = granted
                        accessibilityGranted = AXIsProcessTrusted()
                        if accessibilityGranted && microphoneGranted {
                            onAllGranted()
                        }
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .medium))
                        Text("Check Again")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(width: 300, height: 40)
                    .background(Color(NSColor.controlBackgroundColor))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                if accessibilityGranted && microphoneGranted {
                    Button(action: onAllGranted) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13, weight: .medium))
                            Text("Continue")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .frame(width: 300, height: 40)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer().frame(height: 24)
        }
        .frame(width: 440, height: 520)
        .onAppear {
            // Auto-request microphone permission if not yet asked
            requestMicrophonePermission { granted in
                microphoneGranted = granted
            }
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

// MARK: - Media Control Manager
class MediaControlManager {
    static let shared = MediaControlManager()

    /// Whether we were the ones who paused media (so we only resume if we paused it)
    private var didPauseMedia = false

    /// Which player we paused (so we can target resume correctly)
    private var pausedPlayer: String?

    /// Check if a specific media player is currently playing
    private func isPlayerPlaying(_ appName: String) -> Bool {
        // First check if the app is running
        let checkRunning = """
        tell application "System Events"
            return (name of processes) contains "\(appName)"
        end tell
        """
        guard let runScript = NSAppleScript(source: checkRunning) else { return false }
        var error: NSDictionary?
        let runResult = runScript.executeAndReturnError(&error)
        if error != nil || !runResult.booleanValue { return false }

        // App is running, check player state
        let checkState = """
        tell application "\(appName)"
            return player state as string
        end tell
        """
        guard let stateScript = NSAppleScript(source: checkState) else { return false }
        var stateError: NSDictionary?
        let stateResult = stateScript.executeAndReturnError(&stateError)
        if stateError != nil { return false }

        let state = stateResult.stringValue ?? ""
        return state == "playing" || state == "kPSP"
    }

    /// Check if any media player is currently playing
    private func isMediaPlaying() -> Bool {
        let players = ["Spotify", "Music"]
        for player in players {
            if isPlayerPlaying(player) {
                log("[Speechy] MediaControl: \(player) is currently playing")
                pausedPlayer = player
                return true
            }
        }
        pausedPlayer = nil
        return false
    }

    /// Pause a specific media player via AppleScript
    private func pausePlayer(_ appName: String) {
        let script = """
        tell application "\(appName)" to pause
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                log("[Speechy] MediaControl: Failed to pause \(appName): \(error)")
            } else {
                log("[Speechy] MediaControl: Paused \(appName)")
            }
        }
    }

    /// Resume a specific media player via AppleScript
    private func resumePlayer(_ appName: String) {
        let script = """
        tell application "\(appName)" to play
        """
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                log("[Speechy] MediaControl: Failed to resume \(appName): \(error)")
            } else {
                log("[Speechy] MediaControl: Resumed \(appName)")
            }
        }
    }

    /// Called when recording starts. Pauses media if playing.
    func pauseMediaIfNeeded() {
        guard SettingsManager.shared.pauseMediaDuringRecording else {
            log("[Speechy] MediaControl: Feature disabled, skipping")
            return
        }

        didPauseMedia = false
        pausedPlayer = nil

        if isMediaPlaying(), let player = pausedPlayer {
            log("[Speechy] MediaControl: \(player) is playing, pausing...")
            pausePlayer(player)
            didPauseMedia = true
            log("[Speechy] MediaControl: \(player) paused successfully")
        } else {
            log("[Speechy] MediaControl: No media playing, nothing to pause")
        }
    }

    /// Called when recording/transcription ends. Resumes media if we paused it.
    func resumeMediaIfNeeded() {
        guard SettingsManager.shared.pauseMediaDuringRecording else { return }

        if didPauseMedia, let player = pausedPlayer {
            log("[Speechy] MediaControl: Resuming \(player)...")
            resumePlayer(player)
            didPauseMedia = false
            pausedPlayer = nil
            log("[Speechy] MediaControl: \(player) resumed")
        } else {
            log("[Speechy] MediaControl: We didn't pause media, not resuming")
        }
    }

    /// Reset state (e.g., if recording is cancelled)
    func reset() {
        didPauseMedia = false
        pausedPlayer = nil
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

    @Published var slots: [HotkeyConfig]
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
    @Published var pauseMediaDuringRecording: Bool
    @Published var saveAudioRecordings: Bool

    /// When true, hotkey triggers are suppressed (user is recording a new shortcut in settings)
    var isCapturingShortcut = false

    var onSettingsChanged: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()

    /// Default slots for new installs
    static func defaultSlots() -> [HotkeyConfig] {
        return [
            HotkeyConfig(name: "English", modifiers: CGEventFlags.maskAlternate.rawValue, language: "en", isEnabled: true, mode: .pushToTalk),
            HotkeyConfig(name: "Turkish Toggle", modifiers: CGEventFlags.maskControl.rawValue, language: "tr", isEnabled: true, mode: .toggleToTalk),
        ]
    }

    /// Migrate old slot1/2/3/4 data from UserDefaults to new array format
    private static func migrateOldSlots(defaults: UserDefaults) -> [HotkeyConfig]? {
        // Check if any old slot keys exist
        let hasOldSlots = defaults.data(forKey: "slot1") != nil ||
                          defaults.data(forKey: "slot2") != nil ||
                          defaults.data(forKey: "slot3") != nil ||
                          defaults.data(forKey: "slot4") != nil

        guard hasOldSlots else { return nil }

        var migrated: [HotkeyConfig] = []

        let oldKeys = ["slot1", "slot2", "slot3", "slot4"]
        let defaultNames = ["Hotkey 1", "Hotkey 2", "Toggle 1", "Toggle 2"]

        for (i, key) in oldKeys.enumerated() {
            if let data = defaults.data(forKey: key),
               var config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
                // Ensure migrated configs have a valid UUID and name
                if config.name.isEmpty {
                    config.name = defaultNames[i]
                }
                migrated.append(config)
            }
        }

        // Clean up old keys after migration
        for key in oldKeys {
            defaults.removeObject(forKey: key)
        }

        log("[Speechy] Migrated \(migrated.count) old slots to new array format")
        return migrated.isEmpty ? nil : migrated
    }

    init() {
        // Load saved settings
        let defaults = UserDefaults.standard

        // Load slots: try new format first, then migrate, then defaults
        if let data = defaults.data(forKey: "hotkeySlots"),
           let loadedSlots = try? JSONDecoder().decode([HotkeyConfig].self, from: data),
           !loadedSlots.isEmpty {
            _slots = Published(initialValue: loadedSlots)
        } else if let migratedSlots = SettingsManager.migrateOldSlots(defaults: defaults) {
            _slots = Published(initialValue: migratedSlots)
        } else {
            _slots = Published(initialValue: SettingsManager.defaultSlots())
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

        // Default ON if key has never been set
        if defaults.object(forKey: "pauseMediaDuringRecording") == nil {
            _pauseMediaDuringRecording = Published(initialValue: true)
        } else {
            _pauseMediaDuringRecording = Published(initialValue: defaults.bool(forKey: "pauseMediaDuringRecording"))
        }

        // Default OFF — user must opt-in to save audio recordings
        _saveAudioRecordings = Published(initialValue: defaults.bool(forKey: "saveAudioRecordings"))

        // Auto-save and notify on changes
        $slots.dropFirst().debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
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
        $pauseMediaDuringRecording.dropFirst()
            .sink { [weak self] _ in self?.save() }.store(in: &cancellables)
        $saveAudioRecordings.dropFirst()
            .sink { [weak self] _ in self?.save() }.store(in: &cancellables)
    }

    #if TESTING
    init(forTesting: Bool) {
        _slots = Published(initialValue: SettingsManager.defaultSlots())
        _activationDelay = Published(initialValue: 0.15)
        _selectedModel = Published(initialValue: .fast)
        _history = Published(initialValue: [])
        _selectedInputDeviceUID = Published(initialValue: "system_default")
        _hasCompletedOnboarding = Published(initialValue: false)
        _launchAtLogin = Published(initialValue: false)
        _waveMultiplier = Published(initialValue: 100.0)
        _waveExponent = Published(initialValue: 0.45)
        _waveDivisor = Published(initialValue: 1.0)
        _pauseMediaDuringRecording = Published(initialValue: true)
        _saveAudioRecordings = Published(initialValue: false)
    }
    #endif

    /// Add a new empty slot with defaults
    func addSlot() {
        let newSlot = HotkeyConfig(
            name: "Hotkey \(slots.count + 1)",
            modifiers: 0,
            language: "en",
            isEnabled: false,
            mode: .pushToTalk
        )
        slots.append(newSlot)
    }

    /// Remove a slot by ID (minimum 1 slot)
    func removeSlot(id: UUID) {
        guard slots.count > 1 else { return }
        slots.removeAll { $0.id == id }
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(slots) { defaults.set(data, forKey: "hotkeySlots") }
        defaults.set(activationDelay, forKey: "activationDelay")
        defaults.set(selectedModel.rawValue, forKey: "selectedModel")
        defaults.set(selectedInputDeviceUID, forKey: "selectedInputDeviceUID")
        if let data = try? JSONEncoder().encode(history) { defaults.set(data, forKey: "history") }
        defaults.set(waveMultiplier, forKey: "waveMultiplier")
        defaults.set(waveExponent, forKey: "waveExponent")
        defaults.set(waveDivisor, forKey: "waveDivisor")
        defaults.set(pauseMediaDuringRecording, forKey: "pauseMediaDuringRecording")
        defaults.set(saveAudioRecordings, forKey: "saveAudioRecordings")
    }

    /// Directory for saved audio recordings
    var recordingsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Speechy/Recordings")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func addToHistory(_ text: String, language: String, audioPath: String? = nil) {
        // Don't add blank audio or very short texts
        if text.contains("[BLANK_AUDIO]") || text.count < 2 { return }

        let entry = TranscriptionEntry(text: text, language: language, audioPath: audioPath)
        history.insert(entry, at: 0)
        if history.count > 50 {
            // Delete audio files of removed entries
            let removed = Array(history.suffix(from: 50))
            for old in removed {
                if let path = old.audioPath {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
            history = Array(history.prefix(50))
        }
        save()
    }

    func clearHistory() {
        // Delete all associated audio files
        for entry in history {
            if let path = entry.audioPath {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        history.removeAll()
        save()
    }

    func deleteEntry(_ entry: TranscriptionEntry) {
        // Delete associated audio file
        if let path = entry.audioPath {
            try? FileManager.default.removeItem(atPath: path)
        }
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
                    SidebarItem(
                        title: "License",
                        icon: "key.fill",
                        isSelected: selectedTab == 3,
                        action: { withAnimation(.easeInOut(duration: 0.15)) { selectedTab = 3 } }
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
            .frame(width: 168, alignment: .leading)
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
                case 2:
                    HistoryTab(settings: settings)
                default:
                    LicenseTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 672, height: 816)
    }
}

struct SettingsTab: View {
    @ObservedObject var settings: SettingsManager

    private let accentColors: [Color] = [.blue, .green, .orange, .purple, .red, .cyan, .pink, .yellow, .mint, .teal, .indigo, .brown]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section: Hotkeys
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader(icon: "keyboard", title: "Hotkeys", color: .blue)
                        Spacer()
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                settings.addSlot()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Add Hotkey")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.blue, Color.purple]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(Array(settings.slots.enumerated()), id: \.element.id) { index, slot in
                        let color = accentColors[index % accentColors.count]
                        SlotConfigView(
                            title: "Hotkey \(index + 1)",
                            config: $settings.slots[index],
                            accentColor: color,
                            canDelete: settings.slots.count > 1,
                            onDelete: {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    settings.removeSlot(id: slot.id)
                                }
                            }
                        )
                    }
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

                        Divider()
                            .padding(.horizontal)

                        HStack {
                            Image(systemName: "pause.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.pink)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Pause Media During Recording")
                                    .font(.subheadline.weight(.medium))
                                Text("Automatically pause music when recording and resume when done")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: $settings.pauseMediaDuringRecording)
                                .toggleStyle(SwitchToggleStyle(tint: .pink))
                                .labelsHidden()
                        }
                        .padding()

                        Divider()

                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.cyan)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save Audio Recordings")
                                    .font(.subheadline.weight(.medium))
                                Text("Keep audio files of your recordings in History. Play them back or find them in Finder.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: $settings.saveAudioRecordings)
                                .toggleStyle(SwitchToggleStyle(tint: .cyan))
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
    @State private var isPlaying = false
    @State private var audioPlayer: AVAudioPlayer?

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
                    // Play audio button (only if audio exists)
                    if entry.hasAudio {
                        Button(action: togglePlayback) {
                            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                                .font(.system(size: 11))
                                .foregroundColor(isPlaying ? .orange : .blue)
                                .frame(width: 28, height: 28)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help(isPlaying ? "Stop" : "Play Audio")

                        // Open in Finder button
                        Button(action: {
                            if let url = entry.audioURL {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        }) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .help("Show in Finder")
                    }

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

            // Audio file info
            if entry.hasAudio {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                    Text("Audio saved")
                        .font(.system(size: 10))
                }
                .foregroundColor(.blue.opacity(0.7))
            }
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
        .onDisappear {
            audioPlayer?.stop()
            isPlaying = false
        }
    }

    private func togglePlayback() {
        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
            return
        }

        guard let url = entry.audioURL else { return }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            isPlaying = true

            // Auto-stop when done
            let duration = audioPlayer?.duration ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
                self.isPlaying = false
            }
        } catch {
            log("[Speechy] Failed to play audio: \(error.localizedDescription)")
        }
    }
}

struct SlotConfigView: View {
    let title: String
    @Binding var config: HotkeyConfig
    let accentColor: Color
    var canDelete: Bool = false
    var onDelete: (() -> Void)? = nil
    @State private var isRecordingKey = false

    var currentFlag: String {
        supportedLanguages.first { $0.code == config.language }?.flag ?? "🌍"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with name, enable toggle, and delete button
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

                // Delete button
                if canDelete {
                    Button(action: { onDelete?() }) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                            .frame(width: 28, height: 28)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Remove hotkey")
                }
            }

            // Mode selector (Push-to-Talk / Toggle)
            HStack(spacing: 10) {
                Image(systemName: "hand.tap")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Text("Mode")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $config.mode) {
                    Text("Push-to-Talk").tag(HotkeyMode.pushToTalk)
                    Text("Toggle").tag(HotkeyMode.toggleToTalk)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .disabled(!config.isEnabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
            .opacity(config.isEnabled ? 1 : 0.4)

            // ESC cancel toggle (only for toggle-to-talk mode)
            if config.mode == .toggleToTalk {
                HStack(spacing: 10) {
                    Image(systemName: "escape")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ESC Stops Recording")
                            .font(.subheadline)
                        Text("Press Escape to cancel toggle recording")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $config.escCancels)
                        .toggleStyle(SwitchToggleStyle(tint: accentColor))
                        .labelsHidden()
                        .scaleEffect(0.8)
                        .disabled(!config.isEnabled)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
                .opacity(config.isEnabled ? 1 : 0.4)
            }

            // Shortcut recorder — captures any key combination
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                Text("Shortcut")
                    .font(.subheadline)

                Spacer()

                if isRecordingKey {
                    Text("Press shortcut...")
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.12))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.5), lineWidth: 1.5)
                        )
                } else {
                    Text(config.displayName)
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundColor(accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(accentColor.opacity(0.1))
                        .cornerRadius(8)
                }

                Button(action: {
                    isRecordingKey.toggle()
                    SettingsManager.shared.isCapturingShortcut = isRecordingKey
                }) {
                    Text(isRecordingKey ? "Cancel" : "Record")
                        .font(.caption.weight(.medium))
                        .foregroundColor(isRecordingKey ? .red : .white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isRecordingKey ? Color.red.opacity(0.15) : accentColor)
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Button(action: {
                    config.modifiers = 0
                    config.keyCode = -1
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 26)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("Reset shortcut")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(8)
            .opacity(config.isEnabled ? 1 : 0.4)
            .disabled(!config.isEnabled)
            .background(
                ShortcutCombinationRecorder(isRecording: $isRecordingKey, config: $config)
                    .frame(width: 0, height: 0)
            )

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
        .animation(.easeInOut(duration: 0.15), value: config.mode)
    }
}

/// NSViewRepresentable that captures key presses when isRecording is true
/// Captures any key combination (modifiers + key, or modifiers only)
struct ShortcutCombinationRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var config: HotkeyConfig

    func makeNSView(context: Context) -> ShortcutCombinationRecorderView {
        let view = ShortcutCombinationRecorderView()
        view.onShortcutCaptured = { modifiers, keyCode in
            self.config.modifiers = modifiers
            self.config.keyCode = keyCode
            self.isRecording = false
            SettingsManager.shared.isCapturingShortcut = false
        }
        return view
    }

    func updateNSView(_ nsView: ShortcutCombinationRecorderView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
        nsView.isActive = isRecording
    }
}

class ShortcutCombinationRecorderView: NSView {
    var isActive = false
    /// Called with (modifierFlags rawValue, keyCode). keyCode = -1 for modifier-only.
    var onShortcutCaptured: ((UInt64, Int64) -> Void)?

    /// Accumulated modifiers — only grows while recording, never shrinks
    private var accumulatedModifiers: UInt64 = 0
    private var allModifiersReleased = false
    private var modifierReleaseTimer: Timer?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isActive else { super.keyDown(with: event); return }
        modifierReleaseTimer?.invalidate()
        modifierReleaseTimer = nil
        // Use accumulated modifiers (not just current) + this key
        let currentMods = modsToGCEventFlags(event.modifierFlags.intersection([.shift, .control, .option, .command]))
        accumulatedModifiers |= currentMods
        let finalMods = accumulatedModifiers
        accumulatedModifiers = 0
        onShortcutCaptured?(finalMods, Int64(event.keyCode))
    }

    override func flagsChanged(with event: NSEvent) {
        guard isActive else { super.flagsChanged(with: event); return }
        let currentMods = modsToGCEventFlags(event.modifierFlags.intersection([.shift, .control, .option, .command]))

        if currentMods != 0 {
            // Modifier pressed — accumulate (OR), never remove
            accumulatedModifiers |= currentMods
            modifierReleaseTimer?.invalidate()
            modifierReleaseTimer = nil
        } else if accumulatedModifiers != 0 {
            // ALL modifiers released — save the accumulated combination
            let captured = accumulatedModifiers
            modifierReleaseTimer?.invalidate()
            modifierReleaseTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                self?.accumulatedModifiers = 0
                self?.onShortcutCaptured?(captured, -1)
            }
        }
    }

    private func modsToGCEventFlags(_ mods: NSEvent.ModifierFlags) -> UInt64 {
        var flags: UInt64 = 0
        if mods.contains(.shift) { flags |= CGEventFlags.maskShift.rawValue }
        if mods.contains(.control) { flags |= CGEventFlags.maskControl.rawValue }
        if mods.contains(.option) { flags |= CGEventFlags.maskAlternate.rawValue }
        if mods.contains(.command) { flags |= CGEventFlags.maskCommand.rawValue }
        return flags
    }
}

// MARK: - Waveform View
class WaveformView: NSView {
    private let barCount = 11
    private let weights: [Float] = [0.3, 0.4, 0.55, 0.7, 0.85, 1.0, 0.85, 0.7, 0.55, 0.4, 0.3]
    private var currentLevel: Float = 0
    private var barLayers: [CAGradientLayer] = []
    private var glowLayers: [CALayer] = []

    // Match brand colors: Blue → Purple (same as Settings/Splash logo)
    private let brandBlue = NSColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 1.0)    // #007AFF
    private let brandPurple = NSColor(red: 175/255, green: 82/255, blue: 222/255, alpha: 1.0)  // #AF52DE

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
            glow.backgroundColor = brandBlue.withAlphaComponent(0.4).cgColor
            glow.cornerRadius = 2
            glow.shadowColor = brandBlue.cgColor
            glow.shadowRadius = 3
            glow.shadowOpacity = 0.4
            glow.shadowOffset = .zero
            glow.frame = CGRect(x: x, y: (bounds.height - 3) / 2, width: barWidth, height: 3)
            layer?.addSublayer(glow)
            glowLayers.append(glow)

            // Gradient bar
            let bar = CAGradientLayer()
            bar.colors = [brandBlue.cgColor, brandPurple.cgColor]
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
                red: brandBlue.redComponent * (1 - ratio) + brandPurple.redComponent * ratio,
                green: brandBlue.greenComponent * (1 - ratio) + brandPurple.greenComponent * ratio,
                blue: brandBlue.blueComponent * (1 - ratio) + brandPurple.blueComponent * ratio,
                alpha: 1.0
            )
            barLayers[i].colors = [brandBlue.cgColor, midColor.cgColor]

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
        // Gradient circle background (matches brand: Blue → Purple)
        circleLayer.frame = CGRect(x: 0, y: 0, width: 48, height: 48)
        circleLayer.cornerRadius = 24
        circleLayer.colors = [
            NSColor(red: 0/255, green: 122/255, blue: 255/255, alpha: 1.0).cgColor,    // #007AFF (Blue)
            NSColor(red: 175/255, green: 82/255, blue: 222/255, alpha: 1.0).cgColor     // #AF52DE (Purple)
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

// MARK: - License Tab
struct LicenseTab: View {
    @ObservedObject var licenseManager = LicenseManager.shared
    @State private var showDeactivateConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                licenseHeader
                licenseStatusCard
                if licenseManager.isLicensed {
                    licenseDetailsCard
                    deactivateButton
                }
                permissionsSection
                Spacer()
            }
            .padding(28)
        }
    }

    private var licenseHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.orange)
                Text("License Information")
                    .font(.system(size: 18, weight: .bold))
            }
            Text("Manage your Speechy license and subscription.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }

    private var licenseStatusCard: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(licenseManager.isLicensed ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: licenseManager.isLicensed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .font(.system(size: 22))
                    .foregroundColor(licenseManager.isLicensed ? .green : .red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(licenseManager.isLicensed ? "License Active" : "No Active License")
                    .font(.system(size: 15, weight: .semibold))
                Text(licenseManager.isLicensed ? "Your Speechy license is valid and active." : "Please activate a license to use Speechy.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(licenseManager.isLicensed ? Color.green.opacity(0.05) : Color.red.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(licenseManager.isLicensed ? Color.green.opacity(0.2) : Color.red.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private var licenseDetailsCard: some View {
        VStack(spacing: 0) {
            licenseDetailRow(label: "License Key", value: maskedKey(licenseManager.storedLicenseKey ?? ""), icon: "key", color: .blue, mono: true)
            Divider().padding(.horizontal, 16)
            licenseDetailRow(label: "Plan", value: planLabel(licenseManager.licenseType), icon: "creditcard", color: .purple, mono: false)
            Divider().padding(.horizontal, 16)
            licenseDetailRow(label: "Status", value: licenseManager.licenseStatus.capitalized, icon: "checkmark.circle", color: .green, mono: false)
            if !licenseManager.expiresAt.isEmpty && licenseManager.licenseType != "lifetime" {
                Divider().padding(.horizontal, 16)
                licenseDetailRow(label: "Expires", value: formatDate(licenseManager.expiresAt), icon: "calendar", color: .orange, mono: false)
            }
            Divider().padding(.horizontal, 16)
            licenseDetailRow(label: "Machine ID", value: String(licenseManager.machineID.prefix(16)) + "...", icon: "desktopcomputer", color: .gray, mono: true)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }

    private var deactivateButton: some View {
        Button(action: { showDeactivateConfirm = true }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.left")
                    .font(.system(size: 11, weight: .medium))
                Text("Deactivate License")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.red.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.08))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .alert(isPresented: $showDeactivateConfirm) {
            Alert(
                title: Text("Deactivate License?"),
                message: Text("This will remove the license from this device. You can reactivate it later."),
                primaryButton: .destructive(Text("Deactivate")) {
                    LicenseManager.shared.deactivateAndClear()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            appDelegate.mainWindow?.close()
                            appDelegate.showLicenseScreen()
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private var permissionsSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                Text("Permissions")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
            }
            .padding(.top, 8)

            let perms = checkPermissions()
            VStack(spacing: 0) {
                permissionRow(name: "Accessibility", granted: perms.accessibility, desc: "Global hotkey detection")
                Divider().padding(.horizontal, 16)
                permissionRow(name: "Microphone", granted: perms.microphone, desc: "Voice recording")
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
        }
    }

    func licenseDetailRow(label: String, value: String, icon: String, color: Color, mono: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(color)
                .frame(width: 20)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    func permissionRow(name: String, granted: Bool, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(granted ? .green : .red)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 12, weight: .medium))
                Text(desc).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Text(granted ? "Granted" : "Missing")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(granted ? .green : .red)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background((granted ? Color.green : Color.red).opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    func maskedKey(_ key: String) -> String {
        guard key.count > 8 else { return key }
        return "\(key.prefix(4))••••••••\(key.suffix(4))"
    }

    func planLabel(_ type: String) -> String {
        switch type {
        case "trial": return "Free Trial"
        case "monthly": return "Monthly"
        case "yearly": return "Annual"
        case "lifetime": return "Lifetime"
        default: return type.capitalized
        }
    }

    func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withTimeZone]
        if let date = formatter.date(from: dateStr) {
            let df = DateFormatter()
            df.dateStyle = .medium
            return df.string(from: date)
        }
        return String(dateStr.prefix(10))
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
        setupStatusBar()
        registerSettingsHotkey()

        // Always listen for open settings notification (so Cmd+Shift+S works even without license)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSettingsHotkey), name: NSNotification.Name("OpenSettings"), object: nil)

        // Check license before full initialization
        if LicenseManager.shared.isLicensed {
            log("[Speechy] License found, initializing full app")
            initializeFullApp()
            // Re-verify license in background (every 24h)
            LicenseManager.shared.verifyInBackground()
        } else {
            log("[Speechy] No valid license, showing license screen")
            showLicenseScreen()
        }
    }

    @objc func handleSettingsHotkey() {
        // Always check permissions first
        let perms = checkPermissions()
        if !perms.accessibility || !perms.microphone {
            log("[Speechy] Cmd+Shift+S pressed but permissions missing, showing permission check")
            showPermissionCheck(accessibility: perms.accessibility, microphone: perms.microphone)
            return
        }

        // If no license, show license screen instead of settings
        if !LicenseManager.shared.isLicensed {
            log("[Speechy] Cmd+Shift+S pressed but no license, showing license screen")
            showLicenseScreen()
        } else {
            openSettings()
        }
    }

    func initializeFullApp() {
        guard overlayWindow == nil else { return } // Prevent double init

        overlayWindow = OverlayWindow()
        audioRecorder = AudioRecorder()
        whisperTranscriber = WhisperTranscriber()
        hotkeyManager = HotkeyManager()

        // Check permissions on every launch
        let perms = checkPermissions()
        log("[Speechy] Permission check - Accessibility: \(perms.accessibility), Microphone: \(perms.microphone)")

        if !perms.accessibility || !perms.microphone {
            showPermissionCheck(accessibility: perms.accessibility, microphone: perms.microphone)
            return
        }

        continueFullAppInit()
    }

    func continueFullAppInit() {
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

        log("[Speechy] App fully initialized")
    }

    var permissionWindow: NSWindow?

    func showPermissionCheck(accessibility: Bool, microphone: Bool) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = PermissionCheckView(accessibility: accessibility, microphone: microphone) { [weak self] in
            log("[Speechy] All permissions granted, continuing initialization")
            window.level = .normal
            window.close()
            self?.permissionWindow = nil
            self?.continueFullAppInit()
        }
        window.contentView = NSHostingView(rootView: view)
        window.title = "Speechy — Permissions"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow = window
    }

    func showLicenseScreen() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = LicenseView { [weak self] in
            log("[Speechy] License activated, transitioning to full app")
            window.close()
            self?.initializeFullApp()
        }
        window.contentView = NSHostingView(rootView: view)
        window.title = "Speechy — Activate License"
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
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

    var settingsHotkeyRef: EventHotKeyRef?

    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Use SF Symbol with fallback to text
            if let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Speechy") {
                img.isTemplate = true  // Adapts to light/dark menu bar
                button.image = img
            } else {
                button.title = "🎙"
            }
        }

        // Build right-click menu (also used for left click)
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings… (⌘⇧S)", action: #selector(statusBarClicked), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Speechy", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu

        log("[Speechy] Status bar icon set up")
    }

    func registerSettingsHotkey() {
        // Register Cmd+Shift+S as global hotkey to open settings
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x53505943)  // 'SPYC'
        hotKeyID.id = 1

        // Install handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            NotificationCenter.default.post(name: NSNotification.Name("OpenSettings"), object: nil)
            return noErr
        }, 1, &eventType, nil, nil)

        // S key = keycode 1, Cmd+Shift modifiers
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)
        RegisterEventHotKey(1, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &settingsHotkeyRef)
        log("[Speechy] Global hotkey Cmd+Shift+S registered for settings")
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
                contentRect: NSRect(x: 0, y: 0, width: 672, height: 816),
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

        // Pause media if playing
        MediaControlManager.shared.pauseMediaIfNeeded()

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
                    // Resume media even if recording produced no audio
                    MediaControlManager.shared.resumeMediaIfNeeded()
                }
                return
            }

            // If saving audio is enabled, copy the file BEFORE whisper processes it
            // because the temp file may be deleted during/after transcription
            var savedAudioURL: URL? = nil
            if SettingsManager.shared.saveAudioRecordings {
                let dir = SettingsManager.shared.recordingsDirectory
                let fileName = "\(UUID().uuidString).wav"
                let destURL = dir.appendingPathComponent(fileName)
                do {
                    try FileManager.default.copyItem(at: audioURL, to: destURL)
                    savedAudioURL = destURL
                    log("[Speechy] Audio pre-saved: \(destURL.path)")
                } catch {
                    log("[Speechy] Failed to pre-save audio: \(error.localizedDescription)")
                }
            }

            self.whisperTranscriber.transcribe(audioURL: audioURL, language: self.activeLanguage) { result in
                DispatchQueue.main.async {
                    self.overlayWindow.setState(.hidden)
                    if let text = result, !text.isEmpty {
                        SettingsManager.shared.addToHistory(text, language: self.activeLanguage, audioPath: savedAudioURL?.path)
                        self.pasteText(text)
                    } else if let url = savedAudioURL {
                        // Transcription failed/empty — clean up the saved audio
                        try? FileManager.default.removeItem(at: url)
                    }
                    // Resume media after transcription is complete
                    MediaControlManager.shared.resumeMediaIfNeeded()
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
        hotkeyManager?.stopListening()
        NSApp.terminate(nil)
    }
}

// MARK: - Hotkey Manager
class HotkeyManager {
    var onRecordingStart: ((String, String) -> Void)?
    var onRecordingStop: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var slotConfigs: [HotkeyConfig] = []
    private var activationDelay: Double = 0.15

    private var activeSlotID: UUID? = nil
    private var delayTimer: Timer?
    private var isRecording = false
    private var isToggleMode = false
    private var toggleStopIgnoreRelease = false
    private var cooldownUntil: Date = .distantPast

    func updateConfigs() {
        let settings = SettingsManager.shared
        slotConfigs = settings.slots
        activationDelay = settings.activationDelay
        let names = slotConfigs.map { "\($0.name.isEmpty ? "unnamed" : $0.name): \($0.displayName)" }.joined(separator: ", ")
        log("[Speechy] Configs updated - \(slotConfigs.count) slots: \(names)")
    }

    /// Find a slot config by its UUID
    private func configForID(_ id: UUID) -> HotkeyConfig? {
        return slotConfigs.first { $0.id == id }
    }

    func startListening() {
        stopListening()
        log("[Speechy] Attempting to start hotkey listener...")

        let eventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

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

        let flags = event.flags

        // Suppress hotkeys while user is recording a new shortcut in settings
        if SettingsManager.shared.isCapturingShortcut {
            return Unmanaged.passUnretained(event)
        }

        // Cooldown check — ignore all trigger events briefly after stopping
        if Date() < cooldownUntil && !isRecording {
            return Unmanaged.passUnretained(event)
        }

        // === keyDown handling ===
        if type == .keyDown {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Escape key (keyCode 53) stops toggle recording — respects per-slot escCancels setting
            if keyCode == 53 && isRecording && isToggleMode {
                if let activeID = activeSlotID, let activeConfig = configForID(activeID), activeConfig.escCancels {
                    log("[Speechy] Escape pressed, stopping toggle recording")
                    stopCurrentRecording()
                    return nil // consume the Escape key
                }
                // If escCancels is false, pass through the Escape key
            }

            // Check key+modifier configs on keyDown — iterate all slots
            for cfg in slotConfigs {
                guard cfg.isEnabled && !cfg.isModifierOnly && cfg.keyCode == keyCode else { continue }
                guard matchesModifiers(flags: flags, config: cfg) else { continue }

                // Toggle mode: second keyDown of the same combo stops recording
                if isRecording && isToggleMode && activeSlotID == cfg.id {
                    if !toggleStopIgnoreRelease {
                        log("[Speechy] Toggle key re-pressed, stopping toggle recording (\(cfg.name))")
                        toggleStopIgnoreRelease = true
                        stopCurrentRecording()
                        return nil // consume
                    }
                    return nil // consume repeated keyDown while ignoring
                }

                // Start recording if not already active
                if activeSlotID == nil && !isRecording {
                    activeSlotID = cfg.id
                    isToggleMode = (cfg.mode == .toggleToTalk)
                    if isToggleMode { toggleStopIgnoreRelease = true }
                    startDelayTimer(language: cfg.language, flag: getFlag(for: cfg.language))
                    return nil // consume the trigger key
                }

                return nil // consume even if already active
            }

            return Unmanaged.passUnretained(event)
        }

        // === keyUp handling ===
        if type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

            // Only handle keyUp for key+modifier push-to-talk configs
            if let activeID = activeSlotID, !isToggleMode, let activeConfig = configForID(activeID) {
                if !activeConfig.isModifierOnly && activeConfig.keyCode == keyCode {
                    if isRecording {
                        stopCurrentRecording()
                    } else {
                        delayTimer?.invalidate()
                        delayTimer = nil
                        activeSlotID = nil
                    }
                    return nil // consume the trigger key release
                }
            }

            // Toggle mode: reset the ignore flag on keyUp so next keyDown can stop
            if isRecording && isToggleMode {
                if let activeID = activeSlotID, let activeConfig = configForID(activeID) {
                    if !activeConfig.isModifierOnly && activeConfig.keyCode == keyCode {
                        toggleStopIgnoreRelease = false
                        return nil // consume
                    }
                }
            }

            return Unmanaged.passUnretained(event)
        }

        // === flagsChanged handling (modifier-only configs) ===

        // Toggle mode: if recording, pressing the same modifier again stops it
        if isRecording && isToggleMode {
            if let activeID = activeSlotID, let activeConfig = configForID(activeID) {
                if activeConfig.isModifierOnly {
                    if matchesModifiers(flags: flags, config: activeConfig) && !toggleStopIgnoreRelease {
                        log("[Speechy] Toggle modifier re-pressed, stopping toggle recording")
                        toggleStopIgnoreRelease = true
                        stopCurrentRecording()
                        return Unmanaged.passUnretained(event)
                    }
                    if !matchesModifiers(flags: flags, config: activeConfig) {
                        toggleStopIgnoreRelease = false
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }

        if activeSlotID == nil && !isRecording {
            // Check all modifier-only slots — iterate in order
            for cfg in slotConfigs {
                guard cfg.isEnabled && cfg.isModifierOnly && matchesModifiers(flags: flags, config: cfg) else { continue }
                activeSlotID = cfg.id
                isToggleMode = (cfg.mode == .toggleToTalk)
                if isToggleMode { toggleStopIgnoreRelease = true }
                startDelayTimer(language: cfg.language, flag: getFlag(for: cfg.language))
                break
            }
        } else if activeSlotID != nil && !isToggleMode {
            // Push-to-talk (modifier-only): stop on modifier release
            if let activeID = activeSlotID, let activeConfig = configForID(activeID) {
                if activeConfig.isModifierOnly && !matchesModifiers(flags: flags, config: activeConfig) {
                    if isRecording {
                        stopCurrentRecording()
                    } else {
                        delayTimer?.invalidate()
                        delayTimer = nil
                        activeSlotID = nil
                    }
                }
            }
        }
        // Toggle mode before recording: ignore modifier releases, let delay timer fire
        // Toggle mode while recording: ignore modifier releases (wait for same modifier re-press)

        return Unmanaged.passUnretained(event)
    }

    /// Check if the current modifier flags match the config's required modifiers.
    /// For modifier-only configs this checks exact match; for key+modifier configs this just checks modifiers are held.
    func matchesModifiers(flags: CGEventFlags, config: HotkeyConfig) -> Bool {
        let required = config.modifierFlags
        if required.rawValue == 0 && config.isModifierOnly { return false }

        if required.contains(.maskControl) && !flags.contains(.maskControl) { return false }
        if required.contains(.maskAlternate) && !flags.contains(.maskAlternate) { return false }
        if required.contains(.maskShift) && !flags.contains(.maskShift) { return false }
        if required.contains(.maskCommand) && !flags.contains(.maskCommand) { return false }

        return true
    }

    private func startDelayTimer(language: String, flag: String) {
        delayTimer?.invalidate()
        delayTimer = Timer.scheduledTimer(withTimeInterval: activationDelay, repeats: false) { [weak self] _ in
            guard let self = self, self.activeSlotID != nil else { return }
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

    /// Centralized stop — sets cooldown to prevent immediate re-trigger
    private func stopCurrentRecording() {
        isRecording = false
        isToggleMode = false
        activeSlotID = nil
        cooldownUntil = Date().addingTimeInterval(0.5)
        DispatchQueue.main.async { self.onRecordingStop?() }
    }

    func getFlag(for language: String) -> String {
        supportedLanguages.first { $0.code == language }?.flag ?? "🎙️"
    }

    private var permissionCheckTimer: Timer?

    private func showAccessibilityPrompt() {
        DispatchQueue.main.async { [weak self] in
            self?.startPermissionPolling()

            // Show the dedicated permission check window via AppDelegate
            let perms = checkPermissions()
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.showPermissionCheck(accessibility: perms.accessibility, microphone: perms.microphone)
                return
            }

            // Fallback to basic alert if AppDelegate not available
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

        let nativeURL = self.nativeURL
        let finalURL = self.finalURL

        guard let nativeURL = nativeURL, let finalURL = finalURL else {
            self.nativeFile = nil
            completion(nil)
            return
        }

        // Wait for pending writes to finish, then convert offline.
        // nativeFile must be cleared inside writeQueue so that any already-queued
        // write(from:) calls (which access self?.nativeFile) complete before we
        // release the file — otherwise the last audio buffer(s) get dropped.
        writeQueue.async {
            self.nativeFile = nil

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
        "Altyazı M.K.",
        "Altyazı M.K",
        "altyazı m.k.",
        "Alt yazı M.K.",
        "Altyazılar M.K.",
        "ALTYAZI M.K.",
        "Altyazı:",
        "Alt yazı:",
        "Subtitles by",
        "Translated by",
        "Çeviri:",
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

        // Remove subtitle attribution patterns (e.g., "Altyazı M.K.", "Subtitles by XYZ")
        let subtitlePattern = #"(?i)(?:alt\s?yazı|subtitle|translated|çeviri)\s*:?\s*[A-Za-zÇĞİÖŞÜçğıöşü.]+(?:\s+[A-Za-zÇĞİÖŞÜçğıöşü.]+)*"#
        if let subtitleRegex = try? NSRegularExpression(pattern: subtitlePattern, options: []) {
            filtered = subtitleRegex.stringByReplacingMatches(in: filtered, options: [], range: NSRange(filtered.startIndex..., in: filtered), withTemplate: "")
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
app.setActivationPolicy(.accessory)  // Menu bar app: no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
#endif
