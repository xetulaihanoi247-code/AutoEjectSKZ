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
    static let remountKey = "autoRemountEnabled"
    static var remount: Bool {
        get { UserDefaults.standard.object(forKey: remountKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: remountKey) }
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

// MARK: - Mount lại

/// Tên BSD (vd "disk5") của các ổ ngoài vật lý đang cắm, kể cả khi chưa mount.
func connectedExternalDisks() -> [String] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    p.arguments = ["list", "-plist", "external", "physical"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let list = plist["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
    return list.compactMap { $0["DeviceIdentifier"] as? String }
}

/// Mount mọi volume của các ổ ngoài đang cắm. Trả về tên các volume mới xuất hiện.
func mountAll() -> [String] {
    let before = Set(externalVolumes().map { $0.path })
    for disk in connectedExternalDisks() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        p.arguments = ["mountDisk", disk]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }
    return externalVolumes().filter { !before.contains($0.path) }.map { $0.lastPathComponent }
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
    private var remountItem: NSMenuItem!
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
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func tick() {
        let closed = isLidClosed()
        defer { lidWasClosed = closed }
        if closed && !lidWasClosed { handleTrigger(reason: "gập máy") }
        if !closed && lidWasClosed { scheduleRemount(reason: "mở máy") }
    }

    @objc private func willSleep(_ n: Notification) { handleTrigger(reason: "máy sắp ngủ") }
    @objc private func didWake(_ n: Notification) { scheduleRemount(reason: "máy thức dậy") }

    // MARK: Mount lại khi mở máy

    private var lastRemount = Date.distantPast
    private var remountToken = 0

    private func scheduleRemount(reason: String) {
        guard Prefs.remount else { return }
        // Chống chạy trùng (didWake + mở nắp cùng bắn).
        guard Date().timeIntervalSince(lastRemount) > 5 else { return }
        lastRemount = Date()
        remountToken += 1
        attemptRemount(token: remountToken, attempt: 0, reason: reason)
    }

    /// Thử lúc ~3s, ~5s, ~9s sau khi thức dậy (USB cần chút thời gian để nhận lại).
    private func attemptRemount(token: Int, attempt: Int, reason: String) {
        let delays: [Double] = [3, 2, 4]
        guard attempt < delays.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt]) { [weak self] in
            guard let self = self, token == self.remountToken else { return }
            // Nắp còn gập (dark wake / Power Nap) thì thôi, không mount.
            guard !isLidClosed() else { return }
            DispatchQueue.global().async {
                let mounted = mountAll()
                DispatchQueue.main.async {
                    guard token == self.remountToken else { return }
                    if mounted.isEmpty {
                        self.attemptRemount(token: token, attempt: attempt + 1, reason: reason)
                    } else {
                        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
                        self.lastItem.title = "\(f.string(from: Date())) (\(reason)): đã mount \(mounted.count)"
                        notify("AutoEject", "Đã mount lại: " + mounted.joined(separator: ", "))
                    }
                }
            }
        }
    }

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

        remountItem = NSMenuItem(title: "Tự mount lại khi mở máy", action: #selector(toggleRemount), keyEquivalent: "")
        remountItem.target = self
        remountItem.state = Prefs.remount ? .on : .off
        menu.addItem(remountItem)

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

    @objc private func toggleRemount() {
        Prefs.remount.toggle()
        remountItem.state = Prefs.remount ? .on : .off
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
    print("Ổ ngoài đang cắm (sẽ mount lại): \(connectedExternalDisks())")
    exit(0)
}

// Kiểm thử mount lại thật:  AutoEject --remount-now
if CommandLine.arguments.contains("--remount-now") {
    print("Đã mount: \(mountAll())")
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // chỉ icon menu bar, không hiện ở Dock
let delegate = AppDelegate()
app.delegate = delegate
app.run()
