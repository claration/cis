//
//  AppPickerStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit
internal import class DMG.DMGNode

private final class FlippedView: NSView {
    override var isFlipped: Bool { return true }
}

internal final class AppPickerStepViewController: BannerStepViewController {
    internal var onSelectionChanged: (() -> Void)?

    // MARK: Views

    private let topMessageLabel: NSTextField = {
        let label = NSTextField(wrappingLabelWithString: "Select the applications you would like to install to your \(ProcessInfo.processInfo.marketingModel).")
        label.font = NSFont.systemFont(ofSize: 13)
        return label
    }()

    private let scrollView: NSScrollView = {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.scrollerStyle = .legacy
        return scroll
    }()

    private let containerView: FlippedView = {
        let view = FlippedView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let stackView: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var checkboxes: [NSButton] = []
    private var availableNodes: [DMGNode] = []

    // MARK: Setup

    internal override init(dmg: DMG) {
        super.init(dmg: dmg)

        self.headerView.titleLabel.stringValue = "Pick Applications"
        self.headerView.descriptionLabel.stringValue = "Please pick the applications that you would like to install."
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        scrollView.documentView = containerView
        containerView.addSubview(stackView)

        [topMessageLabel, scrollView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            topMessageLabel.topAnchor.constraint(equalTo: headerViewSeperatorBox.bottomAnchor, constant: 16),
            topMessageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            topMessageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            scrollView.topAnchor.constraint(equalTo: topMessageLabel.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),

            containerView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: containerView.bottomAnchor, constant: -12)
        ])
    }

    internal override func viewWillAppear() {
        super.viewWillAppear()

        do {
            availableNodes = try dmg.lookup()
            populateCheckboxes()
        } catch {
            topMessageLabel.stringValue = "Failed to load applications: \(error.localizedDescription)"
        }
    }

    private func populateCheckboxes() {
        checkboxes.forEach { $0.removeFromSuperview() }
        checkboxes.removeAll()

        for (index, node) in availableNodes.enumerated() {
            let checkbox = NSButton(checkboxWithTitle: node.name, target: self, action: #selector(checkboxToggled(_:)))

            let isSelected = dmg.nodesToInstall.contains(where: { $0.name == node.name })
            checkbox.state = isSelected ? .on : .off

            checkbox.tag = index
            stackView.addArrangedSubview(checkbox)
            checkboxes.append(checkbox)
        }
    }

    @objc private func checkboxToggled(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < availableNodes.count else {
            return
        }

        let node = availableNodes[index]
        if sender.state == .on {
            if !dmg.nodesToInstall.contains(where: { $0.name == node.name }) {
                dmg.nodesToInstall.append(node)
            }
        } else {
            dmg.nodesToInstall.removeAll(where: { $0.name == node.name })
        }

        onSelectionChanged?()
    }
}
