//
//  Preferences.swift
//  CIS
//
//  Created by samsam on 11/16/26.
//

import Foundation

/// Application install location.
internal enum InstallLocation: String {
    /// `/Applications`
    case everyone
    /// `~/Applications`
    case myself
}

/// A set of user controlled preferences.
internal enum Preferences {
    /// Application install location.
    @EnumStorage(key: "on.clarati.scis.installerType", defaultValue: .everyone)
    public static var defaultInstallLocation: InstallLocation

    /// If the installer should automatically trash the DMG file afterwards.
    @Storage(key: "on.clarati.cis.useSystemAppearence", defaultValue: false)
    public static var useSystemAppearence: Bool

    /// If the installer should go to the location step.
    @Storage(key: "on.clarati.cis.skipPriorSteps", defaultValue: false)
    public static var skipPriorInstallerSteps: Bool

    /// If the installer should skip finish step.
    @Storage(key: "on.clarati.cis.skipFinishedInstallerStep", defaultValue: false)
    public static var skipFinishedInstallerStep: Bool

    /// If the installer should automatically trash the DMG file afterwards.
    @Storage(key: "on.clarati.cis.automaticallyTrashDmg", defaultValue: true)
    public static var automaticallyTrashDmg: Bool

    /// If the installer should automatically open the extracted DMG contents afterwards.
    @Storage(key: "on.clarati.cis.automaticallyOpenApp", defaultValue: true)
    public static var automaticallyOpenApp: Bool
}
