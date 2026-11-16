//
//  Process.swift
//  CIS
//
//  Created by samsam on 11/12/26.
//

import struct Foundation.URL
import class Foundation.Process
import class Foundation.Pipe

extension Process {

    /// Helper function for launching processes.
    internal static func runProcess(
        executable: String,
        arguments: [String]
    ) {
        let task = Self()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        try? task.run()
    }
}
