//
//  +NSAlert.swift
//  SDII
//
//  Created by samsam on 11/12/26.
//

internal import AppKit

extension NSAlert {
    /// Helper function for alerts with optional custom buttons.
    internal static func showAlert(
        title: String,
        message: String,
        style: NSAlert.Style,
        buttonTitles: [String] = ["OK"],
        completion: ((NSApplication.ModalResponse) -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = style

            for title in buttonTitles {
                alert.addButton(withTitle: title)
            }

            let response = alert.runModal()
            completion?(response)
        }
    }
}
