import Foundation

struct ExcelBorder {
    private enum Side: String, CaseIterable {
        case top, bottom, left, right
    }

    private let sides: [Side]

    init?(sides: [String]) {
        let parsed = sides.compactMap {
            Side(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        guard !parsed.isEmpty, parsed.count == sides.count else { return nil }
        self.sides = Side.allCases.filter { parsed.contains($0) }
    }

    var assignment: String {
        let edges = sides.map { "edge " + $0.rawValue }.joined(separator: ", ")
        return """
        set targetRange to selection
        repeat with side in {\(edges)}
            set edgeBorder to get border targetRange which border (contents of side)
            set line style of edgeBorder to continuous
            set weight of edgeBorder to border weight thin
        end repeat
        """
    }
}
