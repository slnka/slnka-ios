import Foundation

// MARK: - Feedback Prompt Type

/// The type of feedback prompt to display.
public enum FeedbackPromptType: String, Codable, Sendable {
    /// Net Promoter Score (0-10)
    case nps
    /// Customer Satisfaction (1-5 stars)
    case csat
    /// Customer Effort Score (1-7)
    case ces
    /// Emoji scale (5 emojis)
    case emoji
    /// Thumbs up / down
    case thumbs
    /// Open-ended text response
    case open
    /// Selectable chip options
    case chips
}

// MARK: - Feedback Show Options

/// Configuration for displaying a single feedback prompt.
public struct FeedbackShowOptions {

    /// The type of prompt to render.
    public let promptType: FeedbackPromptType

    /// The question to display to the user.
    public let question: String

    /// Chip choices for `.chips` prompts.
    /// - Server-driven flow (polling): the backend sends
    ///   `{"choices": ["A", "B", "C"]}`, normalized into this array.
    /// - Direct callers may also pass an array of labels.
    public let choices: [String]?

    /// Legacy key-value options for chip-type prompts. When `choices` is set
    /// it takes precedence; this map is kept for backwards compatibility with
    /// callers that bind a stable analytics key to a display label.
    public let options: [String: String]?

    /// An optional trigger identifier (e.g., "post_purchase").
    public let trigger: String?

    /// Server-driven fatigue cap. When set, overrides the SDK's conservative
    /// default of 2 prompts per ISO week (matches the `maxPerWeek` field of
    /// `feedback.prompt_configs`).
    public let maxPerWeek: Int?

    /// Optional metadata attached to the response.
    public let metadata: [String: Any]?

    public init(
        promptType: FeedbackPromptType,
        question: String,
        choices: [String]? = nil,
        options: [String: String]? = nil,
        trigger: String? = nil,
        maxPerWeek: Int? = nil,
        metadata: [String: Any]? = nil
    ) {
        self.promptType = promptType
        self.question = question
        self.choices = choices
        self.options = options
        self.trigger = trigger
        self.maxPerWeek = maxPerWeek
        self.metadata = metadata
    }
}

// MARK: - Survey Config

/// Configuration for a multi-step survey.
public struct SurveyConfig {

    /// Server-side survey identifier.
    public let id: String

    /// Title displayed at the top of the survey.
    public let title: String

    /// Ordered list of survey steps.
    public let steps: [SurveyStep]

    public init(id: String, title: String, steps: [SurveyStep]) {
        self.id = id
        self.title = title
        self.steps = steps
    }
}

// MARK: - Survey Step

/// A single step within a multi-step survey.
public struct SurveyStep {

    /// Server-side step / prompt config identifier.
    public let id: String

    /// The type of prompt to render for this step.
    public let promptType: FeedbackPromptType

    /// The question to display.
    public let question: String

    /// Key-value options for chip-type prompts.
    public let options: [String: String]?

    /// 0-based ordering within the survey.
    public let stepOrder: Int

    /// Whether this step requires an answer before advancing.
    public let isRequired: Bool

    public init(
        id: String,
        promptType: FeedbackPromptType,
        question: String,
        options: [String: String]? = nil,
        stepOrder: Int,
        isRequired: Bool = true
    ) {
        self.id = id
        self.promptType = promptType
        self.question = question
        self.options = options
        self.stepOrder = stepOrder
        self.isRequired = isRequired
    }
}
