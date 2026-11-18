import Carbon
import Darwin
import Foundation

final class ExcelVim {
    enum Mode: String {
        case insert = "Insert"
        case normal = "Normal"
        case visual = "Visual"
    }

    struct Event: Decodable {
        let mode: String?
        let row: Int?
        let column: Int?
        let command: String?
        let excelCommand: String?
        let excelAction: String?
        let arguments: [String]?
        let worksheet: Bool?

        var excelMode: Mode {
            switch mode?.first {
            case "i", "R": .insert
            case "v", "V", "\u{16}": .visual
            default: .normal
            }
        }
    }

    private var process: Process?
    private var terminal: DispatchSourceRead?
    private var events: DispatchSourceFileSystemObject?
    private var master: Int32 = -1
    private var eventFile: FileHandle?
    private var pending = Data()
    private var directory: URL?

    var onEvent: ((Event) -> Void)?
    var onExit: (() -> Void)?
    var isRunning: Bool { process?.isRunning == true }

    func start(commandNames: [String]) throws {
        guard !isRunning else { return }
        stop()
        let paths = ["/opt/homebrew/bin/vim", "/usr/local/bin/vim", "/usr/bin/vim"]
        guard let vim = paths.first(where: FileManager.default.isExecutableFile(atPath:)),
              let script = Bundle.main.url(forResource: "ExcelVimBridge", withExtension: "vim") else {
            throw CocoaError(.fileNoSuchFile)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExcelVim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        self.directory = directory

        do {
            let log = directory.appendingPathComponent("events.jsonl")
            try Data().write(to: log)
            let file = try FileHandle(forReadingFrom: log)
            eventFile = file
            let events = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: file.fileDescriptor, eventMask: .write, queue: .main)
            events.setEventHandler { [weak self] in self?.receiveEvents() }
            events.setCancelHandler { try? file.close() }
            self.events = events
            events.resume()

            var slave: Int32 = -1
            var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
            guard openpty(&master, &slave, nil, nil, &size) == 0 else { throw POSIXError(.EIO) }
            let fd = master
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            let terminal = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            terminal.setEventHandler { [weak self] in
                var output = [UInt8](repeating: 0, count: 8192)
                while Darwin.read(fd, &output, output.count) > 0 {}
                if self?.process?.isRunning == false { self?.ended() }
            }
            terminal.setCancelHandler { Darwin.close(fd) }
            self.terminal = terminal
            terminal.resume()

            let pty = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
            defer { try? pty.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: vim)
            process.arguments = ["-N", "-n", "-i", "NONE", "-S", script.path]
            process.environment = ProcessInfo.processInfo.environment.merging([
                "TERM": "xterm-256color",
                "EXCEL_VIM_EVENTS": log.path,
                "EXCEL_VIM_COMMANDS": commandNames.joined(separator: ",")
            ], uniquingKeysWith: { _, new in new })
            process.standardInput = pty
            process.standardOutput = pty
            process.standardError = pty
            process.terminationHandler = { [weak self] child in
                DispatchQueue.main.async {
                    if self?.process === child { self?.ended() }
                }
            }
            try process.run()
            self.process = process
        } catch {
            stop()
            throw error
        }
    }

    func send(_ keys: String) {
        guard master >= 0, isRunning else { return }
        let bytes = Array(keys.utf8)
        bytes.withUnsafeBytes { buffer in
            _ = Darwin.write(master, buffer.baseAddress, buffer.count)
        }
    }

    func stop() {
        let child = process
        process = nil
        if child?.isRunning == true { child?.terminate() }
        terminal?.cancel()
        terminal = nil
        master = -1
        events?.cancel()
        events = nil
        eventFile = nil
        pending.removeAll()
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    private func ended() {
        stop()
        onExit?()
    }

    private func receiveEvents() {
        guard let data = try? eventFile?.readToEnd(), !data.isEmpty else { return }
        pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
            let line = pending[..<newline]
            pending.removeSubrange(...newline)
            if let event = try? JSONDecoder().decode(Event.self, from: line) {
                onEvent?(event)
            }
        }
    }

    static func terminalKeys(for key: Int64, characters: String, control: Bool) -> String? {
        let special: String?
        switch key {
        case Int64(kVK_Escape): special = "\u{1b}"
        case Int64(kVK_Return), Int64(kVK_ANSI_KeypadEnter): special = "\r"
        case Int64(kVK_Delete): special = "\u{7f}"
        case Int64(kVK_ForwardDelete): special = "\u{1b}[3~"
        case Int64(kVK_Tab): special = "\t"
        case Int64(kVK_LeftArrow): special = "\u{1b}OD"
        case Int64(kVK_RightArrow): special = "\u{1b}OC"
        case Int64(kVK_UpArrow): special = "\u{1b}OA"
        case Int64(kVK_DownArrow): special = "\u{1b}OB"
        default: special = nil
        }
        if let special { return special }
        if control, let scalar = characters.lowercased().unicodeScalars.first,
           (97...122).contains(scalar.value), let character = UnicodeScalar(scalar.value - 96) {
            return String(character)
        }
        guard !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ $0.value < 0xf700 || $0.value > 0xf8ff }) else { return nil }
        return characters
    }
}
