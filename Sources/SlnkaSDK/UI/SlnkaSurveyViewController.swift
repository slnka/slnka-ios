#if canImport(UIKit)
import UIKit

/// Displays a multi-step survey as a bottom sheet.
///
/// Each step renders the appropriate prompt type (NPS, CSAT, etc.) and
/// auto-advances after selection. Navigation buttons allow going back.
/// All UI is built programmatically — no storyboards, no xibs, no SwiftUI.
public class SlnkaSurveyViewController: UIViewController {

    // MARK: - Properties

    private let config: SurveyConfig
    private var currentStep: Int = 0
    private var surveyResponseId: String?

    /// Called internally by SlnkaSDK to wire up the FeedbackManager.
    internal var onStepAnswer: ((String, String, String, Any) -> Void)?
    internal var onSurveyComplete: ((String) -> Void)?
    internal var onSurveyStart: ((String) async -> String?)?

    private let accentColor = SlnkaFeedbackViewController.accentColor

    // MARK: - UI Elements

    private let containerView = UIView()
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let stepIndicatorLabel = UILabel()
    private let questionLabel = UILabel()
    private let inputContainer = UIView()
    private let navigationContainer = UIView()
    private let backButton = UIButton(type: .system)
    private let nextButton = UIButton(type: .system)
    private let thankYouLabel = UILabel()

    private var currentInputView: UIView?

    // MARK: - Init

    public init(config: SurveyConfig) {
        self.config = config
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        renderStep()
        startSurveyIfNeeded()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            containerView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        setupCloseButton()
        setupTitleLabel()
        setupProgressView()
        setupStepIndicator()
        setupQuestionLabel()
        setupInputContainer()
        setupNavigationButtons()
        setupThankYouLabel()
    }

    private func setupCloseButton() {
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setTitle("\u{2715}", for: .normal)
        closeButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        closeButton.tintColor = .secondaryLabel
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        containerView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: containerView.topAnchor),
            closeButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func setupTitleLabel() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = config.title
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0
        containerView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40)
        ])
    }

    private func setupProgressView() {
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = accentColor
        progressView.trackTintColor = accentColor.withAlphaComponent(0.15)
        containerView.addSubview(progressView)

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            progressView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 4)
        ])
    }

    private func setupStepIndicator() {
        stepIndicatorLabel.translatesAutoresizingMaskIntoConstraints = false
        stepIndicatorLabel.font = .systemFont(ofSize: 12, weight: .regular)
        stepIndicatorLabel.textColor = .secondaryLabel
        containerView.addSubview(stepIndicatorLabel)

        NSLayoutConstraint.activate([
            stepIndicatorLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 8),
            stepIndicatorLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor)
        ])
    }

    private func setupQuestionLabel() {
        questionLabel.translatesAutoresizingMaskIntoConstraints = false
        questionLabel.font = .systemFont(ofSize: 17, weight: .bold)
        questionLabel.textColor = .label
        questionLabel.numberOfLines = 0
        containerView.addSubview(questionLabel)

        NSLayoutConstraint.activate([
            questionLabel.topAnchor.constraint(equalTo: stepIndicatorLabel.bottomAnchor, constant: 12),
            questionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            questionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
    }

    private func setupInputContainer() {
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(inputContainer)

        NSLayoutConstraint.activate([
            inputContainer.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 20),
            inputContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
    }

    private func setupNavigationButtons() {
        navigationContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(navigationContainer)

        NSLayoutConstraint.activate([
            navigationContainer.topAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: 20),
            navigationContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            navigationContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            navigationContainer.heightAnchor.constraint(equalToConstant: 44),
            navigationContainer.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.setTitle("Back", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        backButton.tintColor = .secondaryLabel
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        navigationContainer.addSubview(backButton)

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        nextButton.backgroundColor = accentColor
        nextButton.setTitleColor(.white, for: .normal)
        nextButton.layer.cornerRadius = 10
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        navigationContainer.addSubview(nextButton)

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: navigationContainer.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: navigationContainer.centerYAnchor),

            nextButton.trailingAnchor.constraint(equalTo: navigationContainer.trailingAnchor),
            nextButton.centerYAnchor.constraint(equalTo: navigationContainer.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 100),
            nextButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func setupThankYouLabel() {
        thankYouLabel.translatesAutoresizingMaskIntoConstraints = false
        thankYouLabel.text = "Thank you!"
        thankYouLabel.font = .systemFont(ofSize: 22, weight: .bold)
        thankYouLabel.textColor = accentColor
        thankYouLabel.textAlignment = .center
        thankYouLabel.alpha = 0
        thankYouLabel.isHidden = true
        containerView.addSubview(thankYouLabel)

        NSLayoutConstraint.activate([
            thankYouLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            thankYouLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 60)
        ])
    }

    // MARK: - Step Rendering

    private func renderStep() {
        guard currentStep < config.steps.count else { return }

        let step = config.steps[currentStep]
        let total = config.steps.count

        // Update progress
        progressView.setProgress(Float(currentStep + 1) / Float(total), animated: true)
        stepIndicatorLabel.text = "Step \(currentStep + 1) of \(total)"
        questionLabel.text = step.question

        // Update navigation
        backButton.isHidden = currentStep == 0
        let isLast = currentStep == total - 1
        nextButton.setTitle(isLast ? "Submit" : "Next", for: .normal)
        // Disable next until a selection is made (except for open text which uses submit)
        nextButton.isHidden = step.promptType != .open
        selectedStepValue = nil

        // Replace input view
        currentInputView?.removeFromSuperview()
        let inputView = SlnkaFeedbackViewController.buildInputView(
            promptType: step.promptType,
            options: step.options,
            target: self,
            action: #selector(stepInputTapped(_:))
        )
        inputContainer.addSubview(inputView)

        NSLayoutConstraint.activate([
            inputView.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            inputView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            inputView.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            inputView.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor)
        ])

        currentInputView = inputView
    }

    /// The value selected for the current step.
    private var selectedStepValue: Any?

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func backTapped() {
        guard currentStep > 0 else { return }
        currentStep -= 1
        renderStep()
    }

    @objc private func nextTapped() {
        // For open text, grab value from text view
        if config.steps[currentStep].promptType == .open {
            if let tv = currentInputView?.viewWithTag(9000) as? UITextView {
                let text = tv.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !text.isEmpty else { return }
                selectedStepValue = text
            }
        }

        guard let value = selectedStepValue else { return }
        submitCurrentStep(value: value)
    }

    @objc private func stepInputTapped(_ sender: UIButton) {
        let step = config.steps[currentStep]
        var value: Any

        switch step.promptType {
        case .nps, .ces:
            highlightSelectedButton(sender)
            value = sender.tag
        case .csat:
            highlightStars(upTo: sender.tag, in: sender.superview)
            value = sender.tag
        case .emoji:
            highlightSelectedButton(sender)
            value = sender.tag
        case .thumbs:
            highlightSelectedButton(sender)
            value = sender.tag == 1
        case .open:
            // Submit button tapped
            if sender.tag == 9001 {
                if let tv = currentInputView?.viewWithTag(9000) as? UITextView {
                    let text = tv.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !text.isEmpty else { return }
                    value = text
                } else {
                    return
                }
            } else {
                return
            }
        case .chips:
            highlightSelectedChip(sender)
            value = sender.accessibilityIdentifier ?? sender.titleLabel?.text ?? ""
        }

        selectedStepValue = value

        // Auto-advance after a short delay (except for open text which has explicit submit)
        if step.promptType != .open {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.submitCurrentStep(value: value)
            }
        }
    }

    // MARK: - Step Submission

    private func submitCurrentStep(value: Any) {
        let step = config.steps[currentStep]

        // Submit the answer via callback
        if let responseId = surveyResponseId {
            onStepAnswer?(responseId, step.id, step.promptType.rawValue, value)
        }

        let isLast = currentStep == config.steps.count - 1

        if isLast {
            // Complete survey
            if let responseId = surveyResponseId {
                onSurveyComplete?(responseId)
            }
            showThankYou()
        } else {
            currentStep += 1
            renderStep()
        }
    }

    // MARK: - Thank You

    private func showThankYou() {
        titleLabel.isHidden = true
        progressView.isHidden = true
        stepIndicatorLabel.isHidden = true
        questionLabel.isHidden = true
        inputContainer.isHidden = true
        navigationContainer.isHidden = true
        thankYouLabel.isHidden = false

        UIView.animate(withDuration: 0.3) {
            self.thankYouLabel.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    // MARK: - Survey Start

    private func startSurveyIfNeeded() {
        Task { [weak self] in
            guard let self = self else { return }
            let responseId = await self.onSurveyStart?(self.config.id)
            await MainActor.run {
                self.surveyResponseId = responseId
            }
        }
    }

    // MARK: - Highlight Helpers

    private func highlightSelectedButton(_ selected: UIButton) {
        guard let parent = selected.superview else { return }
        for case let btn as UIButton in allButtons(in: parent) {
            if btn === selected {
                btn.backgroundColor = SlnkaFeedbackViewController.accentColor
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = SlnkaFeedbackViewController.accentColor.withAlphaComponent(0.1)
                btn.setTitleColor(SlnkaFeedbackViewController.accentColor, for: .normal)
            }
        }
    }

    private func highlightStars(upTo rating: Int, in parent: UIView?) {
        guard let stack = parent as? UIStackView else { return }
        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        for case let btn as UIButton in stack.arrangedSubviews {
            let filled = btn.tag <= rating
            let name = filled ? "star.fill" : "star"
            btn.setImage(UIImage(systemName: name, withConfiguration: symbolConfig), for: .normal)
            btn.tintColor = filled ? SlnkaFeedbackViewController.accentColor : .tertiaryLabel
        }
    }

    private func highlightSelectedChip(_ selected: UIButton) {
        // Walk up to find the outer vertical stack
        var outerStack: UIStackView?
        var current: UIView? = selected.superview
        while let v = current, v !== inputContainer {
            if let sv = v as? UIStackView, sv.axis == .vertical {
                outerStack = sv
                break
            }
            current = v.superview
        }
        guard let stack = outerStack else { return }

        for case let row as UIStackView in stack.arrangedSubviews {
            for case let btn as UIButton in row.arrangedSubviews {
                if btn === selected {
                    btn.backgroundColor = SlnkaFeedbackViewController.accentColor
                    btn.setTitleColor(.white, for: .normal)
                } else {
                    btn.backgroundColor = SlnkaFeedbackViewController.accentColor.withAlphaComponent(0.1)
                    btn.setTitleColor(SlnkaFeedbackViewController.accentColor, for: .normal)
                }
            }
        }
    }

    private func allButtons(in view: UIView) -> [UIButton] {
        var buttons: [UIButton] = []
        for subview in view.subviews {
            if let btn = subview as? UIButton {
                buttons.append(btn)
            }
            buttons.append(contentsOf: allButtons(in: subview))
        }
        return buttons
    }
}
#endif
