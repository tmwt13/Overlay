struct PopulatedCellMotion {
    enum Direction: String {
        case forward
        case backward
    }

    let direction: Direction
    let count: Int
    let extendsSelection: Bool

    var assignment: String {
        let forward = direction == .forward
        return """
        \(WorksheetSelectionScript.anchor)
        \(extendsSelection ? WorksheetSelectionScript.visualEndpoint : "")
        set destinationRow to searchRow

        set cursorCell to get offset anchorCell row offset (searchRow - anchorRow) column offset (movingColumn - anchorColumn)
        set searchRange to entire row of cursorCell
        set destinationColumn to movingColumn
        repeat \(count) times
            set foundCell to find searchRange what "*" after cursorCell look in formulas look at part search order by rows search direction \(forward ? "search next" : "search previous")
            if foundCell is missing value then exit repeat
            set foundColumn to first column index of foundCell
            if foundColumn \(forward ? "≤" : "≥") destinationColumn then exit repeat
            set destinationColumn to foundColumn
            set cursorCell to foundCell
        end repeat
        if destinationColumn is movingColumn then return
        \(WorksheetSelectionScript.selectDestination(extendsSelection: extendsSelection))
        """
    }
}
