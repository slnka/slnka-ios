#if canImport(UIKit)
import UIKit

/// Displays a single feedback prompt as a bottom sheet.
///
/// Supports NPS, CSAT, CES, emoji, thumbs, open text, and chips prompt types.
/// All UI is built programmatically — no storyboards, no xibs, no SwiftUI.
public class SlnkaFeedbackViewController: UIViewController {

    // MARK: - Properties

    private let options: FeedbackShowOptions
    private var onSubmit: ((Any) -> Void)?

    /// SLNK accent color (#7c3aed)
    static let accentColor = UIColor(red: 0.486, green: 0.227, blue: 0.929, alpha: 1)

    // MARK: - UI Elements

    private let containerView = UIView()
    private let closeButton = UIButton(type: .system)
    private let questionLabel = UILabel()
    private let inputContainer = UIView()

    // Open text
    private let textView = UITextView()
    private let submitButton = UIButton(type: .system)

    // Thank you
    private let thankYouLabel = UILabel()

    /// Tracks the selected value for all prompt types.
    private var selectedValue: Any?

    // MARK: - Init

    public init(options: FeedbackShowOptions, onSubmit: ((Any) -> Void)? = nil) {
        self.options = options
        self.onSubmit = onSubmit
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberHandle = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupContainer()
        setupCloseButton()
        setupQuestionLabel()
        setupInputArea()
        setupThankYouLabel()
    }

    // MARK: - Layout

    private func setupContainer() {
        view.backgroundColor = .systemBackground

        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            containerView.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
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

    private func setupQuestionLabel() {
        questionLabel.translatesAutoresizingMaskIntoConstraints = false
        questionLabel.text = options.question
        questionLabel.font = .systemFont(ofSize: 17, weight: .bold)
        questionLabel.textColor = .label
        questionLabel.numberOfLines = 0
        containerView.addSubview(questionLabel)

        NSLayoutConstraint.activate([
            questionLabel.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            questionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            questionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -40)
        ])
    }

    private func setupInputArea() {
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(inputContainer)

        NSLayoutConstraint.activate([
            inputContainer.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 24),
            inputContainer.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])

        switch options.promptType {
        case .nps:
            buildNumberedButtons(range: 0...10)
        case .csat:
            buildStarButtons(count: 5)
        case .ces:
            buildNumberedButtons(range: 1...7)
        case .emoji:
            buildEmojiButtons()
        case .thumbs:
            buildThumbsButtons()
        case .open:
            buildOpenText()
        case .chips:
            buildChipsButtons()
        }
    }

    private func setupThankYouLabel() {
        thankYouLabel.translatesAutoresizingMaskIntoConstraints = false
        thankYouLabel.text = "Thank you!"
        thankYouLabel.font = .systemFont(ofSize: 22, weight: .bold)
        thankYouLabel.textColor = Self.accentColor
        thankYouLabel.textAlignment = .center
        thankYouLabel.alpha = 0
        thankYouLabel.isHidden = true
        containerView.addSubview(thankYouLabel)

        NSLayoutConstraint.activate([
            thankYouLabel.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            thankYouLabel.topAnchor.constraint(equalTo: questionLabel.bottomAnchor, constant: 40)
        ])
    }

    // MARK: - Input Builders

    /// Builds a horizontal scroll of numbered pill buttons (NPS 0-10, CES 1-7).
    private func buildNumberedButtons(range: ClosedRange<Int>) {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        inputContainer.addSubview(scrollView)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 48),
            scrollView.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])

        for i in range {
            let button = makePillButton(title: "\(i)", tag: i)
            button.addTarget(self, action: #selector(numberedButtonTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    /// Builds 5 star buttons (CSAT).
    private func buildStarButtons(count: Int) {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.distribution = .fillEqually
        inputContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            stack.centerXAnchor.constraint(equalTo: inputContainer.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: 48)
        ])

        for i in 1...count {
            let button = UIButton(type: .system)
            button.tag = i
            let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)
            button.setImage(UIImage(systemName: "star", withConfiguration: config), for: .normal)
            button.tintColor = .tertiaryLabel
            button.addTarget(self, action: #selector(starButtonTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    /// Builds 5 emoji labels as tappable buttons.
    private func buildEmojiButtons() {
        let emojis = ["\u{1F621}", "\u{1F61F}", "\u{1F610}", "\u{1F642}", "\u{1F60D}"]
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 16
        stack.alignment = .center
        stack.distribution = .fillEqually
        inputContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            stack.centerXAnchor.constraint(equalTo: inputContainer.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: 56)
        ])

        for (index, emoji) in emojis.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index + 1
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 36)
            button.addTarget(self, action: #selector(emojiButtonTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    /// Builds two large thumb buttons.
    private func buildThumbsButtons() {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 32
        stack.alignment = .center
        stack.distribution = .fillEqually
        inputContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            stack.centerXAnchor.constraint(equalTo: inputContainer.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: 64)
        ])

        let thumbsUp = UIButton(type: .system)
        thumbsUp.tag = 1
        thumbsUp.setTitle("\u{1F44D}", for: .normal)
        thumbsUp.titleLabel?.font = .systemFont(ofSize: 48)
        thumbsUp.addTarget(self, action: #selector(thumbsTapped(_:)), for: .touchUpInside)
        stack.addArrangedSubview(thumbsUp)

        let thumbsDown = UIButton(type: .system)
        thumbsDown.tag = 0
        thumbsDown.setTitle("\u{1F44E}", for: .normal)
        thumbsDown.titleLabel?.font = .systemFont(ofSize: 48)
        thumbsDown.addTarget(self, action: #selector(thumbsTapped(_:)), for: .touchUpInside)
        stack.addArrangedSubview(thumbsDown)
    }

    /// Builds a text view + submit button for open text.
    private func buildOpenText() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .label
        textView.backgroundColor = .secondarySystemBackground
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        inputContainer.addSubview(textView)

        submitButton.translatesAutoresizingMaskIntoConstraints = false
        submitButton.setTitle("Submit", for: .normal)
        submitButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        submitButton.backgroundColor = Self.accentColor
        submitButton.setTitleColor(.white, for: .normal)
        submitButton.layer.cornerRadius = 10
        submitButton.addTarget(self, action: #selector(openTextSubmitTapped), for: .touchUpInside)
        inputContainer.addSubview(submitButton)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            textView.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            textView.heightAnchor.constraint(equalToConstant: 100),

            submitButton.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 12),
            submitButton.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            submitButton.widthAnchor.constraint(equalToConstant: 120),
            submitButton.heightAnchor.constraint(equalToConstant: 44),
            submitButton.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor)
        ])
    }

    /// Builds selectable chip buttons from options.
    private func buildChipsButtons() {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        inputContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: inputContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor)
        ])

        // Build horizontal rows of chips that wrap
        var currentRow = UIStackView()
        currentRow.axis = .horizontal
        currentRow.spacing = 8
        currentRow.alignment = .center
        stack.addArrangedSubview(currentRow)

        let sortedOptions = (options.options ?? [:]).sorted { $0.key < $1.key }
        for (index, entry) in sortedOptions.enumerated() {
            let chip = makeChipButton(title: entry.value, value: entry.key, tag: index)
            chip.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            currentRow.addArrangedSubview(chip)

            // Wrap every 3 chips
            if (index + 1) % 3 == 0 && index < sortedOptions.count - 1 {
                currentRow = UIStackView()
                currentRow.axis = .horizontal
                currentRow.spacing = 8
                currentRow.alignment = .center
                stack.addArrangedSubview(currentRow)
            }
        }
    }

    // MARK: - Button Factories

    private func makePillButton(title: String, tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = tag
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        button.setTitleColor(Self.accentColor, for: .normal)
        button.backgroundColor = Self.accentColor.withAlphaComponent(0.1)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
        return button
    }

    private func makeChipButton(title: String, value: String, tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.tag = tag
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = value
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.setTitleColor(Self.accentColor, for: .normal)
        button.backgroundColor = Self.accentColor.withAlphaComponent(0.1)
        button.layer.cornerRadius = 16
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        return button
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    @objc private func numberedButtonTapped(_ sender: UIButton) {
        highlightButton(sender, inParent: sender.superview)
        handleSelection(sender.tag)
    }

    @objc private func starButtonTapped(_ sender: UIButton) {
        let rating = sender.tag
        // Fill stars up to the selected one
        if let stack = sender.superview as? UIStackView {
            let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)
            for case let btn as UIButton in stack.arrangedSubviews {
                let filled = btn.tag <= rating
                let name = filled ? "star.fill" : "star"
                btn.setImage(UIImage(systemName: name, withConfiguration: config), for: .normal)
                btn.tintColor = filled ? Self.accentColor : .tertiaryLabel
            }
        }
        handleSelection(rating)
    }

    @objc private func emojiButtonTapped(_ sender: UIButton) {
        highlightButton(sender, inParent: sender.superview)
        handleSelection(sender.tag)
    }

    @objc private func thumbsTapped(_ sender: UIButton) {
        highlightButton(sender, inParent: sender.superview)
        let value = sender.tag == 1
        handleSelection(value)
    }

    @objc private func openTextSubmitTapped() {
        let text = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { return }
        handleSelection(text)
    }

    @objc private func chipTapped(_ sender: UIButton) {
        highlightButton(sender, inParent: findChipsContainer(sender))
        let value = sender.accessibilityIdentifier ?? sender.titleLabel?.text ?? ""
        handleSelection(value)
    }

    // MARK: - Selection Handling

    private func handleSelection(_ value: Any) {
        selectedValue = value
        onSubmit?(value)
        showThankYou()
    }

    private func showThankYou() {
        questionLabel.isHidden = true
        inputContainer.isHidden = true
        thankYouLabel.isHidden = false

        UIView.animate(withDuration: 0.3) {
            self.thankYouLabel.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    // MARK: - Helpers

    private func highlightButton(_ selected: UIButton, inParent parent: UIView?) {
        guard let parent = parent else { return }
        // Dim siblings, highlight selected
        for case let btn as UIButton in allButtons(in: parent) {
            if btn === selected {
                btn.backgroundColor = Self.accentColor
                btn.setTitleColor(.white, for: .normal)
            } else {
                btn.backgroundColor = Self.accentColor.withAlphaComponent(0.1)
                btn.setTitleColor(Self.accentColor, for: .normal)
            }
        }
    }

    /// Recursively finds all UIButtons in a view hierarchy.
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

    /// Walks up the view tree to find the outermost stack (chips container).
    private func findChipsContainer(_ view: UIView) -> UIView? {
        var current: UIView? = view.superview
        var lastStack: UIView? = nil
        while let v = current, v !== inputContainer {
            if v is UIStackView {
                lastStack = v
            }
            current = v.superview
        }
        return lastStack ?? view.superview
    }
}

// MARK: - Internal Helper for Building Input in Survey

extension SlnkaFeedbackViewController {

    /// Builds an input view for a given prompt type, returning it as a UIView.
    /// Used internally by `SlnkaSurveyViewController` to reuse rendering logic.
    static func buildInputView(
        promptType: FeedbackPromptType,
        options: [String: String]?,
        target: AnyObject,
        action: Selector
    ) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        switch promptType {
        case .nps:
            addNumberedButtons(to: container, range: 0...10, target: target, action: action)
        case .csat:
            addStarButtons(to: container, count: 5, target: target, action: action)
        case .ces:
            addNumberedButtons(to: container, range: 1...7, target: target, action: action)
        case .emoji:
            addEmojiButtons(to: container, target: target, action: action)
        case .thumbs:
            addThumbsButtons(to: container, target: target, action: action)
        case .open:
            addOpenText(to: container, target: target, action: action)
        case .chips:
            addChipsButtons(to: container, options: options ?? [:], target: target, action: action)
        }

        return container
    }

    private static func addNumberedButtons(to container: UIView, range: ClosedRange<Int>, target: AnyObject, action: Selector) {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        container.addSubview(scrollView)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 48),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])

        for i in range {
            let button = UIButton(type: .system)
            button.tag = i
            button.setTitle("\(i)", for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            button.setTitleColor(accentColor, for: .normal)
            button.backgroundColor = accentColor.withAlphaComponent(0.1)
            button.layer.cornerRadius = 20
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: 40),
                button.heightAnchor.constraint(equalToConstant: 40)
            ])
            button.addTarget(target, action: action, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    private static func addStarButtons(to container: UIView, count: Int, target: AnyObject, action: Selector) {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.distribution = .fillEqually
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: 48)
        ])

        let config = UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        for i in 1...count {
            let button = UIButton(type: .system)
            button.tag = i
            button.setImage(UIImage(systemName: "star", withConfiguration: config), for: .normal)
            button.tintColor = .tertiaryLabel
            button.addTarget(target, action: action, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    private static func addEmojiButtons(to container: UIView, target: AnyObject, action: Selector) {
        let emojis = ["\u{1F621}", "\u{1F61F}", "\u{1F610}", "\u{1F642}", "\u{1F60D}"]
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 16
        stack.alignment = .center
        stack.distribution = .fillEqually
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: 56)
        ])

        for (index, emoji) in emojis.enumerated() {
            let button = UIButton(type: .system)
            button.tag = index + 1
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 36)
            button.addTarget(target, action: action, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    private static func addThumbsButtons(to container: UIView, target: AnyObject, action: Selector) {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 32
        stack.alignment = .center
        stack.distribution = .fillEqually
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: 64)
        ])

        let thumbsUp = UIButton(type: .system)
        thumbsUp.tag = 1
        thumbsUp.setTitle("\u{1F44D}", for: .normal)
        thumbsUp.titleLabel?.font = .systemFont(ofSize: 48)
        thumbsUp.addTarget(target, action: action, for: .touchUpInside)
        stack.addArrangedSubview(thumbsUp)

        let thumbsDown = UIButton(type: .system)
        thumbsDown.tag = 0
        thumbsDown.setTitle("\u{1F44E}", for: .normal)
        thumbsDown.titleLabel?.font = .systemFont(ofSize: 48)
        thumbsDown.addTarget(target, action: action, for: .touchUpInside)
        stack.addArrangedSubview(thumbsDown)
    }

    private static func addOpenText(to container: UIView, target: AnyObject, action: Selector) {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.font = .systemFont(ofSize: 15)
        tv.textColor = .label
        tv.backgroundColor = .secondarySystemBackground
        tv.layer.cornerRadius = 8
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        tv.tag = 9000 // marker tag to retrieve later
        container.addSubview(tv)

        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("Submit", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        btn.backgroundColor = accentColor
        btn.setTitleColor(.white, for: .normal)
        btn.layer.cornerRadius = 10
        btn.tag = 9001 // marker tag
        btn.addTarget(target, action: action, for: .touchUpInside)
        container.addSubview(btn)

        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: container.topAnchor),
            tv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tv.heightAnchor.constraint(equalToConstant: 100),

            btn.topAnchor.constraint(equalTo: tv.bottomAnchor, constant: 12),
            btn.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            btn.widthAnchor.constraint(equalToConstant: 120),
            btn.heightAnchor.constraint(equalToConstant: 44),
            btn.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    private static func addChipsButtons(to container: UIView, options: [String: String], target: AnyObject, action: Selector) {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        var currentRow = UIStackView()
        currentRow.axis = .horizontal
        currentRow.spacing = 8
        currentRow.alignment = .center
        stack.addArrangedSubview(currentRow)

        let sorted = options.sorted { $0.key < $1.key }
        for (index, entry) in sorted.enumerated() {
            let chip = UIButton(type: .system)
            chip.tag = index
            chip.setTitle(entry.value, for: .normal)
            chip.accessibilityIdentifier = entry.key
            chip.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            chip.setTitleColor(accentColor, for: .normal)
            chip.backgroundColor = accentColor.withAlphaComponent(0.1)
            chip.layer.cornerRadius = 16
            chip.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            chip.addTarget(target, action: action, for: .touchUpInside)
            currentRow.addArrangedSubview(chip)

            if (index + 1) % 3 == 0 && index < sorted.count - 1 {
                currentRow = UIStackView()
                currentRow.axis = .horizontal
                currentRow.spacing = 8
                currentRow.alignment = .center
                stack.addArrangedSubview(currentRow)
            }
        }
    }
}
#endif
