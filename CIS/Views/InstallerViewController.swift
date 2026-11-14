//
//  InstallerViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit

internal final class InstallerViewController: NSViewController {
    internal var dmg: DMG

    private var currentStepIndex = 0
    private var launchAppsWhenFinished = false

    private enum InstallerStep {
        case welcome
        case license
        case apps
        case location
        case installing
        case finished
    }

    private lazy var steps: [InstallerStep] = {
        var list: [InstallerStep] = [.welcome]
        if !dmg.licenses.isEmpty {
            list.append(.license)
        }
        list.append(contentsOf: [.apps, .location, .installing, .finished])
        return list
    }()

    // MARK: Views

    private let containerView: NSView = {
        let view = NSView()
        return view
    }()

    private let bottomBarStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        return stack
    }()

    private let separatorLine: NSBox = {
        let box = NSBox()
        box.boxType = .separator
        return box
    }()

    private let versionLabel: NSTextField = {
        // this is a good name
        let label = NSTextField(labelWithString: "Claration Install System v\(Bundle.main.version)")
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }()

    private let cancelButton: NSButton = {
        let button = NSButton(title: .l(.cancel), target: nil, action: #selector(cancelClicked))
        button.bezelStyle = .rounded
        return button
    }()

    private let backButton: NSButton = {
        let button = NSButton(title: .l(.back), target: nil, action: #selector(backClicked))
        button.bezelStyle = .rounded
        return button
    }()

    private let nextButton: NSButton = {
        let button = NSButton(title: .l(.next), target: nil, action: #selector(nextClicked))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        return button
    }()

    private var currentContentVC: NSViewController?

    private lazy var separatorLeadingToView = separatorLine.leadingAnchor.constraint(equalTo: view.leadingAnchor)
    private lazy var separatorLeadingToLabel = separatorLine.leadingAnchor.constraint(equalTo: versionLabel.trailingAnchor, constant: 12)

    // MARK: Setup

    internal init(dmg: DMG) {
        self.dmg = dmg
        super.init(nibName: nil, bundle: nil)
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func loadView() {
        self.view = NSView(frame: AppDelegate.frame)
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        [containerView, separatorLine, bottomBarStack, versionLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        [backButton, nextButton, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.widthAnchor.constraint(equalToConstant: 70).isActive = true
            bottomBarStack.addArrangedSubview($0)
            $0.target = self
        }

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: separatorLine.topAnchor),

            separatorLine.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: bottomBarStack.topAnchor, constant: -16),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),

            versionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            versionLabel.centerYAnchor.constraint(equalTo: separatorLine.centerYAnchor),

            bottomBarStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            bottomBarStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            bottomBarStack.heightAnchor.constraint(equalToConstant: 20)
        ])

        loadStep(at: 0)
    }

    @MainActor private func loadStep(at index: Int) {
        currentStepIndex = index

        backButton.isHidden = (index == 0)
        backButton.isEnabled = true
        nextButton.isEnabled = true
        cancelButton.isEnabled = true

        let step = steps[index]
        let newVC: NSViewController

        if step == .welcome || step == .finished {
            versionLabel.isHidden = true
            separatorLeadingToLabel.isActive = false
            separatorLeadingToView.isActive = true
        } else {
            versionLabel.isHidden = false
            separatorLeadingToView.isActive = false
            separatorLeadingToLabel.isActive = true
        }

        switch step {
        case .welcome:
            newVC = WelcomeStepViewController(dmg: dmg)
            nextButton.title = .l(.next)
        case .license:
            newVC = LicenseStepViewController(dmg: dmg)
            nextButton.title = .l(.iAgree)
        case .apps:
            let appPickerVC = AppPickerStepViewController(dmg: dmg)
            // Update Next button state whenever checkboxes are toggled
            appPickerVC.onSelectionChanged = { [weak self] in
                guard let self = self else { return }
                self.nextButton.isEnabled = !self.dmg.nodesToInstall.isEmpty
            }
            newVC = appPickerVC
            nextButton.title = .l(.next)
            // Initial check when loading the apps step
            nextButton.isEnabled = !dmg.nodesToInstall.isEmpty
        case .location:
            newVC = LocationStepViewController(dmg: dmg)
            nextButton.title = .l(.install)
        case .installing:
            let installVC = InstallingStepViewController(dmg: dmg)
            installVC.onCompletion = { [weak self] in
                self?.nextButton.isEnabled = true
            }
            installVC.startInstallation()
            newVC = installVC
            backButton.isEnabled = false
            nextButton.isEnabled = false
            cancelButton.isEnabled = false
            nextButton.title = .l(.next)
        case .finished:
            let finishedVC = FinishedStepViewController(dmg: dmg)
            finishedVC.runOptionChecked = { isChecked in
                self.launchAppsWhenFinished = isChecked
            }
            newVC = finishedVC
            backButton.isEnabled = false
            cancelButton.isEnabled = false
            nextButton.title = .l(.finish)
        }

        switchContent(to: newVC)
    }

    private func switchContent(to newVC: NSViewController) {
        if let oldVC = currentContentVC {
            oldVC.view.removeFromSuperview()
            oldVC.removeFromParent()
        }

        addChild(newVC)
        containerView.addSubview(newVC.view)
        newVC.view.frame = containerView.bounds
        newVC.view.autoresizingMask = [.width, .height]

        currentContentVC = newVC
    }

    @objc private func cancelClicked() {
        NSApp.terminate(nil)
    }

    @objc private func backClicked() {
        if currentStepIndex > 0 {
            loadStep(at: currentStepIndex - 1)
        }
    }

    @objc private func nextClicked() {
        if currentStepIndex == steps.count - 1 {
            // Launches all installed apps
            if launchAppsWhenFinished {
                for node in dmg.nodesToInstall {
                    NSWorkspace.launchNode(node, parentPath: dmg.destinationFolderPath)
                }
            }

            NSApp.terminate(nil)
            return
        }

        loadStep(at: currentStepIndex + 1)
    }
}
