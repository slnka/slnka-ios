import Foundation

/// Manages feedback submission, survey lifecycle, and prompt fatigue.
///
/// Follows the same internal pattern as `EventTracker` — owns a Transport
/// and Storage reference, exposes async methods, and guards behind consent.
final class FeedbackManager {

    private let transport: Transport
    private let storage: SlnkaStorage
    private let debug: Bool

    /// Conservative client-side default. Overridden when a poll cycle (or a
    /// direct `showFeedback` caller) supplies a server-driven cap via
    /// `serverMaxPerWeek`.
    private let defaultMaxPromptsPerWeek = 2

    /// Server-driven fatigue cap captured by the most recent poll cycle (or
    /// set by an explicit caller). When non-nil, this overrides
    /// `defaultMaxPromptsPerWeek` in `canShowPrompt()`.
    var serverMaxPerWeek: Int?

    init(transport: Transport, storage: SlnkaStorage, debug: Bool = false) {
        self.transport = transport
        self.storage = storage
        self.debug = debug
    }

    // MARK: - Fatigue

    /// Returns `true` if a prompt can be shown without exceeding the weekly limit.
    /// The cap is the server-driven `serverMaxPerWeek` when set, otherwise the
    /// conservative default of 2.
    func canShowPrompt() -> Bool {
        let weekKey = currentWeekKey()
        let count = storage.getInt(forKey: weekKey)
        let cap = serverMaxPerWeek ?? defaultMaxPromptsPerWeek
        let allowed = count < cap
        logDebug("Fatigue check: \(count)/\(cap) this week (\(weekKey)) -> \(allowed ? "allowed" : "blocked")")
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
    /// Payload shape matches the backend `SubmitResponseRequest` DTO (camelCase
    /// fields, flat — no nested `context` block, scalar value split across
    /// `responseValue` (string) and `responseScore` (int) per the column types
    /// in `feedback.feedback_responses`).
    func submitResponse(
        promptType: String,
        question: String,
        value: Any,
        pageUrl: String?,
        triggerName: String? = nil,
        metadata: [String: Any]?
    ) async {
        let normalized = normalizeValue(value)
        let isNumeric = normalized is Int || normalized is Double || normalized is NSNumber
        var payload: [String: Any] = [
            "promptType": promptType,
            "question": question,
            "anonymousId": storage.getOrCreateAnonymousId(),
            "timestamp": iso8601Now()
        ]
        if isNumeric {
            payload["responseScore"] = normalized
        } else {
            payload["responseValue"] = String(describing: normalized)
        }
        if let sessionId = storage.getSessionId() {
            payload["sessionId"] = sessionId
        }
        if let triggerName = triggerName {
            payload["triggerName"] = triggerName
        }
        if let pageUrl = pageUrl {
            payload["pageUrl"] = pageUrl
        }
        if let metadata = metadata {
            payload["metadata"] = metadata
        }
        if let userId = storage.getUserId() {
            payload["userId"] = userId
        }

        let success = await transport.submitFeedbackResponse(payload)
        logDebug("Submit feedback response: \(success ? "OK" : "FAILED")")
    }

    // MARK: - Survey Lifecycle

    /// Starts a survey response session.
    /// Returns the server-assigned response ID, or `nil` on failure.
    func startSurveyResponse(surveyId: String) async -> String? {
        let payload: [String: Any] = [
            "surveyId": surveyId,
            "anonymousId": storage.getOrCreateAnonymousId(),
            "sessionId": storage.getSessionId() ?? "unknown",
            "timestamp": iso8601Now()
        ]

        let responseId = await transport.startSurveyResponse(payload)
        logDebug("Start survey response: \(responseId ?? "nil")")
        return responseId
    }

    /// Submits an answer for a single survey step.
    /// Same flat camelCase shape as `submitResponse` (see comment there).
    func submitSurveyStepAnswer(
        responseId: String,
        promptConfigId: String,
        promptType: String,
        question: String,
        value: Any
    ) async {
        let normalized = normalizeValue(value)
        let isNumeric = normalized is Int || normalized is Double || normalized is NSNumber
        var payload: [String: Any] = [
            "surveyResponseId": responseId,
            "promptConfigId": promptConfigId,
            "promptType": promptType,
            "question": question,
            "anonymousId": storage.getOrCreateAnonymousId(),
            "timestamp": iso8601Now()
        ]
        if isNumeric {
            payload["responseScore"] = normalized
        } else {
            payload["responseValue"] = String(describing: normalized)
        }
        if let sessionId = storage.getSessionId() {
            payload["sessionId"] = sessionId
        }
        if let userId = storage.getUserId() {
            payload["userId"] = userId
        }

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
