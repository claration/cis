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
    @discardableResult
    internal static func runProcess(
        executable: String,
        arguments: [String],
        waitUntilExit: Bool = true
    ) -> (success: Bool, output: String, process: Process?) {
        let task = Self()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()

            if waitUntilExit {
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                return (task.terminationStatus == 0, output.trimmingCharacters(in: .whitespacesAndNewlines), nil)
            } else {
                return (false, "", task)
            }
        } catch {
            return (false, error.localizedDescription, nil)
        }
    }
}
