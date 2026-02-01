//  For licensing see accompanying LICENSE.md file.
//  Copyright © 2024 Argmax, Inc. All rights reserved.

import Foundation

// MARK: - Transcription Mode

/// Represents the current transcription mode
public enum TranscriptionMode: Sendable, Equatable {
    /// No transcription in progress
    case idle

    /// Normal (non-speculative) transcription
    case normal

    /// Speculative decoding enabled
    case speculative

    /// Transitioning between modes (stored as raw strings to avoid recursion)
    indirect case transitioning(from: TranscriptionMode, to: TranscriptionMode)

    /// Check if currently idle
    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    /// Check if transcription is active (not idle or transitioning)
    public var isActive: Bool {
        switch self {
        case .normal, .speculative:
            return true
        case .idle, .transitioning:
            return false
        }
    }
}

// MARK: - Transcription State Manager

/// Actor for managing transcription state and preventing reentrancy issues
public actor TranscriptionStateManager {
    /// Current transcription mode
    private(set) public var mode: TranscriptionMode = .idle

    /// Active transcription identifier for cancellation support
    private(set) public var activeId: UUID?

    public init() {}

    // MARK: - State Transitions

    /// Begin a new transcription session
    /// - Parameter speculative: Whether to use speculative decoding
    /// - Returns: Unique ID for this transcription session
    /// - Throws: WhisperError.transcriptionInProgress if already active
    public func beginTranscription(speculative: Bool) throws -> UUID {
        guard mode.isIdle else {
            throw WhisperError.transcriptionInProgress()
        }

        let id = UUID()
        self.activeId = id
        self.mode = speculative ? .speculative : .normal
        return id
    }

    /// Validate that a transcription is still active
    /// - Parameter id: The transcription ID to validate
    /// - Throws: WhisperError.transcriptionCancelled if not active
    public func validateActive(id: UUID) throws {
        guard self.activeId == id else {
            throw WhisperError.transcriptionCancelled()
        }
    }

    /// End a transcription session
    /// - Parameter id: The transcription ID to end
    public func endTranscription(id: UUID) {
        guard self.activeId == id else { return }
        self.activeId = nil
        self.mode = .idle
    }

    /// Cancel the current transcription
    public func cancelTranscription() {
        self.activeId = nil
        self.mode = .idle
    }

    /// Transition to a new mode
    /// - Parameter newMode: The target mode
    public func transitionTo(_ newMode: TranscriptionMode) async {
        let currentMode = self.mode
        self.mode = .transitioning(from: currentMode, to: newMode)

        // Allow async work to complete during transition
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        self.mode = newMode
    }
}
