//
//  FinishedStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit

internal final class FinishedStepViewController: WizardStepViewController {
    internal var onOptionChecked: ((Bool) -> Void)?

    // MARK: Views

    internal let actionCheckbox: NSButton = {
        let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        return checkbox
    }()

    // MARK: Setup

    internal override init(dmg: DMG) {
        super.init(dmg: dmg)

        self.titleLabel.stringValue = "Completing \(dmg.name) Setup"
        self.descriptionLabel.stringValue = """
        \(dmg.name) has been installed on your \(ProcessInfo.processInfo.marketingModel).

        Click Finish to close Setup.
        """

        self.actionCheckbox.title = "Run \(dmg.name)"
        self.actionCheckbox.state = .off
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(actionCheckbox)

        NSLayoutConstraint.activate([
            actionCheckbox.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 20),
            actionCheckbox.leadingAnchor.constraint(equalTo: descriptionLabel.leadingAnchor)
        ])

        actionCheckbox.target = self
        actionCheckbox.action = #selector(handleCheckboxTapped)
    }

    // the `actionCheckbox` value should match the default value in
    // InstallerViewController()
    @objc private func handleCheckboxTapped(_ sender: NSButton) {
        let isChecked = (sender.state == .on)
        onOptionChecked?(isChecked)
    }
}
