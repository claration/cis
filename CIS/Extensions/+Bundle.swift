//
//  +Bundle.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

internal import class Foundation.Bundle

extension Bundle {
    /// The bundle's display name.
    internal var name: String {
        if
            let displayName = object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            !displayName.isEmpty
        {
            return displayName
        }

        if
            let name = object(forInfoDictionaryKey: "CFBundleName") as? String,
            !name.isEmpty
        {
            return name
        }

        return object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? ""
    }

    /// The bundle's  version.
    internal var version: String {
        if let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }

        return object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }
}
