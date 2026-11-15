//
//  +NSImage+Colors.swift
//  CIS
//
//  Created by samsam on 11/15/26.
//

internal import class AppKit.NSImage
internal import class AppKit.NSColor
internal import class ColorCube.CCColorCube

extension NSImage {
    internal var primaryColor: NSColor? {
        CCColorCube().extractColors(
            from: self,
            flags: [.orderByBrightness, .onlyDarkColors]
        )?.first
    }
}
