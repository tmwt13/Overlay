enum WorksheetSelectionScript {
    static let anchor = """
    set anchorCell to get active cell
    set anchorRow to first row index of anchorCell
    set anchorColumn to first column index of anchorCell
    set searchRow to anchorRow
    set movingColumn to anchorColumn
    """

    static let visualEndpoint = """
    set selectedRange to get selection
    if (count (areas of selectedRange)) is not 1 then return
    set selectedTop to first row index of selectedRange
    set selectedLeft to first column index of selectedRange
    set selectedBottom to selectedTop + (count rows of selectedRange) - 1
    set selectedRight to selectedLeft + (count columns of selectedRange) - 1
    if anchorRow is selectedBottom then
        set searchRow to selectedTop
    else
        set searchRow to selectedBottom
    end if
    if anchorColumn is selectedRight then
        set movingColumn to selectedLeft
    else
        set movingColumn to selectedRight
    end if
    """

    static func selectDestination(extendsSelection: Bool) -> String {
        guard extendsSelection else {
            return """
            goto reference (get offset anchorCell row offset (destinationRow - anchorRow) column offset (destinationColumn - anchorColumn))
            """
        }
        return """
        set topRow to anchorRow
        if destinationRow < topRow then set topRow to destinationRow
        set leftColumn to anchorColumn
        if destinationColumn < leftColumn then set leftColumn to destinationColumn
        set rangeStart to get offset anchorCell row offset (topRow - anchorRow) column offset (leftColumn - anchorColumn)
        set rowSpan to anchorRow + destinationRow - 2 * topRow + 1
        set columnSpan to anchorColumn + destinationColumn - 2 * leftColumn + 1
        set newSelection to get resize rangeStart row size rowSpan column size columnSpan
        goto reference newSelection
        activate object anchorCell
        """
    }
}
