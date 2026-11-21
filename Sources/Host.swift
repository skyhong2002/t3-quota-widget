import AppKit
import WidgetKit
final class Delegate: NSObject, NSApplicationDelegate {
    var timer: Timer?
    var previous: Data?
    private var lastReload: [String: (state: Data, date: Date)] = [:]

    private func reload(_ kinds: [String], when state: [String: Any], interval: TimeInterval, force: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        let now = Date()
        for kind in kinds {
            if !force, let last = lastReload[kind],
               last.state == data || now.timeIntervalSince(last.date) < interval { continue }
            lastReload[kind] = (data, now)
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        sync()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.sync() }
    }
    func sync(forceReload: Bool = false) {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/reader.py").path, "--snapshot"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do {
            try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            guard p.terminationStatus == 0, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let accounts = object["accounts"] as? [[String: Any]] else { return }
            var published: [String: Any] = ["accounts": accounts]
            // `defaults write tw.skyhong.t3usage language en` or zh; follows the macOS language by default.
            let language = UserDefaults.standard.string(forKey: "language") ?? "auto"
            published["language"] = language == "auto" ? (Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en") : (language == "en" ? "en" : "zh")
            for key in ["pace", "spend", "computai"] {
                if let value = object[key], !(value is NSNull) { published[key] = value }
            }
            let payload = try JSONSerialization.data(withJSONObject: published, options: [.sortedKeys])
            if payload != previous {
                let root = URL(fileURLWithPath: "/Users/Shared/T3QuotaWidget", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try payload.write(to: root.appendingPathComponent("accounts.json"), options: .atomic)
                previous = payload
            }
            // Poll timestamps and derived countdowns change even when the underlying quotas do not.
            let quotas = accounts.map { account in
                var account = account
                if var usage = account["usage"] as? [String: Any] {
                    usage.removeValue(forKey: "updatedAt")
                    account["usage"] = usage
                }
                return account
            }
            let accountKinds = accounts.indices.map { "T3Account\($0)" }
            try reload(["T3FiveAccounts", "ComputAIPace"] + accountKinds,
                       when: ["accounts": quotas, "language": published["language"] ?? NSNull()],
                       interval: 600, force: forceReload)

            // Spend changes independently of quotas. Ignore timestamp-only changes and let WidgetKit
            // pick up intermediate updates through the normal timeline.
            var spend = published["spend"] as? [String: Any] ?? [:]
            spend.removeValue(forKey: "updatedAt")
            let ledger = published["computai"] as? [String: Any] ?? [:]
            try reload(["T3Spend", "ComputAITrend", "ComputAIDeviceSpend"],
                       when: ["spend": spend, "days": ledger["days"] ?? NSNull(),
                              "devices": ledger["devices"] ?? NSNull(), "yesterdayUSD": ledger["yesterdayUSD"] ?? NSNull(),
                              "language": published["language"] ?? NSNull()],
                       interval: 1800, force: forceReload)
            if forceReload { WidgetCenter.shared.reloadTimelines(ofKind: "ComputAIMachines") }
        } catch { print(error); fflush(stdout) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sync(forceReload: true)
        let alert = NSAlert(); alert.messageText = "T3 帳號額度 Widget"; alert.informativeText = "在桌面按右鍵 → 編輯小工具 → 搜尋 T3，選擇帳號卡片或「T3 帳號額度」。背景同步每 30 秒讀取 T3 Code 的既有資料。"; alert.addButton(withTitle: "好"); alert.runModal(); return true
    }
}
let app = NSApplication.shared; let delegate = Delegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
