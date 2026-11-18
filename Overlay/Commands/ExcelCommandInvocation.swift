import Foundation

struct ExcelCommandInvocation {
    let name: String
    let arguments: [String]

    init?(_ input: String) {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandName = input.prefix { !$0.isWhitespace && $0 != "(" }
        var tail = input.dropFirst(commandName.count)

        // Keep the existing :select("home") spelling alongside :select home.
        if tail.first == "(", tail.last == ")" {
            tail = tail.dropFirst().dropLast()
        }

        var end = tail.startIndex
        var arguments: [String] = []
        for token in tail.matches(of: /"([^"]*)"|'([^']*)'|([^\s"']+)/) {
            guard tail[end..<token.range.lowerBound].allSatisfy(\.isWhitespace) else { return nil }
            arguments.append(String(token.1 ?? token.2 ?? token.3 ?? ""))
            end = token.range.upperBound
        }
        guard tail[end...].allSatisfy(\.isWhitespace) else { return nil }

        name = String(commandName)
        self.arguments = arguments
    }
}
