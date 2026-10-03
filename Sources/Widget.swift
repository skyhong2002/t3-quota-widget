import SwiftUI
import WidgetKit
import Foundation

struct Quota: Codable { var title: String; var percentLeft: Double; var window: Reset }
struct Reset: Codable { var resetsAt: String? }
struct Usage: Codable { var updatedAt: String; var usageRows: [Quota] }
struct Credits: Codable { var availableCount: Int; var nextExpiresAt: String? }
struct Account: Codable, Identifiable { var id: String; var provider: String; var label: String; var plan: String?; var resetCredits: Credits?; var usage: Usage? }
struct Snapshot: Codable { var accounts: [Account] }
struct Entry: TimelineEntry { let date: Date; let accounts: [Account] }
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), accounts: []) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(300))))
    }
    func read() -> Entry {
        let root = Optional(URL(fileURLWithPath: "/Users/Shared/T3QuotaWidget", isDirectory: true))
        guard let root, let data = try? Data(contentsOf: root.appendingPathComponent("accounts.json")),
              let value = try? JSONDecoder().decode(Snapshot.self, from: data) else { return Entry(date: Date(), accounts: []) }
        return Entry(date: Date(), accounts: value.accounts)
    }
}
struct Tile: View {
    let entry: Entry
    func reset(_ raw: String?) -> String {
        guard let raw, let date = ISO8601DateFormatter().date(from: raw) else { return "未提供" }
        let minutes = max(0, Int(date.timeIntervalSince(entry.date) / 60))
        if minutes == 0 { return "已到期·待更新" }
        if minutes >= 1440 { return "\(minutes / 1440)天\(minutes % 1440 / 60)時" }
        return "\(minutes / 60)時\(minutes % 60)分"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text("T3 帳號額度").font(.system(size: 13, weight: .bold)); Spacer(); Text("剩餘 / 重置").font(.system(size: 8)).foregroundStyle(.secondary) }
            if entry.accounts.isEmpty { Spacer(); Text("請開啟 T3 帳號額度，等待資料同步。").font(.caption); Spacer() }
            ForEach(entry.accounts) { account in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(account.provider == "claude" ? "Claude" : "Codex").foregroundStyle(account.provider == "claude" ? Color.orange : Color.cyan)
                        Text(account.label).lineLimit(1).minimumScaleFactor(0.75)
                    }.font(.system(size: 9, weight: .semibold))
                    HStack(spacing: 4) {
                        Text((account.plan ?? "方案未提供").replacingOccurrences(of: " Subscription", with: "")).lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 0)
                        if let credits = account.resetCredits {
                            Text("重置券 \(credits.availableCount) · 到期 \(reset(credits.nextExpiresAt))").lineLimit(1).minimumScaleFactor(0.65)
                        }
                    }.font(.system(size: 7)).foregroundStyle(.secondary)
                    if let usage = account.usage {
                        ForEach(Array(usage.usageRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 5) {
                                Text(row.title.replacingOccurrences(of: "Weekly · ", with: "")).frame(width: 48, alignment: .leading).lineLimit(1)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.10))
                                        Capsule().fill(row.percentLeft < 15 ? Color.red : (account.provider == "claude" ? Color.orange : Color.cyan)).frame(width: max(0, g.size.width * row.percentLeft / 100))
                                    }
                                }.frame(height: 4)
                                Text("\(Int(row.percentLeft))%").monospacedDigit().frame(width: 28, alignment: .trailing)
                                Text(reset(row.window.resetsAt)).lineLimit(1).minimumScaleFactor(0.65).foregroundStyle(.secondary).frame(width: 60, alignment: .trailing)
                            }.font(.system(size: 8))
                        }
                    } else { Text("T3 尚無額度資料").font(.system(size: 8)).foregroundStyle(.secondary) }
                }
                if account.id != entry.accounts.last?.id { Divider() }
            }
            Spacer(minLength: 0)
            if let raw = entry.accounts.compactMap({ $0.usage?.updatedAt }).min(), let checked = ISO8601DateFormatter().date(from: raw) {
                HStack(spacing: 2) { Text("T3 資料："); Text(checked, style: .relative); if entry.date.timeIntervalSince(checked) > 900 { Text("· 未更新").foregroundStyle(.orange) } }.font(.system(size: 7)).foregroundStyle(.secondary)
            }
        }.containerBackground(.background, for: .widget)
    }
}
@main struct T3QuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "T3FiveAccounts", provider: Provider()) { Tile(entry: $0) }
            .configurationDisplayName("T3 五帳號額度")
            .description("同時顯示三個 Claude 與兩個 Codex 帳號的剩餘額度及重置時間。")
            .supportedFamilies([.systemLarge])
    }
}
