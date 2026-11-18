import Foundation

struct KeyTipSession {
    var process: pid_t?
    var tips: [RibbonKeyTip] = []
    var tab: RibbonTab?
    var commandPath = ""
    var menuIsOpen = false
    var helpIsOpen = false
    var prefix = ""
    var commandLine: String?
    var tabLoadID = UUID()
    var isLoadingTab = false
    var pendingKeys: [(Int64, String)] = []
}
