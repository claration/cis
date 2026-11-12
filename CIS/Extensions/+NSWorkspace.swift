//
//  +NSWorkspace.swift
//  CIS
//
//  Created by samsam on 11/12/26.
//

import AppKit
import DMG

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

        NSWorkspace.shared.openApplication(at: appPath, configuration: config) { app, error in
            if let error {
                NSAlert.showAlert(
                    title: "Failed to Launch App",
                    message: error.localizedDescription,
                    style: .warning
                )
            }
        }
    }
}
