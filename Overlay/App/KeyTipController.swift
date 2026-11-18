import AppKit
import ApplicationServices
import Combine

final class KeyTipController: ObservableObject {
    enum KeyboardAccess {
        case needsPermission
        case unavailable
        case alreadyRunning
        case ready
    }

    private static let excelBundleID = "com.microsoft.Excel"

    @Published private(set) var keyboardAccess = KeyboardAccess.needsPermission {
        didSet { requestModeIndicatorUpdate() }
    }
    @Published private(set) var isExcelFrontmost = false

    @Published var vimMode: ExcelVim.Mode = .insert {
        didSet {
            if vimMode != oldValue { requestModeIndicatorUpdate() }
        }
    }
    @Published var vimEnabled = UserDefaults.standard.object(forKey: "excelVimEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(vimEnabled, forKey: "excelVimEnabled")
            resetVim()
            if vimEnabled {
                if keyboardAccess == .ready { startVim() }
            } else {
                vim.stop()
                vimState = nil
            }
            requestModeIndicatorUpdate()
        }
    }

    @Published var vimStatus = "" {
        didSet {
            if vimStatus != oldValue { requestModeIndicatorUpdate() }
        }
    }
    let vim = ExcelVim()
    var vimProcess: pid_t?
    var vimState: ExcelVim.Event?
    var vimInsertNeedsCommit = false
    var vimCommitID: UUID?
    var deferredVimEvents: [ExcelVim.Event] = []
    var vimCommandVisible = false

    let accessibility = ExcelAccessibility()
    let reader = RibbonReader()
    let overlay = KeyTipOverlay()
    let keyboard = KeyboardEventTap()
    private let modeIndicator = VimModeIndicator()
    private var modeIndicatorUpdatePending = false
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    var optionPressedAt: TimeInterval?
    var swallowedKeys: Set<Int64> = []
    var keyTips = KeyTipSession()

    init() {
        isExcelFrontmost = frontExcel != nil
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isExcelFrontmost = app?.bundleIdentifier == Self.excelBundleID
                if app?.processIdentifier != self.vimProcess {
                    self.resetVim()
                }
                if app?.processIdentifier != self.keyTips.process {
                    self.optionPressedAt = nil
                    self.dismiss()
                }
                self.requestModeIndicatorUpdate()
            }
        }

        vim.onEvent = { [weak self] event in self?.handleVimEvent(event) }
        vim.onExit = { [weak self] in
            self?.resetVim()
            self?.vimState = nil
            self?.vimStatus = "Vim wurde beendet"
        }
        enable(prompt: false)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if !self.keyboard.isRunning, AXIsProcessTrusted() {
                    self.enable(prompt: false)
                } else if self.keyTips.process == nil, self.optionPressedAt == nil {
                    self.requestModeIndicatorUpdate()
                }
            }
        }
    }

    func enable(prompt: Bool) {
        guard !keyboard.isRunning else { return }
        let option = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        guard AXIsProcessTrustedWithOptions([option: prompt] as CFDictionary) else {
            keyboardAccess = .needsPermission
            return
        }

        let result = keyboard.start { [weak self] type, event in
            self?.handle(type, event: event) ?? false
        }
        switch result {
        case .started:
            keyboardAccess = .ready
            if vimEnabled { startVim() }
        case .alreadyRunning: keyboardAccess = .alreadyRunning
        case .unavailable: keyboardAccess = .unavailable
        }
    }

    func requestModeIndicatorUpdate() {
        guard !modeIndicatorUpdatePending else { return }
        modeIndicatorUpdatePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.modeIndicatorUpdatePending = false
            self.updateModeIndicator()
        }
    }

    private func updateModeIndicator() {
        guard keyboardAccess == .ready, vimEnabled, vimStatus.isEmpty, vim.isRunning,
              let excel = frontExcel?.processIdentifier,
              let frame = accessibility.focusedWindowFrame(in: excel) else {
            modeIndicator.hide()
            return
        }
        modeIndicator.show(vimMode, recording: vimState?.recordingRegister, in: frame)
    }

    var frontExcel: NSRunningApplication? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == Self.excelBundleID else { return nil }
        return app
    }

    func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
