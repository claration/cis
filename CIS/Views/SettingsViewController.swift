//
//  SettingsViewController.swift
//  CIS
//
//  Created by samsam on 11/15/26.
//

internal import AppKit
internal import struct UniformTypeIdentifiers.UTType

internal final class SettingsViewController: NSViewController {

    // MARK: Views

    private let locationLabel = NSTextField(labelWithString: .l(.settingsDefaultLocation))

    private lazy var applicationsOption: LocationOptionButton = {
        let icon = NSWorkspace.shared.icon(forFile: "/")
        let button = LocationOptionButton(icon: icon, title: .l(.settingsDefaultLocationEveryone))
        button.onSelect = { [weak self] in
            Preferences.defaultInstallLocation = .everyone
            self?.updateLocationSelection()
        }
        return button
    }()

    private lazy var userApplicationsOption: LocationOptionButton = {
        let icon = NSWorkspace.shared.icon(forFile: "/Users")
        let button = LocationOptionButton(icon: icon, title: .l(.settingsDefaultLocationMyself))
        button.onSelect = { [weak self] in
            Preferences.defaultInstallLocation = .myself
            self?.updateLocationSelection()
        }
        return button
    }()

    private lazy var systemAppearanceCheckbox: NSButton = {
        let button = NSButton(
            checkboxWithTitle: .l(.settingsSystemAppearance),
            target: self,
            action: #selector(setSystemAppearance(_:))
        )
        button.state = Preferences.useSystemAppearence ? .on : .off
        return button
    }()

    private lazy var skipPriorStepsCheckbox: NSButton = {
        let button = NSButton(
            checkboxWithTitle: .l(.settingsSkipPriorSteps),
            target: self,
            action: #selector(setSkipPriorSteps(_:))
        )
        button.state = Preferences.skipPriorInstallerSteps ? .on : .off
        return button
    }()

    private lazy var skipFinishedStepCheckbox: NSButton = {
        let button = NSButton(
            checkboxWithTitle: .l(.settingsSkipFinishedStep),
            target: self,
            action: #selector(setSkipFinishedStep(_:))
        )
        button.state = Preferences.skipFinishedInstallerStep ? .on : .off
        return button
    }()

    private lazy var deleteCheckbox: NSButton = {
        let button = NSButton(
            checkboxWithTitle: .l(.settingsDeleteDiskAfterFinished),
            target: self,
            action: #selector(setAutomaticallyTrashDmg(_:))
        )
        button.state = Preferences.automaticallyTrashDmg ? .on : .off
        return button
    }()

    private lazy var autoMountCheckbox: NSButton = {
        let button = NSButton(
            checkboxWithTitle: .l(.settingsAutoMountDmgWithoutApps),
            target: self,
            action: #selector(setAutoMountDmgWithoutApps(_:))
        )
        button.state = Preferences.autoMountDmgWithoutApps ? .on : .off
        return button
    }()

    private let setDefaultDescription: NSTextField = {
        let baseFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let italicDescriptor = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        let font = NSFont(descriptor: italicDescriptor, size: baseFont.pointSize) ?? baseFont

        let label = NSTextField(wrappingLabelWithString: .l(.settingsSetDefaultDescription(appName: "Disk Image Mounter")))
        label.font = font
        return label
    }()

    private lazy var defaultButton = NSButton(
        title: .l(.settingsSetDefault),
        target: self,
        action: #selector(setDefaultApplication)
    )

    private lazy var installLocationStack: NSStackView = {
        let stack = NSStackView(views: [applicationsOption, userApplicationsOption])
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 12
        return stack
    }()

    private lazy var mainStack: NSStackView = {
        let stack = NSStackView(views: [
            locationLabel,
            installLocationStack,
            systemAppearanceCheckbox,
            skipPriorStepsCheckbox,
            skipFinishedStepCheckbox,
            deleteCheckbox,
            autoMountCheckbox,
            defaultButton,
            setDefaultDescription
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: Setup

    internal override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 266))
    }

    internal override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),

            installLocationStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])

        updateLocationSelection()
    }
}

extension SettingsViewController {

    // MARK: Actions

    @objc private func setSystemAppearance(_ sender: NSButton) {
        Preferences.useSystemAppearence = (sender.state == .on)
    }

    @objc private func setSkipPriorSteps(_ sender: NSButton) {
        Preferences.skipPriorInstallerSteps = (sender.state == .on)
    }

    @objc private func setSkipFinishedStep(_ sender: NSButton) {
        Preferences.skipFinishedInstallerStep = (sender.state == .on)
    }

    private func updateLocationSelection() {
        let isEveryone = (Preferences.defaultInstallLocation == .everyone)
        applicationsOption.isSelected = isEveryone
        userApplicationsOption.isSelected = !isEveryone
    }

    @objc private func setAutomaticallyTrashDmg(_ sender: NSButton) {
        Preferences.automaticallyTrashDmg = (sender.state == .on)
    }

    @objc private func setAutoMountDmgWithoutApps(_ sender: NSButton) {
        Preferences.autoMountDmgWithoutApps = (sender.state == .on)
    }

    @objc private func setDefaultApplication() {
        NSWorkspace.setDefaultFileForApplication(
            url: Bundle.main.bundleURL,
            toOpen: UTType(filenameExtension: "dmg")!
        )
    }
}
