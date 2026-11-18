import Foundation

enum ExcelAppleScript {
    static func source(for assignment: String, in applicationURL: URL) -> String {
        let path = applicationURL.path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "\(path)"
            \(assignment)
        end tell
        """
    }

    static func run(_ assignment: String, in applicationURL: URL) -> String? {
        guard let appleScript = NSAppleScript(source: source(for: assignment, in: applicationURL)) else {
            return "Excel-Skript konnte nicht erstellt werden"
        }
        var error: NSDictionary?
        _ = appleScript.executeAndReturnError(&error)
        guard let error else { return nil }
        if error[NSAppleScript.errorNumber] as? Int == -1743 {
            return "Excel-Zugriff unter Datenschutz & Sicherheit → Automation erlauben"
        }
        let detail = error[NSAppleScript.errorMessage] as? String
        return detail ?? "Excel konnte die Aktion nicht ausführen"
    }
}
