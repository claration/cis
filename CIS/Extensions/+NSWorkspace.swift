//
//  +NSWorkspace.swift
//  CIS
//
//  Created by samsam on 11/12/26.
//

internal import AppKit
internal import struct UniformTypeIdentifiers.UTType
internal import class DMG.DMGNode

extension NSWorkspace {
    /// Launches installed DMG nodes.
    internal static func launchNode(
        _ node: DMGNode,
        parentPath: URL
    ) {
        let appPath = parentPath.appending(path: node.name)
        print(appPath)

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.hides = false

        Self.shared.openApplication(at: appPath, configuration: config) { app, error in
            if let error {
                NSAlert.showAlert(
                    title: "Failed to Launch App",
                    message: error.localizedDescription,
                    style: .warning
                )
            }
        }
    }

    internal static func setDefaultFileForApplication(
        url appURL: URL,
        toOpen contentType: UTType
    ) {
        Self.shared.setDefaultApplication(at: appURL, toOpen: contentType) { error in
            if let error = error {
                NSAlert.showAlert(
                    title: "Failed to Set Default Application",
                    message: error.localizedDescription,
                    style: .warning
                )
                return
            }

            if let appURL = appURL as CFURL? {
                // forces launch services to recheck us
                LSRegisterURL(appURL, true)
            }

            NSAlert.showAlert(
                title: "Successfully Set Default Application",
                message: "You can now use \(Bundle.main.name) to install applications instead of Disk Image Mounter.",
                style: .informational
            )
        }
    }
}
