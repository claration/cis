//
//  +String.swift
//  CIS
//
//  Created by samsam on 11/13/26.
//

import struct Foundation.LocalizedStringResource

extension String {
    /// Helper static function for locatizations.
    static func l(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }
}

extension String {
    /// Helper for making names safe for the disk.
    internal func diskSafeName() throws -> String {
        let cleaned = replacingOccurrences(of: "/", with: ":")
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." || cleaned.contains("\0") {
            throw DMGError.unsafeName(self)
        }

        return cleaned
    }
}
