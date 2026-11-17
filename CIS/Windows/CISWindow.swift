//
//  CISWindow.swift
//  CIS
//
//  Created by samsam on 11/16/26.
//

internal import AppKit

internal final class CISWindow: NSWindow {
    internal init(toolbarStyle: NSWindow.ToolbarStyle? = nil) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 0, height: 0),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        self.isReleasedWhenClosed = false

        if let style = toolbarStyle {
            self.toolbar = NSToolbar(identifier: "")
            self.toolbarStyle = style
        }
    }
}
