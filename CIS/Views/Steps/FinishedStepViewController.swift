//
//  FinishedStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit

internal final class FinishedStepViewController: WizardStepViewController {
    internal var runOptionChecked: ((Bool) -> Void)?

    // MARK: Views

    internal let runCheckbox: NSButton = {
        let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        return checkbox
    }()

    // MARK: Setup

    internal override init(dmg: DMG) {
        super.init(dmg: dmg)

        self.titleLabel.stringValue = .l(.finishedTitle(appName: dmg.name))
        self.descriptionLabel.stringValue = .l(.finishedDescription(
            appName: dmg.name,
            model: ProcessInfo.processInfo.marketingModel
        ))

        self.runCheckbox.title = .l(.finishedOptionRun(appName: dmg.name))
        self.runCheckbox.state = .off
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(runCheckbox)

        NSLayoutConstraint.activate([
            runCheckbox.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 20),
            runCheckbox.leadingAnchor.constraint(equalTo: descriptionLabel.leadingAnchor)
        ])

        runCheckbox.target = self
        runCheckbox.action = #selector(runCheckboxTapped)
    }

    // the `actionCheckbox` value should match the default value in
    // InstallerViewController()
    @objc private func runCheckboxTapped(_ sender: NSButton) {
        let isChecked = (sender.state == .on)
        runOptionChecked?(isChecked)
    }
}
