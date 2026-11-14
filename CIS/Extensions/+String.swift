//
//  +String.swift
//  CIS
//
//  Created by samsam on 11/13/26.
//

import struct Foundation.LocalizedStringResource

extension String {
    /// Helper static function for locatizations
    static func l(_ resource: LocalizedStringResource) -> String {
        String(localized: resource)
    }
}
