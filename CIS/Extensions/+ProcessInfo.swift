//
//  +NSDevice.swift
//  stupiddiskimageinstaller
//
//  Created by samsam on 11/11/26.
//

import class Foundation.ProcessInfo
import class Foundation.FileManager
import class Foundation.NSNumber

extension ProcessInfo {
    /// The operating systems remaining space, in formatted bytes (i.e. 236 GB).
    internal func remainingSpace() -> String? {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/")

        if let freeSizeNumber = attrs?[.systemFreeSize] as? NSNumber {
            return freeSizeNumber.int64Value.formattedBytes()
        }

        return nil
    }

    /// The operating systems marketing model using `libMobileGestalt`.
    internal var marketingModel: String {
        guard
            let raw = MGCopyAnswer(kMGPhysicalHardwareNameString)?.takeUnretainedValue() as? String
        else {
            return "Unknown"
        }

        // Mac Mini (2022) -> Mac Mini
        if let parenIndex = raw.firstIndex(of: "(") {
            return String(raw[..<parenIndex]).trimmingCharacters(in: .whitespaces)
        }

        return raw
    }
}
