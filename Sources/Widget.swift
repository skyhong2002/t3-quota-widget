import SwiftUI
import WidgetKit
import Foundation

struct Quota: Codable { var title: String; var percentLeft: Double; var window: Reset }
struct Reset: Codable { var resetsAt: String? }
struct Usage: Codable { var updatedAt: String; var usageRows: [Quota] }
struct Credits: Codable { var availableCount: Int; var nextExpiresAt: String? }
struct Account: Codable, Identifiable { var id: String; var provider: String; var label: String; var plan: String?; var resetCredits: Credits?; var usage: Usage? }
struct Spend: Codable { var todayUSD: Double; var monthUSD: Double; var devices: Int; var unpricedModels: Int; var updatedAt: String }
struct Ledger: Codable {
    struct Source: Codable { var provider: String; var usd: Double }
    struct Device: Codable { var name: String; var usd: Double; var stale: Bool }
    struct Machine: Codable { var name: String; var online: Bool; var cpu: Int; var gpu: Int?; var memory: Int?; var watts: Int? }
    struct Day: Codable { var day: String; var claude: Double; var codex: Double }
    struct Pace: Codable { var provider: String; var title: String; var percentLeft: Double; var elapsedPercent: Double?; var resetsIn: Double?; var runsOutIn: Double?; var stale: Bool }
    var updatedAt: String; var todayUSD: Double; var yesterdayUSD: Double?; var monthUSD: Double; var projectedUSD: Double?
    var sources: [Source]; var devices: [Device]; var machines: [Machine]; var days: [Day]; var pace: [Pace]; var unpricedModels: Int
}
struct Snapshot: Codable { var accounts: [Account]; var spend: Spend?; var computai: Ledger? }
struct Entry: TimelineEntry { let date: Date; let accounts: [Account]; var spend: Spend? = nil; var ledger: Ledger? = nil }
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
        return Entry(date: Date(), accounts: value.accounts, spend: value.spend, ledger: value.computai)
    }
}
func dollars(_ value: Double) -> String { "$" + value.formatted(.number.precision(.fractionLength(0))) }
func shortDollars(_ value: Double) -> String { value >= 10_000 ? "$" + (value / 1000).formatted(.number.precision(.fractionLength(1))) + "k" : dollars(value) }
func span(_ seconds: Double) -> String {
    let minutes = max(0, Int(seconds / 60))
    if minutes >= 1440 { return "\(minutes / 1440)天\(minutes % 1440 / 60)時" }
    if minutes >= 60 { return "\(minutes / 60)時\(minutes % 60)分" }
    return "\(minutes)分"
}
func providerColor(_ provider: String) -> Color { provider == "claude" ? .orange : .cyan }
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
            if let spend = entry.spend {
                HStack(spacing: 4) {
                    Text("API 等值").foregroundStyle(.secondary)
                    Text("今日 \(dollars(spend.todayUSD))").fontWeight(.semibold)
                    Text("本月 \(dollars(spend.monthUSD))").fontWeight(.semibold)
                    if spend.unpricedModels > 0 { Text("+ 未計價").foregroundStyle(.orange) }
                    Spacer(minLength: 0)
                    if spend.devices > 1 { Text("\(spend.devices) 台").foregroundStyle(.secondary) }
                }.font(.system(size: 8)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            }
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

struct SingleEntry: TimelineEntry { let date: Date; let account: Account? }
struct FixedProvider: TimelineProvider {
    let index: Int
    func placeholder(in context: Context) -> SingleEntry { read() }
    func getSnapshot(in context: Context, completion: @escaping (SingleEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SingleEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(300))))
    }
    func read() -> SingleEntry {
        let snapshot = Provider().read()
        return SingleEntry(date: snapshot.date, account: snapshot.accounts.indices.contains(index) ? snapshot.accounts[index] : nil)
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
                Text("等待 T3 帳號資料").font(.headline)
                Text("請確認 T3 帳號設定與背景同步。").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }.containerBackground(.background, for: .widget)
    }
}
struct FixedAccountWidget: Widget {
    let index: Int
    let name: String
    init() { self.index = 0; self.name = "Claude 1" }
    init(index: Int, name: String) { self.index = index; self.name = name }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "T3Account" + String(index), provider: FixedProvider(index: index)) { SingleTile(entry: $0) }
            .configurationDisplayName(name)
            .description("此帳號的訂閱方案、額度與重置狀態。帳號身分由 T3 設定取得。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct SpendTile: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("AI 花費").font(.system(size: 13, weight: .bold))
                Spacer()
                Text("API 等值").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            if let spend = entry.spend {
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("本月").font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(dollars(spend.monthUSD)).font(.system(size: 30, weight: .bold)).minimumScaleFactor(0.6)
                    }
                    if family != .systemSmall {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("今日").font(.system(size: 10)).foregroundStyle(.secondary)
                            Text(dollars(spend.todayUSD)).font(.system(size: 20, weight: .semibold))
                        }
                        if let yesterday = entry.ledger?.yesterdayUSD {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("昨日").font(.system(size: 10)).foregroundStyle(.secondary)
                                Text(dollars(yesterday)).font(.system(size: 20, weight: .semibold)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.monospacedDigit().lineLimit(1)
                if family == .systemSmall {
                    Text("今日 \(dollars(spend.todayUSD))").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    if spend.devices > 1 { Text("\(spend.devices) 台電腦 ·") }
                    if let checked = ISO8601DateFormatter().date(from: spend.updatedAt) {
                        if entry.date.timeIntervalSince(checked) > 900 { Text("未更新").foregroundStyle(.orange) } else { Text("\(checked.formatted(date: .omitted, time: .shortened)) 更新") }
                    }
                }.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                if spend.unpricedModels > 0 {
                    Text("另有 \(spend.unpricedModels) 個模型未計價").font(.system(size: 9)).foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.8)
                }
            } else {
                Spacer(minLength: 0)
                Text("等待 ComputAI 資料").font(.system(size: 12, weight: .medium))
                Text("需要安裝 computai").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }.containerBackground(.background, for: .widget)
    }
}
struct SpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "T3Spend", provider: Provider()) { SpendTile(entry: $0) }
            .configurationDisplayName("AI 花費")
            .description("本月與今日的 Claude、Codex 用量，以 API 價格換算，涵蓋 ComputAI 讀得到的每台電腦。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
struct ComputAIWidgets: WidgetBundle {
    var body: some Widget {
        SpendWidget()
        PaceWidget()
        TrendWidget()
        DeviceSpendWidget()
        MachinesWidget()
    }
}
@main struct T3WidgetBundle: WidgetBundle {
    var body: some Widget {
        ComputAIWidgets().body
        FixedAccountWidget(index: 0, name: "Claude 1 · 第一個帳號")
        FixedAccountWidget(index: 1, name: "Claude 2 · 第二個帳號")
        FixedAccountWidget(index: 2, name: "Claude 3 · 第三個帳號")
        FixedAccountWidget(index: 3, name: "Codex 1 · 第一個帳號")
        FixedAccountWidget(index: 4, name: "Codex 2 · 第二個帳號")
        T3QuotaWidget()
    }
}
