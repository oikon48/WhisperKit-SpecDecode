//  For licensing see accompanying LICENSE.md file.
//  Copyright © 2024 Argmax, Inc. All rights reserved.

import CoreML
@testable import WhisperKit
import XCTest

/// Unit tests for Speculative Decoding functionality.
/// Tests cover DecodingOptions extensions, TranscriptionStateManager, and error types.
final class SpeculativeDecodingTests: XCTestCase {
    override func setUp() async throws {
        Logging.shared.logLevel = .debug
    }

    // MARK: - DecodingOptions Tests

    func testDecodingOptions_defaultValues() {
        // Arrange & Act
        let options = DecodingOptions()

        // Assert
        XCTAssertFalse(options.useSpeculativeDecoding)
        XCTAssertNil(options.assistantModel)
        XCTAssertEqual(options.speculativeThreshold, 0.9)
        XCTAssertEqual(options.maxSpeculationLength, 8)
    }

    func testDecodingOptions_customValues() {
        // Arrange & Act
        let options = DecodingOptions(
            useSpeculativeDecoding: true,
            assistantModel: "distil-whisper-tiny",
            speculativeThreshold: 0.85,
            maxSpeculationLength: 4
        )

        // Assert
        XCTAssertTrue(options.useSpeculativeDecoding)
        XCTAssertEqual(options.assistantModel, "distil-whisper-tiny")
        XCTAssertEqual(options.speculativeThreshold, 0.85)
        XCTAssertEqual(options.maxSpeculationLength, 4)
    }

    func testDecodingOptions_speculativeThresholdBoundaries() {
        // Test lower boundary
        let lowThreshold = DecodingOptions(
            useSpeculativeDecoding: true,
            speculativeThreshold: 0.0
        )
        XCTAssertEqual(lowThreshold.speculativeThreshold, 0.0)

        // Test upper boundary
        let highThreshold = DecodingOptions(
            useSpeculativeDecoding: true,
            speculativeThreshold: 1.0
        )
        XCTAssertEqual(highThreshold.speculativeThreshold, 1.0)
    }

    // MARK: - TranscriptionStateManager Tests

    func testTranscriptionStateManager_initialState() async {
        // Arrange
        let manager = TranscriptionStateManager()

        // Act
        let mode = await manager.mode

        // Assert
        XCTAssertEqual(mode, .idle)
    }

    func testTranscriptionStateManager_beginNormalTranscription() async throws {
        // Arrange
        let manager = TranscriptionStateManager()

        // Act
        let id = try await manager.beginTranscription(speculative: false)

        // Assert
        XCTAssertNotNil(id)
        let mode = await manager.mode
        XCTAssertEqual(mode, .normalDecoding)
    }

    func testTranscriptionStateManager_beginSpeculativeTranscription() async throws {
        // Arrange
        let manager = TranscriptionStateManager()

        // Act
        let id = try await manager.beginTranscription(speculative: true)

        // Assert
        XCTAssertNotNil(id)
        let mode = await manager.mode
        XCTAssertEqual(mode, .speculativeDecoding)
    }

    func testTranscriptionStateManager_endTranscription() async throws {
        // Arrange
        let manager = TranscriptionStateManager()
        let id = try await manager.beginTranscription(speculative: false)

        // Act
        await manager.endTranscription(id: id)

        // Assert
        let mode = await manager.mode
        XCTAssertEqual(mode, .idle)
    }

    func testTranscriptionStateManager_beginWhileInProgress_throws() async throws {
        // Arrange
        let manager = TranscriptionStateManager()
        _ = try await manager.beginTranscription(speculative: false)

        // Act & Assert
        do {
            _ = try await manager.beginTranscription(speculative: true)
            XCTFail("Expected error to be thrown")
        } catch let error as WhisperError {
            if case .transcriptionInProgress = error {
                // Expected
            } else {
                XCTFail("Expected transcriptionInProgress error, got \(error)")
            }
        }
    }

    func testTranscriptionStateManager_validateActive_success() async throws {
        // Arrange
        let manager = TranscriptionStateManager()
        let id = try await manager.beginTranscription(speculative: false)

        // Act & Assert - should not throw
        try await manager.validateActive(id: id)
    }

    func testTranscriptionStateManager_validateActive_wrongId_throws() async throws {
        // Arrange
        let manager = TranscriptionStateManager()
        _ = try await manager.beginTranscription(speculative: false)
        let wrongId = UUID()

        // Act & Assert
        do {
            try await manager.validateActive(id: wrongId)
            XCTFail("Expected error to be thrown")
        } catch let error as WhisperError {
            if case .transcriptionCancelled = error {
                // Expected
            } else {
                XCTFail("Expected transcriptionCancelled error, got \(error)")
            }
        }
    }

    func testTranscriptionStateManager_cancel() async throws {
        // Arrange
        let manager = TranscriptionStateManager()
        let id = try await manager.beginTranscription(speculative: false)

        // Act
        await manager.cancel()

        // Assert - validate should throw
        do {
            try await manager.validateActive(id: id)
            XCTFail("Expected error after cancel")
        } catch {
            // Expected
        }
    }

    // MARK: - TranscriptionMode Tests

    func testTranscriptionMode_isIdle() {
        XCTAssertTrue(TranscriptionMode.idle.isIdle)
        XCTAssertFalse(TranscriptionMode.normalDecoding.isIdle)
        XCTAssertFalse(TranscriptionMode.speculativeDecoding.isIdle)
    }

    func testTranscriptionMode_isSpeculative() {
        XCTAssertFalse(TranscriptionMode.idle.isSpeculative)
        XCTAssertFalse(TranscriptionMode.normalDecoding.isSpeculative)
        XCTAssertTrue(TranscriptionMode.speculativeDecoding.isSpeculative)
    }

    // MARK: - WhisperError SD Tests

    func testWhisperError_assistantModelNotLoaded() {
        let error = WhisperError.assistantModelNotLoaded()
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("Assistant model") ?? false)
    }

    func testWhisperError_transcriptionInProgress() {
        let error = WhisperError.transcriptionInProgress()
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("in progress") ?? false)
    }

    func testWhisperError_transcriptionCancelled() {
        let error = WhisperError.transcriptionCancelled()
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("cancelled") ?? false)
    }

    func testWhisperError_customMessages() {
        let customError = WhisperError.assistantModelNotLoaded("Custom message")
        XCTAssertTrue(customError.errorDescription?.contains("Custom message") ?? false)
    }

    func testWhisperError_equatable() {
        // Same errors should be equal
        XCTAssertEqual(
            WhisperError.assistantModelNotLoaded(),
            WhisperError.assistantModelNotLoaded()
        )

        // Different errors should not be equal
        XCTAssertNotEqual(
            WhisperError.assistantModelNotLoaded(),
            WhisperError.transcriptionInProgress()
        )
    }

    // MARK: - SpeculativeDecodingResult Tests

    func testSpeculativeDecodingResult_creation() {
        // Arrange & Act
        let result = TextDecoder.SpeculativeDecodingResult(
            tokens: [1, 2, 3, 4, 5],
            acceptedCount: 4,
            correctedCount: 1
        )

        // Assert
        XCTAssertEqual(result.tokens.count, 5)
        XCTAssertEqual(result.acceptedCount, 4)
        XCTAssertEqual(result.correctedCount, 1)
    }

    func testSpeculativeDecodingResult_allAccepted() {
        // Arrange & Act
        let result = TextDecoder.SpeculativeDecodingResult(
            tokens: [1, 2, 3],
            acceptedCount: 3,
            correctedCount: 0
        )

        // Assert
        XCTAssertEqual(result.acceptedCount, 3)
        XCTAssertEqual(result.correctedCount, 0)
    }

    func testSpeculativeDecodingResult_allCorrected() {
        // Arrange & Act
        let result = TextDecoder.SpeculativeDecodingResult(
            tokens: [1, 2],
            acceptedCount: 0,
            correctedCount: 2
        )

        // Assert
        XCTAssertEqual(result.acceptedCount, 0)
        XCTAssertEqual(result.correctedCount, 2)
    }
}
