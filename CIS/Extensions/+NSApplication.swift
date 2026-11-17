//
//  +NSApplication.swift
//  CIS
//
//  Created by samsam on 11/15/26.
//

internal import AppKit

extension NSApplication {

    /// Generates a new icon using our current icon with a custom "badge" on the bottom right.
    internal func genApplicationIconBadgeImage(with subIcon: NSImage) -> NSImage {
        let baseImage = NSApp.applicationIconImage!

        let size = baseImage.size
        let combinedImage = NSImage(size: size)

        combinedImage.lockFocus()

        baseImage.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        let subIconSize = size.width * 0.4
        let padding: CGFloat = size.width * 0

        let subIconRect = NSRect(
            x: size.width - subIconSize - padding,
            y: padding,
            width: subIconSize,
            height: subIconSize
        )

        subIcon.draw(
            in: subIconRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        combinedImage.unlockFocus()
        return combinedImage
    }
}
