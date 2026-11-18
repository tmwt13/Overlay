extension WindowsRibbonKeyTips {
    // Keys are the tab and the menu's KeyTip, followed by the entries in that Windows menu.
    private static let menus: [String: [Binding]] = [
        "hb": [
            .init("p", ["Top Border", "Rahmenlinie oben"]),
            .init("o", ["Bottom Border", "Rahmenlinie unten"]),
            .init("l", ["Left Border", "Rahmenlinie links"]),
            .init("r", ["Right Border", "Rahmenlinie rechts"]),
            .init("n", ["No Border", "Kein Rahmen", "Keine Rahmenlinie"]),
            .init("a", ["All Borders", "Alle Rahmenlinien"]),
            .init("s", ["Outside Borders", "Rahmenlinien außen", "Außenrahmen"]),
        ],
        "he": [
            .init("a", ["Clear All", "Alles löschen"]),
            .init("f", ["Clear Formats", "Formate löschen"]),
            .init("c", ["Clear Contents", "Inhalte löschen"]),
        ],
        "hi": [
            .init("i", ["Insert Cells", "Zellen einfügen"]),
            .init("r", ["Insert Sheet Rows", "Insert Rows", "Blattzeilen einfügen", "Zeilen einfügen"]),
            .init("c", ["Insert Sheet Columns", "Insert Columns", "Blattspalten einfügen", "Spalten einfügen"]),
            .init("s", ["Insert Sheet", "Blatt einfügen"]),
        ],
        "hd": [
            .init("d", ["Delete Cells", "Zellen löschen"]),
            .init("r", ["Delete Sheet Rows", "Delete Rows", "Blattzeilen löschen", "Zeilen löschen"]),
            .init("c", ["Delete Sheet Columns", "Delete Columns", "Blattspalten löschen", "Spalten löschen"]),
            .init("s", ["Delete Sheet", "Blatt löschen"]),
        ],
        "ho": [
            .init("h", ["Row Height", "Zeilenhöhe"]),
            .init("a", ["AutoFit Row Height", "Zeilenhöhe automatisch anpassen"]),
            .init("w", ["Column Width", "Spaltenbreite"]),
            .init("i", ["AutoFit Column Width", "Spaltenbreite automatisch anpassen"]),
        ],
        "hfd": [
            .init("f", ["Find", "Suchen"]),
            .init("r", ["Replace", "Ersetzen"]),
            .init("g", ["Go To", "Gehe zu"]),
            .init("s", ["Go To Special", "Inhalte auswählen"]),
        ],
        "hm": [
            .init("c", ["Merge & Center", "Merge and Center", "Verbinden und zentrieren"]),
            .init("a", ["Merge Across", "Verbinden über"]),
            .init("m", ["Merge Cells", "Zellen verbinden"]),
            .init("u", ["Unmerge Cells", "Zellverbund aufheben"]),
        ],
        "wf": [
            .init("f", ["Freeze Panes", "Fenster fixieren", "Freeze at Selection"]),
            .init("r", ["Freeze Top Row", "Oberste Zeile fixieren"]),
            .init("c", ["Freeze First Column", "Erste Spalte fixieren"]),
        ],
    ]

    static func submenu(at path: String) -> [Binding] { menus[path] ?? [] }
}
