//
//  FinishedStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit

internal final class FinishedStepViewController: WizardStepViewController {
    internal var runOptionChecked: ((Bool) -> Void)?
    internal var deleteOptionChecked: ((Bool) -> Void)?

    // MARK: Views

    internal let runCheckbox: NSButton = {
        let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        return checkbox
    }()

    internal let deleteCheckbox: NSButton = {
        let checkbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
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
        self.deleteCheckbox.title = .l(.finishedDeleteDiskImage(pathName: dmg.path.lastPathComponent))
        self.runCheckbox.state = .off
        self.deleteCheckbox.state = .on
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()

        [runCheckbox, deleteCheckbox].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
            $0.target = self
        }

        NSLayoutConstraint.activate([
            runCheckbox.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 20),
            runCheckbox.leadingAnchor.constraint(equalTo: descriptionLabel.leadingAnchor),
            deleteCheckbox.topAnchor.constraint(equalTo: runCheckbox.bottomAnchor, constant: 10),
            deleteCheckbox.leadingAnchor.constraint(equalTo: descriptionLabel.leadingAnchor)
        ])

        runCheckbox.action = #selector(runCheckboxTapped)
        deleteCheckbox.action = #selector(deleteCheckboxTapped)
    }

    // the `runCheckbox` value should match the default value in
    // InstallerViewController()
    @objc private func runCheckboxTapped(_ sender: NSButton) {
        let isChecked = (sender.state == .on)
        runOptionChecked?(isChecked)
    }

    // the `deleteCheckbox` value should match the default value in
    // InstallerViewController()
    @objc private func deleteCheckboxTapped(_ sender: NSButton) {
        let isChecked = (sender.state == .on)
        deleteOptionChecked?(isChecked)
    }
}
