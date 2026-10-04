import SwiftUI
import WidgetKit

// Widgets drawn from the running ComputAI dashboard (computai --web): machines, spend per device and
// the last 14 days. 額度速度 is projected from the T3 quotas of every account.

struct LedgerHeader: View {
    let title: String
    let trailing: String
    let ledger: Ledger?
    let date: Date
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 13, weight: .bold))
            Spacer()
            if let ledger, let checked = ISO8601DateFormatter().date(from: ledger.updatedAt), date.timeIntervalSince(checked) > 900 {
                Text("未更新").foregroundStyle(.orange)
            } else {
                Text(trailing).foregroundStyle(.secondary)
            }
        }.font(.system(size: 9)).lineLimit(1)
    }
}

struct NoLedger: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text("等待 ComputAI 儀表板").font(.system(size: 12, weight: .medium))
            Text("computai --web 沒有在執行").font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

struct MachinesTile: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        let large = family == .systemLarge
        VStack(alignment: .leading, spacing: large ? 8 : 4) {
            let machines = entry.ledger?.machines ?? []
            LedgerHeader(title: "機器", trailing: "\(machines.filter(\.online).count)/\(machines.count) 在線", ledger: entry.ledger, date: entry.date)
            if entry.ledger == nil { NoLedger() } else {
                Grid(alignment: .trailing, horizontalSpacing: large ? 12 : 8, verticalSpacing: large ? 7 : 2) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        Text("CPU"); Text("GPU")
                        if large { Text("記憶體") }
                        Text("功耗")
                    }.font(.system(size: large ? 9 : 7)).foregroundStyle(.secondary)
                    ForEach(machines, id: \.name) { machine in
                        GridRow {
                            HStack(spacing: 4) {
                                Circle().fill(machine.online ? Color.green : Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
                                Text(machine.name).lineLimit(1).minimumScaleFactor(0.8)
                            }.frame(maxWidth: .infinity, alignment: .leading).gridColumnAlignment(.leading)
                            Text("\(machine.cpu)%").foregroundStyle(machine.cpu >= 80 ? .orange : .primary)
                            Text(machine.gpu.map { "\($0)%" } ?? "–").foregroundStyle(machine.gpu == nil ? .secondary : .primary)
                            if large { Text(machine.memory.map { "\($0)%" } ?? "–").foregroundStyle((machine.memory ?? 0) >= 90 ? .orange : .primary) }
                            Text(machine.watts.map { "\($0) W" } ?? "–").foregroundStyle(machine.watts == nil ? .secondary : .primary)
                        }.opacity(machine.online ? 1 : 0.5)
                    }
                }.font(.system(size: large ? 12 : 9)).monospacedDigit()
                Spacer(minLength: 0)
            }
        }.containerBackground(.background, for: .widget)
    }
}

struct DeviceSpendTile: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LedgerHeader(title: "各機器花費", trailing: entry.ledger.map { "本月 \(dollars($0.monthUSD))" } ?? "", ledger: entry.ledger, date: entry.date)
            if let ledger = entry.ledger {
                let used = ledger.devices.filter { $0.usd >= 0.5 }
                let top = used.first?.usd ?? 1
                Spacer(minLength: 0)
                ForEach(used.prefix(5), id: \.name) { device in
                    HStack(spacing: 6) {
                        Text(device.name).lineLimit(1).minimumScaleFactor(0.8).frame(width: 78, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(Color.accentColor.opacity(device.stale ? 0.3 : 0.8)).frame(width: max(3, g.size.width * device.usd / top))
                        }.frame(height: 6)
                        Text(dollars(device.usd)).monospacedDigit().frame(width: 44, alignment: .trailing)
                    }.font(.system(size: 10))
                }
                Spacer(minLength: 0)
                let idle = ledger.devices.count - min(used.count, 5)
                if idle > 0 { Text("另 \(idle) 台本月沒有用量").font(.system(size: 8)).foregroundStyle(.secondary) }
            } else { NoLedger() }
        }.containerBackground(.background, for: .widget)
    }
}

struct TrendTile: View {
    let entry: Entry
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            let trailing = entry.ledger.map { l in (l.yesterdayUSD.map { "昨日 \(dollars($0)) · " } ?? "") + "今日 \(dollars(l.todayUSD))" } ?? ""
            LedgerHeader(title: "14 天花費", trailing: trailing, ledger: entry.ledger, date: entry.date)
            if let days = entry.ledger?.days, !days.isEmpty {
                let top = max(1, days.map { $0.claude + $0.codex }.max() ?? 1)
                GeometryReader { g in
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                            VStack(spacing: 0) {
                                Rectangle().fill(Color.cyan).frame(height: g.size.height * day.codex / top)
                                Rectangle().fill(Color.orange).frame(height: g.size.height * day.claude / top)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 1.5))
                            .opacity(index == days.count - 1 ? 0.55 : 1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }
                HStack {
                    Text(days.first?.day ?? "")
                    Spacer()
                    HStack(spacing: 3) { Circle().fill(Color.orange).frame(width: 5, height: 5); Text("Claude") }
                    HStack(spacing: 3) { Circle().fill(Color.cyan).frame(width: 5, height: 5); Text("Codex") }
                    Text("· 最高 \(dollars(top))")
                    Spacer()
                    Text("今日")
                }.font(.system(size: 8)).foregroundStyle(.secondary)
            } else { NoLedger() }
        }.containerBackground(.background, for: .widget)
    }
}

struct PaceBar: View {
    let provider: String
    let window: AccountPace.Window
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(providerColor(provider)).frame(width: g.size.width * window.percentLeft / 100)
                // Time left in the window: a bar shorter than this mark is burning faster than time.
                Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 1.5).offset(x: g.size.width * (100 - window.elapsedPercent) / 100)
            }
        }
    }
}

struct PaceStatus: View {
    let window: AccountPace.Window
    var body: some View {
        if window.runsOutIn == 0 {
            Text("已用完 · \(span(window.resetsIn))後重置").foregroundStyle(.red)
        } else if let out = window.runsOutIn {
            Text("\(span(out))後用完 · \(span(window.resetsIn))後重置").foregroundStyle(.orange)
        } else {
            Text("撐得到重置 · \(span(window.resetsIn))").foregroundStyle(.secondary)
        }
    }
}

struct PaceTile: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    func stale(_ account: AccountPace) -> Bool {
        guard let checked = ISO8601DateFormatter().date(from: account.updatedAt) else { return true }
        return entry.date.timeIntervalSince(checked) > 900
    }
    var body: some View {
        let large = family == .systemLarge
        let late = entry.pace.filter { $0.windows.contains { $0.runsOutIn != nil } }.count
        VStack(alignment: .leading, spacing: large ? 7 : 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("額度速度").font(.system(size: 13, weight: .bold))
                Spacer()
                Text(late == 0 ? "每個帳號都撐得到重置" : "\(late) 個帳號會提早用完").foregroundStyle(late == 0 ? Color.secondary : Color.orange)
            }.font(.system(size: 9)).lineLimit(1)
            if entry.pace.isEmpty {
                Spacer(minLength: 0)
                Text("等待 T3 帳號資料").font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
            }
            ForEach(Array(entry.pace.enumerated()), id: \.offset) { _, account in
                let name = HStack(spacing: 4) {
                    Text(account.provider == "claude" ? "Claude" : "Codex").foregroundStyle(providerColor(account.provider)).fontWeight(.semibold)
                    Text(account.name).lineLimit(1).truncationMode(.middle)
                }
                if large {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { name; Spacer(); Text(stale(account) ? "未更新" : account.plan).foregroundStyle(stale(account) ? Color.orange : Color.secondary) }
                            .font(.system(size: 10))
                        ForEach(Array(account.windows.enumerated()), id: \.offset) { _, window in
                            HStack(spacing: 6) {
                                Text(window.title).frame(width: 58, alignment: .leading).lineLimit(1)
                                PaceBar(provider: account.provider, window: window).frame(height: 4)
                                Text("\(Int(window.percentLeft))%").monospacedDigit().frame(width: 28, alignment: .trailing)
                                PaceStatus(window: window).frame(width: 118, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.8)
                            }.font(.system(size: 9))
                        }
                    }.opacity(stale(account) ? 0.5 : 1)
                } else {
                    let window = account.windows[min(account.worst, account.windows.count - 1)]
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            name
                            Text(window.title).foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text("剩 \(Int(window.percentLeft))%").fontWeight(.semibold).monospacedDigit()
                        }.font(.system(size: 9))
                        HStack(spacing: 6) {
                            PaceBar(provider: account.provider, window: window).frame(height: 3)
                            PaceStatus(window: window).font(.system(size: 7)).lineLimit(1).frame(width: 112, alignment: .trailing)
                        }
                    }.opacity(stale(account) ? 0.5 : 1)
                }
            }
            Spacer(minLength: 0)
        }.containerBackground(.background, for: .widget)
    }
}

struct MachinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComputAIMachines", provider: Provider()) { MachinesTile(entry: $0) }
            .configurationDisplayName("機器")
            .description("每台機器是否在線，以及 CPU、GPU、功耗。資料來自 ComputAI。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct DeviceSpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComputAIDeviceSpend", provider: Provider()) { DeviceSpendTile(entry: $0) }
            .configurationDisplayName("各機器花費")
            .description("本月每台電腦的 Claude 與 Codex 用量，以 API 價格換算。")
            .supportedFamilies([.systemMedium])
    }
}
struct TrendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComputAITrend", provider: Provider()) { TrendTile(entry: $0) }
            .configurationDisplayName("14 天花費")
            .description("最近 14 天每天的 Claude 與 Codex 用量，以 API 價格換算。")
            .supportedFamilies([.systemMedium])
    }
}
struct PaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComputAIPace", provider: Provider()) { PaceTile(entry: $0) }
            .configurationDisplayName("額度速度")
            .description("五個帳號照目前的使用速度，每個額度會不會在重置前用完。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
