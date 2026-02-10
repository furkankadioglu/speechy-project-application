import XCTest
@testable import Speechy

final class AudioRecorderEngineTests: XCTestCase {

    var recorder: AudioRecorderEngine!

    override func setUp() {
        super.setUp()
        recorder = AudioRecorderEngine()
    }

    override func tearDown() {
        recorder = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialIsRecordingIsFalse() {
        XCTAssertFalse(recorder.isRecording)
    }

    // MARK: - stopRecording without starting

    func testStopRecordingReturnsEmptyArrayWhenNotRecording() {
        let frames = recorder.stopRecording()
        XCTAssertTrue(frames.isEmpty)
    }

    func testStopRecordingKeepsIsRecordingFalse() {
        _ = recorder.stopRecording()
        XCTAssertFalse(recorder.isRecording)
    }

    // MARK: - RecorderError

    func testFormatErrorDescription() {
        let error = AudioRecorderEngine.RecorderError.formatError
        XCTAssertEqual(error.errorDescription, "Ses formatı oluşturulamadı")
    }

    func testConverterErrorDescription() {
        let error = AudioRecorderEngine.RecorderError.converterError
        XCTAssertEqual(error.errorDescription, "Ses dönüştürücü oluşturulamadı")
    }

    func testRecorderErrorConformsToLocalizedError() {
        let error: LocalizedError = AudioRecorderEngine.RecorderError.formatError
        XCTAssertNotNil(error.errorDescription)
    }
}
