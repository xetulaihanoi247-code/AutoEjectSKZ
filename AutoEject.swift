// AutoEject — ứng dụng menu bar: gập máy là tự eject toàn bộ ổ ngoài.
// Build: ./build.sh   (swiftc, không cần Xcode project)

import Cocoa
import IOKit
import ServiceManagement

// MARK: - Cấu hình

enum Prefs {
    static let enabledKey = "autoEjectEnabled"
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

// MARK: - Đọc trạng thái nắp máy

/// true = nắp đang gập. Đọc từ IOPMrootDomain (key AppleClamshellState).
func isLidClosed() -> Bool {
    let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard svc != 0 else { return false }
    defer { IOObjectRelease(svc) }
    guard let prop = IORegistryEntryCreateCFProperty(svc, "AppleClamshellState" as CFString,
                                                     kCFAllocatorDefault, 0)?.takeRetainedValue()
    else { return false }
    return (prop as? Bool) ?? false
}

// MARK: - Eject

struct EjectResult {
    var ejected: [String] = []
    var failed: [(name: String, reason: String)] = []
}

/// Liệt kê các ổ cần eject: ổ ngoài / removable / ejectable, bỏ ổ trong và ổ hệ thống.
func externalVolumes() -> [URL] {
    let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsEjectableKey,
                                  .volumeIsRemovableKey, .volumeIsLocalKey, .volumeNameKey]
    let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                     options: [.skipHiddenVolumes]) ?? []
    return urls.filter { url in
        guard url.path != "/", !url.path.hasPrefix("/System/") else { return false }
        guard let v = try? url.resourceValues(forKeys: Set(keys)) else { return false }
        guard v.volumeIsLocal == true else { return false }      // bỏ ổ mạng
        if v.volumeIsInternal == true { return false }           // bỏ ổ trong
        return v.volumeIsEjectable == true || v.volumeIsRemovable == true || v.volumeIsInternal == false
    }
}

func ejectAll(dryRun: Bool = false) -> EjectResult {
    var result = EjectResult()
    for url in externalVolumes() {
        let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
        if dryRun { result.ejected.append(name); continue }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            result.ejected.append(name)
        } catch {
            result.failed.append((name, error.localizedDescription))
        }
    }
    return result
}

func notify(_ title: String, _ body: String) {
    let esc = { (s: String) in s.replacingOccurrences(of: "\"", with: "'") }
    let script = "display notification \"\(esc(body))\" with title \"\(esc(title))\""
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    try? p.run()
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var lastItem: NSMenuItem!
    private var lidWasClosed = false
    private var lastEject = Date.distantPast
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        lidWasClosed = isLidClosed()

        // Poll nắp máy 2 lần/giây: bắt được cả khi cắm màn hình ngoài (máy không ngủ).
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)

        // Phòng hờ: máy sắp ngủ (gập máy, hết pin, bấm nút nguồn...) thì cũng eject.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
    }

    private func tick() {
        let closed = isLidClosed()
        defer { lidWasClosed = closed }
        if closed && !lidWasClosed { handleTrigger(reason: "gập máy") }
    }

    @objc private func willSleep(_ n: Notification) { handleTrigger(reason: "máy sắp ngủ") }

    private func handleTrigger(reason: String) {
        guard Prefs.enabled else { return }
        // Chống eject 2 lần liền (poll + sleep notification cùng bắn).
        guard Date().timeIntervalSince(lastEject) > 5 else { return }
        lastEject = Date()
        let r = ejectAll()
        report(r, reason: reason)
    }

    private func report(_ r: EjectResult, reason: String) {
        guard !(r.ejected.isEmpty && r.failed.isEmpty) else { return }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        var line = "\(f.string(from: Date())) (\(reason)): đã eject \(r.ejected.count)"
        if !r.failed.isEmpty { line += ", lỗi \(r.failed.count)" }
        lastItem.title = line
        if !r.failed.isEmpty {
            let detail = r.failed.map { "\($0.name): đang bận" }.joined(separator: "; ")
            notify("AutoEject — không eject được", detail)
        } else {
            notify("AutoEject", "Đã eject: " + r.ejected.joined(separator: ", "))
        }
    }

    // MARK: Menu

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eject.circle",
                                           accessibilityDescription: "AutoEject")
        let menu = NSMenu()

        enabledItem = NSMenuItem(title: "Tự động eject khi gập máy", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = Prefs.enabled ? .on : .off
        menu.addItem(enabledItem)

        let now = NSMenuItem(title: "Eject tất cả ngay", action: #selector(ejectNow), keyEquivalent: "e")
        now.target = self
        menu.addItem(now)

        menu.addItem(.separator())
        lastItem = NSMenuItem(title: "Chưa eject lần nào", action: nil, keyEquivalent: "")
        lastItem.isEnabled = false
        menu.addItem(lastItem)
        menu.addItem(.separator())

        loginItem = NSMenuItem(title: "Khởi động cùng máy", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(withTitle: "Thoát", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        Prefs.enabled.toggle()
        enabledItem.state = Prefs.enabled ? .on : .off
        statusItem.button?.image = NSImage(systemSymbolName: Prefs.enabled ? "eject.circle" : "eject.circle.fill",
                                           accessibilityDescription: "AutoEject")
        statusItem.button?.appearsDisabled = !Prefs.enabled
    }

    @objc private func ejectNow() {
        let r = ejectAll()
        if r.ejected.isEmpty && r.failed.isEmpty { notify("AutoEject", "Không có ổ ngoài nào đang cắm.") }
        report(r, reason: "thủ công")
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            notify("AutoEject", "Không đặt được khởi động cùng máy: \(error.localizedDescription)")
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

// MARK: - Entry point

// Chế độ dòng lệnh để kiểm thử mà không eject thật:  AutoEject --dry-run
if CommandLine.arguments.contains("--dry-run") {
    print("Nắp máy đang gập: \(isLidClosed())")
    let r = ejectAll(dryRun: true)
    print("Sẽ eject: \(r.ejected)")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // chỉ icon menu bar, không hiện ở Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
