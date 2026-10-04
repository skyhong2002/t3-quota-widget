import AppKit
import WidgetKit
final class Delegate: NSObject, NSApplicationDelegate {
    var timer: Timer?
    var previous: Data?
    func applicationDidFinishLaunching(_ notification: Notification) {
        sync()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.sync() }
    }
    func sync() {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        p.arguments = [Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/reader.py").path, "--snapshot"]
        p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        do {
            try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            guard p.terminationStatus == 0, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let accounts = object["accounts"] else { return }
            var published: [String: Any] = ["accounts": accounts]
            if let spend = object["spend"], !(spend is NSNull) { published["spend"] = spend }
            let payload = try JSONSerialization.data(withJSONObject: published, options: [.sortedKeys])
            guard payload != previous else { return }
            guard let root = Optional(URL(fileURLWithPath: "/Users/Shared/T3QuotaWidget", isDirectory: true)) else { print("No shared container"); fflush(stdout); return }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try payload.write(to: root.appendingPathComponent("accounts.json"), options: .atomic)
            previous = payload
            WidgetCenter.shared.reloadAllTimelines()
            print("Updated five-account widget"); fflush(stdout)
        } catch { print(error); fflush(stdout) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sync()
        let alert = NSAlert(); alert.messageText = "T3 五帳號 Widget"; alert.informativeText = "在桌面按右鍵 → 編輯小工具 → 搜尋 T3，加入「T3 五帳號額度」。背景同步每 30 秒讀取 T3 Code 的既有資料。"; alert.addButton(withTitle: "好"); alert.runModal(); return true
    }
}
let app = NSApplication.shared; let delegate = Delegate(); app.delegate = delegate; app.setActivationPolicy(.accessory); app.run()
