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
    var updatedAt: String; var todayUSD: Double; var yesterdayUSD: Double?; var monthUSD: Double; var projectedUSD: Double?
    var sources: [Source]; var devices: [Device]; var machines: [Machine]; var days: [Day]; var unpricedModels: Int
}
struct AccountPace: Codable {
    struct Window: Codable { var title: String; var percentLeft: Double; var elapsedPercent: Double; var resetsIn: Double; var runsOutIn: Double? }
    var provider: String; var name: String; var plan: String; var updatedAt: String; var worst: Int; var windows: [Window]
}
struct Snapshot: Codable { var accounts: [Account]; var pace: [AccountPace]?; var spend: Spend?; var computai: Ledger?; var language: String? }

/// Picks the Traditional Chinese or English string. The host publishes the language (default zh).
struct Words {
    let english: Bool
    func callAsFunction(_ zh: String, _ en: String) -> String { english ? en : zh }
    func span(_ seconds: Double) -> String {
        let minutes = max(0, Int(seconds / 60))
        if minutes >= 1440 { return english ? "\(minutes / 1440)d \(minutes % 1440 / 60)h" : "\(minutes / 1440)天\(minutes % 1440 / 60)時" }
        if minutes >= 60 { return english ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes / 60)時\(minutes % 60)分" }
        return english ? "\(minutes)m" : "\(minutes)分"
    }
    /// T3 window titles: Session, Weekly, Weekly · Fable.
    func window(_ title: String) -> String {
        let parts = title.components(separatedBy: " · ")
        let base = parts[0] == "Session" ? self("5 小時", "5-hour") : parts[0] == "Weekly" ? self("每週", "Weekly") : parts[0]
        guard parts.count > 1 else { return base }
        return english ? "\(parts[1]) \(base.lowercased())" : "\(parts[1]) \(base)"
    }
    func until(_ raw: String?, from date: Date) -> String {
        guard let raw, let reset = ISO8601DateFormatter().date(from: raw) else { return self("未提供", "n/a") }
        if reset.timeIntervalSince(date) < 60 { return self("已到期·待更新", "due · updating") }
        return span(reset.timeIntervalSince(date))
    }
    func plan(_ plan: String?) -> String { (plan ?? self("方案未提供", "Plan unknown")).replacingOccurrences(of: " Subscription", with: "") }
}

struct Entry: TimelineEntry {
    let date: Date; let accounts: [Account]; var pace: [AccountPace] = []; var spend: Spend? = nil; var ledger: Ledger? = nil; var language = "zh"
    var t: Words { Words(english: language == "en") }
}
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
        return Entry(date: Date(), accounts: value.accounts, pace: value.pace ?? [], spend: value.spend, ledger: value.computai, language: value.language ?? "zh")
    }
}
func dollars(_ value: Double) -> String { "$" + value.formatted(.number.precision(.fractionLength(0))) }
func providerColor(_ provider: String) -> Color { provider == "claude" ? .orange : .cyan }
func providerName(_ provider: String) -> String { provider == "claude" ? "Claude" : "Codex" }
func isStale(_ raw: String?, at date: Date) -> Bool {
    guard let raw, let checked = ISO8601DateFormatter().date(from: raw) else { return true }
    return date.timeIntervalSince(checked) > 900
}

/// Title, where the data comes from, and a summary on the right that turns into a stale warning.
/// Lays the content out at full size and, if it is taller than the widget, at smaller scales until it fits.
/// Every font and fixed width is multiplied by the scale, so the whole widget shrinks evenly.
struct Fitted<Content: View>: View {
    @ViewBuilder let content: (CGFloat) -> Content
    var body: some View {
        ViewThatFits(in: .vertical) {
            content(1); content(0.92); content(0.84); content(0.76); content(0.68); content(0.6)
        }
    }
}

/// Title, where the data comes from, and a summary on the right that turns into a stale warning.
struct WidgetHeader: View {
    let title: String
    let source: String
    var trailing: String = ""
    var trailingColor: Color = .secondary
    var updatedAt: String?
    let date: Date
    let t: Words
    var s: CGFloat = 1
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6 * s) {
            Text(title).font(.system(size: 14 * s, weight: .bold)).layoutPriority(1)
            if !source.isEmpty { Text(source).font(.system(size: 10 * s)).foregroundStyle(.secondary) }
            Spacer(minLength: 4)
            if updatedAt != nil && isStale(updatedAt, at: date) {
                Text(t("資料未更新", "Data is stale")).foregroundStyle(.orange)
            } else {
                Text(trailing).foregroundStyle(trailingColor)
            }
        }.font(.system(size: 10 * s)).lineLimit(1)
    }
}

struct Tile: View {
    let entry: Entry
    var body: some View {
        Fitted { s in layout(s) }.containerBackground(.background, for: .widget)
    }
    func layout(_ s: CGFloat) -> some View {
        let t = entry.t
        let checked = entry.accounts.compactMap { $0.usage?.updatedAt }.min()
        return VStack(alignment: .leading, spacing: 4 * s) {
            WidgetHeader(title: t("帳號額度", "Account Quotas"), source: "T3 Code", trailing: t("剩餘 / 重置", "Left / resets in"), updatedAt: checked, date: entry.date, t: t, s: s)
            if entry.accounts.isEmpty { Text(t("請開啟 T3 帳號額度，等待資料同步。", "Open the T3 quota app and wait for the first sync.")).font(.system(size: 11 * s)) }
            ForEach(entry.accounts) { account in
                VStack(alignment: .leading, spacing: 2 * s) {
                    HStack(spacing: 4 * s) {
                        Text(providerName(account.provider)).foregroundStyle(providerColor(account.provider))
                        Text(account.label).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(t.plan(account.plan)).font(.system(size: 10 * s, weight: .regular)).foregroundStyle(.secondary).lineLimit(1)
                    }.font(.system(size: 12 * s, weight: .semibold))
                    if let credits = account.resetCredits {
                        Text(t("重置券 \(credits.availableCount) · 到期 \(t.until(credits.nextExpiresAt, from: entry.date))",
                               "\(credits.availableCount) reset credit\(credits.availableCount == 1 ? "" : "s") · expire in \(t.until(credits.nextExpiresAt, from: entry.date))"))
                            .font(.system(size: 9 * s)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let usage = account.usage {
                        ForEach(Array(usage.usageRows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 5 * s) {
                                Text(t.window(row.title)).frame(width: 70 * s, alignment: .leading).lineLimit(1)
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.primary.opacity(0.10))
                                        Capsule().fill(row.percentLeft < 15 ? Color.red : providerColor(account.provider)).frame(width: max(0, g.size.width * row.percentLeft / 100))
                                    }
                                }.frame(height: 4 * s)
                                Text("\(Int(row.percentLeft))%").monospacedDigit().frame(width: 30 * s, alignment: .trailing)
                                Text(t.until(row.window.resetsAt, from: entry.date)).lineLimit(1).foregroundStyle(.secondary).frame(width: 64 * s, alignment: .trailing)
                            }.font(.system(size: 11 * s))
                        }
                    } else { Text(t("T3 尚無額度資料", "No quota from T3 yet")).font(.system(size: 9 * s)).foregroundStyle(.secondary) }
                }
                if account.id != entry.accounts.last?.id { Divider() }
            }
            Spacer(minLength: 0)
            if let spend = entry.spend {
                HStack(spacing: 4 * s) {
                    Text("ComputAI").foregroundStyle(.secondary)
                    Text(t("今日 \(dollars(spend.todayUSD))", "Today \(dollars(spend.todayUSD))")).fontWeight(.semibold)
                    Text(t("本月 \(dollars(spend.monthUSD))", "Month \(dollars(spend.monthUSD))")).fontWeight(.semibold)
                    if spend.unpricedModels > 0 { Text(t("+ 未計價", "+ unpriced")).foregroundStyle(.orange) }
                    Spacer(minLength: 0)
                    if spend.devices > 1 { Text(t("\(spend.devices) 台", "\(spend.devices) computers")).foregroundStyle(.secondary) }
                }.font(.system(size: 9 * s)).monospacedDigit().lineLimit(1)
            }
        }
    }
}
struct T3QuotaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "T3FiveAccounts", provider: Provider()) { Tile(entry: $0) }
            .configurationDisplayName("T3 五帳號額度 · Five Accounts")
            .description("資料來源：T3 Code。三個 Claude 與兩個 Codex 帳號的剩餘額度及重置時間。")
            .supportedFamilies([.systemLarge])
    }
}

struct SingleEntry: TimelineEntry { let date: Date; let account: Account?; var language = "zh"; var t: Words { Words(english: language == "en") } }
struct FixedProvider: TimelineProvider {
    let index: Int
    func placeholder(in context: Context) -> SingleEntry { read() }
    func getSnapshot(in context: Context, completion: @escaping (SingleEntry) -> Void) { completion(read()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SingleEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(300))))
    }
    func read() -> SingleEntry {
        let snapshot = Provider().read()
        return SingleEntry(date: snapshot.date, account: snapshot.accounts.indices.contains(index) ? snapshot.accounts[index] : nil, language: snapshot.language)
    }
}
struct SingleTile: View {
    let entry: SingleEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        Fitted { s in layout(s) }.containerBackground(.background, for: .widget)
    }
    func layout(_ s: CGFloat) -> some View {
        let t = entry.t
        let large = family == .systemLarge
        return VStack(alignment: .leading, spacing: (large ? 14 : 4) * s) {
            if let account = entry.account {
                let color = providerColor(account.provider)
                HStack(alignment: .firstTextBaseline) {
                    Text(providerName(account.provider)).font(.system(size: (large ? 20 : 18) * s, weight: .bold)).foregroundStyle(color)
                    Spacer()
                    Text(t.plan(account.plan)).font(.system(size: 12 * s, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(account.label).font(.system(size: 13 * s, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if isStale(account.usage?.updatedAt, at: entry.date) && account.usage != nil {
                        Text(t("資料未更新", "Data is stale")).foregroundStyle(.orange)
                    } else {
                        Text("T3 Code").foregroundStyle(.secondary)
                    }
                }.font(.system(size: 10 * s))
                if let usage = account.usage {
                    ForEach(Array(usage.usageRows.enumerated()), id: \.offset) { _, row in
                        VStack(spacing: 4 * s) {
                            HStack {
                                Text(t.window(row.title)).font(.system(size: 12 * s, weight: .medium))
                                Spacer()
                                Text(t("剩 \(Int(row.percentLeft))%", "\(Int(row.percentLeft))% left")).font(.system(size: 14 * s, weight: .semibold)).monospacedDigit()
                                Text(t.until(row.window.resetsAt, from: entry.date)).font(.system(size: 11 * s)).foregroundStyle(.secondary)
                            }.lineLimit(1)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.primary.opacity(0.10))
                                    Capsule().fill(row.percentLeft < 15 ? .red : color).frame(width: g.size.width * row.percentLeft / 100)
                                }
                            }.frame(height: 6 * s)
                        }
                    }
                    if large { Spacer(minLength: 0) }
                    if let credits = account.resetCredits {
                        Text(t("重置券 \(credits.availableCount) 張 · 到期 \(t.until(credits.nextExpiresAt, from: entry.date))",
                               "\(credits.availableCount) reset credit\(credits.availableCount == 1 ? "" : "s") · expire in \(t.until(credits.nextExpiresAt, from: entry.date))"))
                            .font(.system(size: 12 * s)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if large, let raw = usage.usageRows.first?.window.resetsAt, let reset = ISO8601DateFormatter().date(from: raw) {
                        HStack { Text(t("下次重置", "Next reset")); Text(reset, format: .dateTime.month().day().hour().minute()) }.font(.system(size: 12 * s)).foregroundStyle(.secondary)
                    }
                } else { Text(t("T3 尚無此帳號的額度資料", "No quota from T3 for this account yet")).font(.system(size: 11 * s)).foregroundStyle(.secondary) }
            } else {
                Text(t("等待 T3 帳號資料", "Waiting for T3 accounts")).font(.system(size: 15 * s, weight: .semibold))
                Text(t("請確認 T3 帳號設定與背景同步。", "Check the T3 account settings and the background sync.")).font(.system(size: 13 * s)).foregroundStyle(.secondary)
            }
            if !large { Spacer(minLength: 0) }
        }
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
            .description("資料來源：T3 Code。此帳號的訂閱方案、額度與重置狀態。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct SpendTile: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        let t = entry.t
        let small = family == .systemSmall
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: t("AI 花費", "AI Spend"), source: small ? "" : "ComputAI", trailing: small ? "" : t("照 API 價格", "at API prices"),
                         updatedAt: entry.spend?.updatedAt, date: entry.date, t: t)
            if let spend = entry.spend {
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t("本月", "This month")).font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(dollars(spend.monthUSD)).font(.system(size: 32, weight: .bold)).minimumScaleFactor(0.6)
                    }
                    if !small {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t("今日", "Today")).font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(dollars(spend.todayUSD)).font(.system(size: 22, weight: .semibold))
                        }
                        if let yesterday = entry.ledger?.yesterdayUSD {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t("昨日", "Yesterday")).font(.system(size: 11)).foregroundStyle(.secondary)
                                Text(dollars(yesterday)).font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.monospacedDigit().lineLimit(1)
                if small {
                    Text(t("今日 \(dollars(spend.todayUSD))", "Today \(dollars(spend.todayUSD))")).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    let time = ISO8601DateFormatter().date(from: spend.updatedAt)?.formatted(date: .omitted, time: .shortened) ?? ""
                    if small {
                        Text("ComputAI · \(time)")
                    } else {
                        if spend.devices > 1 { Text(t("\(spend.devices) 台電腦 ·", "\(spend.devices) computers ·")) }
                        Text(t("\(time) 更新", "updated \(time)"))
                    }
                }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                if spend.unpricedModels > 0 {
                    Text(t("另有 \(spend.unpricedModels) 個模型未計價", "\(spend.unpricedModels) models have no price")).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(1).minimumScaleFactor(0.8)
                }
            } else {
                NoLedger(t: t)
            }
        }.containerBackground(.background, for: .widget)
    }
}
struct SpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "T3Spend", provider: Provider()) { SpendTile(entry: $0) }
            .configurationDisplayName("AI 花費 · AI Spend")
            .description("資料來源：ComputAI。本月、今日與昨日的 Claude、Codex 用量，以 API 價格換算，涵蓋每台電腦。")
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
