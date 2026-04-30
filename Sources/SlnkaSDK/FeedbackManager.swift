import Foundation

/// Manages feedback submission, survey lifecycle, and prompt fatigue.
///
/// Follows the same internal pattern as `EventTracker` — owns a Transport
/// and Storage reference, exposes async methods, and guards behind consent.
final class FeedbackManager {

    private let transport: Transport
    private let storage: SlnkaStorage
    private let debug: Bool

    /// Maximum prompts allowed per calendar week.
    private let maxPromptsPerWeek = 2

    init(transport: Transport, storage: SlnkaStorage, debug: Bool = false) {
        self.transport = transport
        self.storage = storage
        self.debug = debug
    }

    // MARK: - Fatigue

    /// Returns `true` if a prompt can be shown without exceeding the weekly limit.
    func canShowPrompt() -> Bool {
        let weekKey = currentWeekKey()
        let count = storage.getInt(forKey: weekKey)
        let allowed = count < maxPromptsPerWeek
        logDebug("Fatigue check: \(count)/\(maxPromptsPerWeek) this week (\(weekKey)) -> \(allowed ? "allowed" : "blocked")")
        return allowed
    }

    /// Increments the fatigue counter for the current calendar week.
    func incrementFatigueCount() {
        let weekKey = currentWeekKey()
        let current = storage.getInt(forKey: weekKey)
        storage.setInt(current + 1, forKey: weekKey)
        logDebug("Fatigue incremented to \(current + 1) for \(weekKey)")
    }

    // MARK: - Single Feedback Response

    /// Submits a single feedback response to POST /api/v1/sdk/feedback/responses.
    func submitResponse(
        promptType: String,
        question: String,
        value: Any,
        pageUrl: String?,
        metadata: [String: Any]?
    ) async {
        var payload: [String: Any] = [
            "prompt_type": promptType,
            "question": question,
            "value": normalizeValue(value),
            "anonymous_id": storage.getOrCreateAnonymousId(),
            "timestamp": iso8601Now()
        ]

        if let pageUrl = pageUrl {
            payload["page_url"] = pageUrl
        }

        if let metadata = metadata {
            payload["metadata"] = metadata
        }

        if let userId = storage.getUserId() {
            payload["user_id"] = userId
        }

        let success = await transport.submitFeedbackResponse(payload)
        logDebug("Submit feedback response: \(success ? "OK" : "FAILED")")
    }

    // MARK: - Survey Lifecycle

    /// Starts a survey response session.
    /// Returns the server-assigned response ID, or `nil` on failure.
    func startSurveyResponse(surveyId: String) async -> String? {
        let payload: [String: Any] = [
            "survey_id": surveyId,
            "anonymous_id": storage.getOrCreateAnonymousId(),
            "session_id": storage.getSessionId() ?? "unknown",
            "timestamp": iso8601Now()
        ]

        let responseId = await transport.startSurveyResponse(payload)
        logDebug("Start survey response: \(responseId ?? "nil")")
        return responseId
    }

    /// Submits an answer for a single survey step.
    func submitSurveyStepAnswer(
        responseId: String,
        promptConfigId: String,
        promptType: String,
        question: String,
        value: Any
    ) async {
        let payload: [String: Any] = [
            "survey_response_id": responseId,
            "prompt_config_id": promptConfigId,
            "prompt_type": promptType,
            "question": question,
            "value": normalizeValue(value),
            "anonymous_id": storage.getOrCreateAnonymousId(),
            "timestamp": iso8601Now()
        ]

        let success = await transport.submitFeedbackResponse(payload)
        logDebug("Submit survey step answer (response=\(responseId), step=\(promptConfigId)): \(success ? "OK" : "FAILED")")
    }

    /// Marks a survey response as complete.
    func completeSurveyResponse(responseId: String) async {
        let success = await transport.completeSurveyResponse(responseId: responseId)
        logDebug("Complete survey response \(responseId): \(success ? "OK" : "FAILED")")
    }

    // MARK: - Private Helpers

    /// Returns the UserDefaults key for the current ISO week (e.g. `__slnka_fb_2026-W15`).
    private func currentWeekKey() -> String {
        let calendar = Calendar(identifier: .iso8601)
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let year = components.yearForWeekOfYear ?? 2026
        let week = components.weekOfYear ?? 1
        return "__slnka_fb_\(year)-W\(String(format: "%02d", week))"
    }

    private func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    /// Normalizes feedback values to JSON-safe types.
    private func normalizeValue(_ value: Any) -> Any {
        if let intVal = value as? Int {
            return intVal
        } else if let doubleVal = value as? Double {
            return doubleVal
        } else if let stringVal = value as? String {
            return stringVal
        } else if let boolVal = value as? Bool {
            return boolVal
        } else {
            return String(describing: value)
        }
    }

    private func logDebug(_ message: String) {
        if debug {
            print("[SlnkaSDK:FeedbackManager] \(message)")
        }
    }
}
