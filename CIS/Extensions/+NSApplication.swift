//
//  +NSApplication.swift
//  CIS
//
//  Created by samsam on 11/15/26.
//

internal import AppKit

extension NSApplication {
    /// Sets mini icon image on the bottom right at runtime.
    internal func setApplicationIconBadgeImage(with subIcon: NSImage) {
        guard let baseImage = NSApp.applicationIconImage else {
            return
        }

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
        self.applicationIconImage = combinedImage
    }
}
