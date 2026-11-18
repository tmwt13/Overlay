import Carbon

struct WorksheetMotion {
    enum Direction: String {
        case left, right, up, down

        var keyCode: CGKeyCode {
            switch self {
            case .left: CGKeyCode(kVK_LeftArrow)
            case .right: CGKeyCode(kVK_RightArrow)
            case .up: CGKeyCode(kVK_UpArrow)
            case .down: CGKeyCode(kVK_DownArrow)
            }
        }

        var rowStep: Int {
            switch self {
            case .up: -1
            case .down: 1
            case .left, .right: 0
            }
        }

        var columnStep: Int {
            switch self {
            case .left: -1
            case .right: 1
            case .up, .down: 0
            }
        }
    }

    enum Target {
        case step(Direction, Int)
        case row(Int)
        case lastUsedRow
    }

    static let maxRow = 1_048_576
    static let maxColumn = 16_384

    let target: Target
    let extendsSelection: Bool

    var assignment: String {
        """
        \(WorksheetSelectionScript.anchor)
        \(extendsSelection ? WorksheetSelectionScript.visualEndpoint : "")
        set destinationRow to searchRow
        set destinationColumn to movingColumn
        \(destination)
        if destinationRow is searchRow and destinationColumn is movingColumn then return
        \(WorksheetSelectionScript.selectDestination(extendsSelection: extendsSelection))
        """
    }

    private var destination: String {
        switch target {
        case .row(let row):
            "set destinationRow to \(row)"
        case .lastUsedRow:
            """
            set usedCells to used range of (worksheet object of anchorCell)
            set destinationRow to (first row index of usedCells) + (count rows of usedCells) - 1
            """
        case .step(let direction, let count):
            """
            set destinationRow to searchRow + \(direction.rowStep * count)
            if destinationRow < 1 then set destinationRow to 1
            if destinationRow > \(Self.maxRow) then set destinationRow to \(Self.maxRow)
            set destinationColumn to movingColumn + \(direction.columnStep * count)
            if destinationColumn < 1 then set destinationColumn to 1
            if destinationColumn > \(Self.maxColumn) then set destinationColumn to \(Self.maxColumn)
            """
        }
    }
}
