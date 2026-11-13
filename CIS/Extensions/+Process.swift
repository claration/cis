//
//  Process.swift
//  CIS
//
//  Created by samsam on 11/12/26.
//

internal import struct Foundation.URL
internal import class Foundation.Process
internal import class Foundation.Pipe

extension Process {

    /// Helper function for launching processes.
    @discardableResult
    internal static func runProcess(
        executable: String,
        arguments: [String]
    ) -> (success: Bool, output: String) {
        let task = Self()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (task.terminationStatus == 0, output.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
