import XCTest
@testable import ParrotCore

final class WhisperCppTests: XCTestCase {
    func testModelVariantsMatchGGMLNames() throws {
        let english = try XCTUnwrap(ModelRegistry.find("whisper-base.en"))
        let turbo = try XCTUnwrap(ModelRegistry.find("whisper-large-v3-turbo"))
        XCTAssertEqual(WhisperCppTranscriber.variant(for: english), "base.en")
        XCTAssertEqual(WhisperCppTranscriber.variant(for: turbo), "large-v3-turbo")
    }

    func testWAVContainsMonoPCM16AndClipsInvalidSamples() {
        let wav = WhisperCppTranscriber.wavData([-2, -1, 0, 1, 2, .nan])
        XCTAssertEqual(wav.count, 56)
        XCTAssertEqual(String(decoding: wav[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: wav[8..<16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(Array(wav[24..<28]), [0x80, 0x3e, 0, 0]) // 16 kHz
        XCTAssertEqual(Array(wav[44...]), [1, 128, 1, 128, 0, 0, 255, 127, 255, 127, 0, 0])
    }
}
