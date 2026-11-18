import Foundation

enum WindowsRibbonKeyTips {
    struct Tab {
        let key: String
        let names: [String]
    }

    enum Activation {
        case press
        case focus
        case menu
        case splitMenu
    }

    struct Binding {
        let key: String
        let names: [String]
        let activation: Activation

        init(_ key: String, _ names: [String], _ activation: Activation = .press) {
            self.key = key
            self.names = names
            self.activation = activation
        }

        func matches(title: String, identifier: String?) -> Bool {
            let candidates = [Self.normalized(title), Self.normalized(identifier ?? "")]
            return names.contains { candidates.contains(Self.normalized($0)) }
        }

        private static func normalized(_ value: String) -> String {
            let title = value.split(separator: "(", maxSplits: 1).first.map(String.init) ?? value
            return title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .unicodeScalars.filter(CharacterSet.alphanumerics.contains)
                .map(String.init).joined()
        }
    }

    static let tabs: [Tab] = [
        .init(key: "h", names: ["home", "start"]),
        .init(key: "n", names: ["insert", "einfügen"]),
        .init(key: "p", names: ["page layout", "seitenlayout", "layout"]),
        .init(key: "m", names: ["formulas", "formeln"]),
        .init(key: "a", names: ["data", "daten"]),
        .init(key: "r", names: ["review", "überprüfen"]),
        .init(key: "w", names: ["view", "ansicht"]),
        .init(key: "l", names: ["developer", "entwicklertools"]),
    ]

    // Windows Excel's English KeyTips, with aliases for the corresponding macOS controls.
    // https://support.microsoft.com/en-us/accessibility/excel/keyboard-shortcuts-in-excel
    // https://www.automateexcel.com/shortcuts/ribbon-commands/
    private static let controls: [String: [Binding]] = [
        "h": [
            .init("x", ["Cut", "Ausschneiden"]),
            .init("c", ["Copy", "Kopieren"]),
            .init("v", ["Paste", "Einfügen"], .splitMenu),
            .init("fp", ["Format Painter", "Format übertragen", "Format"]),
            .init("ff", ["Font", "Font Name", "Schriftart", "FontName"], .focus),
            .init("fs", ["Font Size", "Schriftgrad", "Schriftgröße", "FontSize"], .focus),
            .init("fg", ["Increase Font Size", "Schriftgrad vergrößern"]),
            .init("fk", ["Decrease Font Size", "Schriftgrad verkleinern"]),
            .init("1", ["Bold", "Fett", "FontBold"]),
            .init("2", ["Italic", "Kursiv", "FontItalic"]),
            .init("3", ["Underline", "Unterstreichen", "FontUnderline"]),
            .init("b", ["Borders", "Rahmen", "Rahmenlinien"], .splitMenu),
            .init("h", ["Fill Color", "Shading", "Füllfarbe"], .splitMenu),
            .init("fc", ["Font Color", "Schriftfarbe"], .splitMenu),
            .init("at", ["Top Align", "Oben ausrichten"]),
            .init("am", ["Middle Align", "Vertikal zentrieren", "Mittig ausrichten"]),
            .init("ab", ["Bottom Align", "Unten ausrichten"]),
            .init("fq", ["Orientation", "Ausrichtung", "Textausrichtung"], .menu),
            .init("al", ["Align Left", "Linksbündig", "Links ausrichten"]),
            .init("ac", ["Center", "Center Text", "Zentrieren", "Zentriert"]),
            .init("ar", ["Align Right", "Rechtsbündig", "Rechts ausrichten"]),
            .init("5", ["Decrease Indent", "Einzug verkleinern"]),
            .init("6", ["Increase Indent", "Einzug vergrößern"]),
            .init("w", ["Wrap Text", "Zeilenumbruch", "Text umbrechen"]),
            .init("m", ["Merge & Center", "Merge and Center", "Verbinden und zentrieren"], .splitMenu),
            .init("n", ["Number Format", "Zahlenformat"], .focus),
            .init("an", ["Accounting Number Format", "Buchhaltungszahlenformat"]),
            .init("p", ["Percent Style", "Prozentformat"]),
            .init("k", ["Comma Style", "Tausendertrennzeichen", "Kommaformat", "NumberCommaStyle"]),
            .init("0", ["Increase Decimal", "Dezimalstelle hinzufügen", "Dezimalstellen erhöhen"]),
            .init("9", ["Decrease Decimal", "Dezimalstelle löschen", "Dezimalstellen verringern"]),
            .init("l", ["Conditional Formatting", "Bedingte Formatierung"], .menu),
            .init("t", ["Format as Table", "Als Tabelle formatieren"], .menu),
            .init("j", ["Cell Styles", "Zellenformatvorlagen"], .menu),
            .init("i", ["Insert Cells", "Insert", "Zellen einfügen"], .splitMenu),
            .init("d", ["Delete Cells", "Delete", "Zellen löschen"], .splitMenu),
            .init("o", ["Cell Format", "Format Cells Menu", "Format"], .menu),
            .init("u", ["AutoSum", "AutoSumme"], .splitMenu),
            .init("fi", ["Fill", "Ausfüllen", "Füllbereich"], .menu),
            .init("e", ["Clear", "Löschen", "Inhalte löschen"], .menu),
            .init("s", ["Sort & Filter", "Sort and Filter", "Sortieren und Filtern"], .menu),
            .init("fd", ["Find & Select", "Find and Select", "Suchen und Auswählen"], .menu),
            .init("as", ["Add-ins", "Add-Ins"], .menu),
            .init("fe", ["Analyze Data", "Daten analysieren"]),
        ],
        "n": [
            .init("v", ["PivotTable", "PivotTable einfügen"], .menu),
            .init("sp", ["Recommended PivotTables", "Empfohlene PivotTables"]),
            .init("t", ["Table", "Tabelle"]),
            .init("zi", ["Illustrations", "Illustrationen"], .menu),
            .init("r", ["Recommended Charts", "Empfohlene Diagramme"]),
            .init("c1", ["Insert Column or Bar Chart", "Column or Bar Chart", "Säulen- oder Balkendiagramm"], .menu),
            .init("n1", ["Insert Line or Area Chart", "Line or Area Chart", "Linien- oder Flächendiagramm"], .menu),
            .init("q", ["Insert Pie or Doughnut Chart", "Pie or Doughnut Chart", "Kreis- oder Ringdiagramm"], .menu),
            .init("d", ["Insert Scatter or Bubble Chart", "Scatter or Bubble Chart", "Punkt- oder Blasendiagramm"], .menu),
            .init("m2", ["Maps", "Karten"], .menu),
            .init("sz", ["PivotChart"]),
            .init("sl", ["Line Sparkline", "Line", "Linie"]),
            .init("so", ["Column Sparkline", "Column", "Säule"]),
            .init("sw", ["Win/Loss Sparkline", "Win/Loss", "Gewinn/Verlust"]),
            .init("sf", ["Slicer", "Datenschnitt"]),
            .init("st", ["Timeline", "Zeitachse"]),
            .init("i2", ["Link", "Hyperlink"], .menu),
            .init("c2", ["Comment", "New Comment", "Kommentar", "Neuer Kommentar"]),
            .init("zt", ["Text"], .menu),
            .init("zs", ["Symbols", "Symbol", "Symbole"], .menu),
        ],
        "p": [
            .init("th", ["Themes", "Designs"], .menu),
            .init("tc", ["Theme Colors", "Colors", "Farben"], .menu),
            .init("tf", ["Theme Fonts", "Fonts", "Schriftarten"], .menu),
            .init("te", ["Theme Effects", "Effects", "Effekte"], .menu),
            .init("m", ["Margins", "Seitenränder"], .menu),
            .init("o", ["Orientation", "Ausrichtung"], .menu),
            .init("sz", ["Size", "Paper Size", "Größe", "Papierformat"], .menu),
            .init("r", ["Print Area", "Druckbereich"], .menu),
            .init("b", ["Breaks", "Umbrüche"], .menu),
            .init("g", ["Background", "Hintergrund"]),
            .init("i", ["Print Titles", "Drucktitel"]),
            .init("w", ["Width", "Breite"], .focus),
            .init("h", ["Height", "Höhe"], .focus),
            .init("x", ["Scale", "Skalierung"], .focus),
            .init("af", ["Bring Forward", "Ebene nach vorne"], .menu),
            .init("ae", ["Send Backward", "Ebene nach hinten"], .menu),
            .init("ap", ["Selection Pane", "Auswahlbereich"]),
            .init("aa", ["Align", "Ausrichten"], .menu),
            .init("ag", ["Group", "Gruppieren"], .menu),
            .init("ay", ["Rotate", "Drehen"], .menu),
        ],
        "m": [
            .init("f", ["Insert Function", "Funktion einfügen"]),
            .init("u", ["AutoSum", "AutoSumme"], .splitMenu),
            .init("r", ["Recently Used", "Zuletzt verwendet"], .menu),
            .init("i", ["Financial", "Finanzmathematik"], .menu),
            .init("l", ["Logical", "Logik"], .menu),
            .init("t", ["Text"], .menu),
            .init("e", ["Date & Time", "Datum und Uhrzeit"], .menu),
            .init("o", ["Lookup & Reference", "Nachschlagen und Verweisen"], .menu),
            .init("g", ["Math & Trig", "Mathematik und Trigonometrie"], .menu),
            .init("q", ["More Functions", "Weitere Funktionen"], .menu),
            .init("n", ["Name Manager", "Namens-Manager", "Namensmanager"]),
            .init("m", ["Define Name", "Namen definieren"], .splitMenu),
            .init("s", ["Use in Formula", "In Formel verwenden"], .menu),
            .init("c", ["Create from Selection", "Aus Auswahl erstellen"]),
            .init("p", ["Trace Precedents", "Spur zum Vorgänger"]),
            .init("d", ["Trace Dependents", "Spur zum Nachfolger"]),
            .init("a", ["Remove Arrows", "Pfeile entfernen"], .menu),
            .init("h", ["Show Formulas", "Formeln anzeigen"]),
            .init("k", ["Error Checking", "Fehlerüberprüfung"], .menu),
            .init("v", ["Evaluate Formula", "Formelauswertung"]),
            .init("w", ["Watch Window", "Überwachungsfenster"]),
            .init("x", ["Calculation Options", "Berechnungsoptionen"], .menu),
            .init("b", ["Calculate Now", "Jetzt berechnen"]),
            .init("j", ["Calculate Sheet", "Blatt berechnen"]),
        ],
        "a": [
            .init("pn", ["Get Data", "Daten abrufen"], .menu),
            .init("r", ["Refresh All", "Alle aktualisieren"], .splitMenu),
            .init("o", ["Queries & Connections", "Abfragen und Verbindungen"]),
            .init("sa", ["Sort Ascending", "Sort A to Z", "Aufsteigend sortieren", "Von A bis Z sortieren"]),
            .init("sd", ["Sort Descending", "Sort Z to A", "Absteigend sortieren", "Von Z bis A sortieren"]),
            .init("ss", ["Sort", "Sortieren"]),
            .init("t", ["Filter"]),
            .init("c", ["Clear Filter", "Clear", "Filter löschen"]),
            .init("y1", ["Reapply", "Erneut anwenden"]),
            .init("q", ["Advanced Filter", "Advanced", "Erweitert"]),
            .init("e", ["Text to Columns", "Text in Spalten"]),
            .init("ff", ["Flash Fill", "Blitzvorschau"]),
            .init("m", ["Remove Duplicates", "Duplikate entfernen"]),
            .init("v", ["Data Validation", "Datenüberprüfung"], .splitMenu),
            .init("n", ["Consolidate", "Konsolidieren"]),
            .init("dm", ["Relationships", "Beziehungen"]),
            .init("w", ["What-If Analysis", "Was-wäre-wenn-Analyse"], .menu),
            .init("fc", ["Forecast Sheet", "Prognoseblatt"]),
            .init("zo", ["Outline", "Gliederung"], .menu),
            .init("y2", ["Data Analysis", "Datenanalyse"]),
        ],
        "r": [
            .init("s", ["Spelling", "Rechtschreibung"]),
            .init("e", ["Thesaurus"]),
            .init("b", ["Workbook Statistics", "Arbeitsmappenstatistik"]),
            .init("a", ["Check Accessibility", "Barrierefreiheit überprüfen"], .menu),
            .init("l", ["Translate", "Übersetzen"]),
            .init("g", ["Show Changes", "Änderungen anzeigen"]),
            .init("c", ["New Comment", "Neuer Kommentar"]),
            .init("d", ["Delete Comment", "Delete", "Kommentar löschen"]),
            .init("v", ["Previous Comment", "Vorheriger Kommentar"]),
            .init("n", ["Next Comment", "Nächster Kommentar"]),
            .init("h1", ["Show Comments", "Kommentare anzeigen"]),
            .init("t", ["Notes", "Notizen"], .menu),
            .init("ps", ["Protect Sheet", "Blatt schützen"]),
            .init("pw", ["Protect Workbook", "Arbeitsmappe schützen"]),
            .init("u1", ["Allow Edit Ranges", "Bearbeiten von Bereichen zulassen"]),
            .init("h2", ["Hide Ink", "Freihand ausblenden"]),
        ],
        "w": [
            .init("l", ["Normal"]),
            .init("i", ["Page Break Preview", "Umbruchvorschau"]),
            .init("p", ["Page Layout", "Seitenlayout"]),
            .init("c", ["Custom Views", "Benutzerdefinierte Ansichten"]),
            .init("k", ["Navigation"]),
            .init("vh", ["Headings", "Überschriften"]),
            .init("vg", ["Gridlines", "Gitternetzlinien"]),
            .init("vf", ["Formula Bar", "Bearbeitungsleiste"]),
            .init("q", ["Zoom"]),
            .init("j", ["100%", "100 Percent"]),
            .init("g", ["Zoom to Selection", "Zoom auf Auswahl", "Auswahl vergrößern"]),
            .init("n", ["New Window", "Neues Fenster"]),
            .init("a", ["Arrange All", "Alle anordnen"]),
            .init("f", ["Freeze Panes", "Fenster fixieren"], .menu),
            .init("s", ["Split", "Teilen"]),
            .init("h", ["Hide", "Ausblenden"]),
            .init("u", ["Unhide", "Einblenden"]),
            .init("w", ["Switch Windows", "Fenster wechseln"], .menu),
            .init("m", ["Macros", "Makros"], .menu),
        ],
    ]

    static func tab(named title: String) -> Tab? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return tabs.first { $0.names.contains(title) }
    }

    static func bindings(for tabTitle: String) -> [Binding] {
        guard let tab = tab(named: tabTitle) else { return [] }
        return controls[tab.key] ?? []
    }
}
