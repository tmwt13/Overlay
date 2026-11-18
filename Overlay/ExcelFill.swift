import Foundation

enum ExcelFill {
    case rgb(UInt32)
    case none

    init?(color: String) {
        let color = color.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch color {
        case "none": self = .none
        case "black", "schwarz": self = .rgb(0x000000)
        case "white", "weiß", "weiss": self = .rgb(0xffffff)
        case "red", "rot": self = .rgb(0xff0000)
        case "green", "grün", "gruen": self = .rgb(0x008000)
        case "blue", "blau": self = .rgb(0x0000ff)
        case "yellow", "gelb": self = .rgb(0xffff00)
        case "orange": self = .rgb(0xffa500)
        case "purple", "lila": self = .rgb(0x800080)
        case "gray", "grey", "grau": self = .rgb(0x808080)
        default:
            guard color.first == "#", color.count == 7,
                  color.dropFirst().allSatisfy(\.isHexDigit),
                  let rgb = UInt32(color.dropFirst(), radix: 16) else { return nil }
            self = .rgb(rgb)
        }
    }

    var assignment: String {
        switch self {
        case .none:
            return "set pattern of interior object of selection to pattern none"
        case .rgb(let color):
            let red = (color >> 16) & 255
            let green = (color >> 8) & 255
            let blue = color & 255
            return "set color of interior object of selection to {\(red), \(green), \(blue)}"
        }
    }
}

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
        return detail ?? "Excel konnte die Formatierung nicht anwenden"
    }
}
