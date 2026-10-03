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
struct T3QuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "T3FiveAccounts", provider: Provider()) { Tile(entry: $0) }
            .configurationDisplayName("T3 五帳號額度")
            .description("同時顯示三個 Claude 與兩個 Codex 帳號的剩餘額度及重置時間。")
            .supportedFamilies([.systemLarge])
    }
}

import AppIntents
struct AccountEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "T3 帳號")
    static var defaultQuery = AccountQuery()
    let id: String
    let label: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(label)") }
}
struct AccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [AccountEntity] {
        Provider().read().accounts.map { AccountEntity(id: $0.id, label: ($0.provider == "claude" ? "Claude · " : "Codex · ") + $0.label) }
    }
}
struct AccountIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "選擇帳號"
    @Parameter(title: "帳號") var account: AccountEntity?
    init() {}
}
struct SingleEntry: TimelineEntry { let date: Date; let account: Account? }
struct SingleProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SingleEntry { SingleEntry(date: Date(), account: nil) }
    func snapshot(for configuration: AccountIntent, in context: Context) async -> SingleEntry { read(configuration) }
    func timeline(for configuration: AccountIntent, in context: Context) async -> Timeline<SingleEntry> {
        Timeline(entries: [read(configuration)], policy: .after(Date().addingTimeInterval(300)))
    }
    func read(_ configuration: AccountIntent) -> SingleEntry {
        let snapshot = Provider().read()
        return SingleEntry(date: snapshot.date, account: snapshot.accounts.first { $0.id == configuration.account?.id })
    }
}
struct SingleTile: View {
    let entry: SingleEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 16 : 4) {
            if let account = entry.account {
                let color: Color = account.provider == "claude" ? .orange : .cyan
                HStack(alignment: .firstTextBaseline) {
                    Text(account.provider == "claude" ? "Claude" : "Codex").font(.system(size: family == .systemLarge ? 20 : 18, weight: .bold)).foregroundStyle(color)
                    Spacer()
                    Text((account.plan ?? "方案未提供").replacingOccurrences(of: " Subscription", with: "")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Text(account.label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if let usage = account.usage {
                    ForEach(Array(usage.usageRows.enumerated()), id: \.offset) { _, row in
                        VStack(spacing: 4) {
                            HStack {
                                Text(row.title.replacingOccurrences(of: "Weekly · ", with: "")).font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text("\(Int(row.percentLeft))% 剩餘").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                                Text(Tile(entry: Entry(date: entry.date, accounts: [])).reset(row.window.resetsAt)).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.10))
                                    Capsule().fill(row.percentLeft < 15 ? .red : color).frame(width: g.size.width * row.percentLeft / 100)
                                }
                            }.frame(height: 6)
                        }
                    }
                    if family == .systemLarge { Spacer(minLength: 0) }
                    HStack(spacing: 3) {
                        if let credits = account.resetCredits {
                            Text("重置券 \(credits.availableCount) 張").fontWeight(.medium)
                            Text("· 到期 \(Tile(entry: Entry(date: entry.date, accounts: [])).reset(credits.nextExpiresAt))")
                        }
                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                    if family == .systemLarge, let raw = usage.usageRows.first?.window.resetsAt, let reset = ISO8601DateFormatter().date(from: raw) {
                        HStack { Text("下次重置"); Text(reset, format: .dateTime.month().day().hour().minute()) }.font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                } else { Text("T3 尚無此帳號的額度資料").font(.caption).foregroundStyle(.secondary) }
            } else {
                Text("選擇一個 T3 帳號").font(.headline)
                Text("在這張小工具上按右鍵 → 編輯小工具 → 帳號。").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }.containerBackground(.background, for: .widget)
    }
}
struct T3SingleWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "T3SingleAccount", intent: AccountIntent.self, provider: SingleProvider()) { SingleTile(entry: $0) }
            .configurationDisplayName("T3 單一帳號")
            .description("一張小工具顯示一個訂閱帳號，使用較大的文字。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
@main struct T3WidgetBundle: WidgetBundle {
    var body: some Widget { T3SingleWidget(); T3QuotaWidget() }
}
