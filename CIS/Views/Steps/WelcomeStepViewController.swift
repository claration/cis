//
//  WelcomeStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import AppKit

internal final class WelcomeStepViewController: WizardStepViewController {

    // MARK: Setup

    internal override init(dmg: DMG) {
        super.init(dmg: dmg)

        self.titleLabel.stringValue = .l(.welcomeTitle(appName: dmg.name))
        self.descriptionLabel.stringValue = .l(.welcomeDescription(
            appName: dmg.name,
            model: ProcessInfo.processInfo.marketingModel
        ))
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
