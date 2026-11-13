//
//  WelcomeStepViewController.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

import AppKit

internal final class WelcomeStepViewController: WizardStepViewController {

    // MARK: Setup

    internal override init(dmg: DMG) {
        super.init(dmg: dmg)

        self.titleLabel.stringValue = "Welcome to \(dmg.name) Setup"
        self.descriptionLabel.stringValue = """
        Setup will guide you through the installation process of \(dmg.name).

        It is recommended you close all other applications before starting Setup. This will make it possible to update relevant system files without having to reboot your \(ProcessInfo.processInfo.marketingModel).

        Click Next to continue.
        """
    }

    internal required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
