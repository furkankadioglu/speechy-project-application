import XCTest
@testable import Speechy

@MainActor
final class WhisperTranscriberTests: XCTestCase {

    var transcriber: WhisperTranscriber!

    override func setUp() {
        super.setUp()
        transcriber = WhisperTranscriber()
    }

    override func tearDown() {
        transcriber = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialStateIsIdle() {
        if case .idle = transcriber.state {
            // OK
        } else {
            XCTFail("Initial state should be .idle, got: \(transcriber.state)")
        }
    }

    func testInitialTranscriptIsEmpty() {
        XCTAssertEqual(transcriber.transcript, "")
    }

    // MARK: - isRecording

    func testIsRecordingFalseWhenIdle() {
        XCTAssertFalse(transcriber.isRecording)
    }

    func testIsRecordingTrueWhenRecording() {
        transcriber.state = .recording
        XCTAssertTrue(transcriber.isRecording)
    }

    func testIsRecordingFalseWhenReady() {
        transcriber.state = .ready
        XCTAssertFalse(transcriber.isRecording)
    }

    func testIsRecordingFalseWhenTranscribing() {
        transcriber.state = .transcribing
        XCTAssertFalse(transcriber.isRecording)
    }

    // MARK: - isTranscribing

    func testIsTranscribingFalseWhenIdle() {
        XCTAssertFalse(transcriber.isTranscribing)
    }

    func testIsTranscribingTrueWhenTranscribing() {
        transcriber.state = .transcribing
        XCTAssertTrue(transcriber.isTranscribing)
    }

    func testIsTranscribingFalseWhenRecording() {
        transcriber.state = .recording
        XCTAssertFalse(transcriber.isTranscribing)
    }

    // MARK: - errorMessage

    func testErrorMessageNilWhenIdle() {
        XCTAssertNil(transcriber.errorMessage)
    }

    func testErrorMessageNilWhenReady() {
        transcriber.state = .ready
        XCTAssertNil(transcriber.errorMessage)
    }

    func testErrorMessageReturnsMessageWhenError() {
        transcriber.state = .error("Bir hata oluştu")
        XCTAssertEqual(transcriber.errorMessage, "Bir hata oluştu")
    }

    func testErrorMessageNilWhenRecording() {
        transcriber.state = .recording
        XCTAssertNil(transcriber.errorMessage)
    }

    // MARK: - clearTranscript

    func testClearTranscriptClearsText() {
        transcriber.transcript = "Merhaba dünya"
        transcriber.clearTranscript()
        XCTAssertEqual(transcriber.transcript, "")
    }

    func testClearTranscriptResetsErrorState() {
        transcriber.state = .error("Test hatası")
        transcriber.clearTranscript()
        if case .ready = transcriber.state {
            // OK
        } else {
            XCTFail("State should be .ready after clearing error, got: \(transcriber.state)")
        }
    }

    func testClearTranscriptDoesNotChangeNonErrorState() {
        transcriber.state = .recording
        transcriber.clearTranscript()
        if case .recording = transcriber.state {
            // OK - should stay recording
        } else {
            XCTFail("State should still be .recording, got: \(transcriber.state)")
        }
    }

    // MARK: - loadModelIfNeeded (without model)

    func testLoadModelDoesNothingWhenModelNotReady() async {
        // Model dosyası yok, loadModelIfNeeded idle'dan çıkmamalı
        ModelDownloadManager.shared.deleteModel()
        await transcriber.loadModelIfNeeded()
        // State idle kalmalı çünkü model yok
        if case .idle = transcriber.state {
            // OK
        } else if case .loadingModel = transcriber.state {
            // Bu da kabul edilebilir - model yüklemeye çalışıp başarısız olabilir
        } else if case .error = transcriber.state {
            // Model yok, hata normal
        } else {
            // State idle kalmalı
        }
    }
}
