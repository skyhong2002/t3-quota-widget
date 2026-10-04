import SwiftUI
import WidgetKit

// Widgets drawn from the running ComputAI dashboard (computai --web): machines, spend per device and
// the last 14 days. 額度速度 is projected from the T3 quotas of every account.

struct NoLedger: View {
    let t: Words
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer(minLength: 0)
            Text(t("等待 ComputAI 儀表板", "Waiting for the ComputAI dashboard")).font(.system(size: 13, weight: .medium))
            Text(t("computai --web 沒有在執行", "computai --web is not running")).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

struct MachinesTile: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        Fitted { s in layout(s) }.containerBackground(.background, for: .widget)
    }
    func layout(_ s: CGFloat) -> some View {
        let t = entry.t
        let large = family == .systemLarge
        let machines = entry.ledger?.machines ?? []
        return VStack(alignment: .leading, spacing: (large ? 10 : 4) * s) {
            WidgetHeader(title: t("機器", "Machines"), source: "ComputAI",
                         trailing: t("\(machines.filter(\.online).count)/\(machines.count) 在線", "\(machines.filter(\.online).count)/\(machines.count) online"),
                         updatedAt: entry.ledger?.updatedAt, date: entry.date, t: t, s: s)
            if entry.ledger == nil { NoLedger(t: t) } else {
                Grid(alignment: .trailing, horizontalSpacing: (large ? 14 : 10) * s, verticalSpacing: (large ? 13 : 1.5) * s) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        Text("CPU"); Text("GPU")
                        if large { Text(t("記憶體", "Memory")) }
                        Text(t("功耗", "Power"))
                    }.font(.system(size: (large ? 10 : 8) * s)).foregroundStyle(.secondary)
                    ForEach(machines, id: \.name) { machine in
                        GridRow {
                            HStack(spacing: 5 * s) {
                                Circle().fill(machine.online ? Color.green : Color.secondary.opacity(0.4)).frame(width: 6 * s, height: 6 * s)
                                Text(machine.name).lineLimit(1).truncationMode(.middle)
                            }.frame(maxWidth: .infinity, alignment: .leading).gridColumnAlignment(.leading)
                            Text("\(machine.cpu)%").foregroundStyle(machine.cpu >= 80 ? .orange : .primary)
                            Text(machine.gpu.map { "\($0)%" } ?? "–").foregroundStyle(machine.gpu == nil ? .secondary : .primary)
                            if large { Text(machine.memory.map { "\($0)%" } ?? "–").foregroundStyle((machine.memory ?? 0) >= 90 ? .orange : .primary) }
                            Text(machine.watts.map { "\($0) W" } ?? "–").foregroundStyle(machine.watts == nil ? .secondary : .primary)
                        }.opacity(machine.online ? 1 : 0.5)
                    }
                }.font(.system(size: (large ? 15 : 10.5) * s)).monospacedDigit()
                Spacer(minLength: 0)
            }
        }
    }
}

struct DeviceSpendTile: View {
    let entry: Entry
    var body: some View {
        let t = entry.t
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: t("各機器花費", "Spend by Computer"), source: "ComputAI",
                         trailing: entry.ledger.map { t("本月 \(dollars($0.monthUSD))", "Month \(dollars($0.monthUSD))") } ?? "",
                         updatedAt: entry.ledger?.updatedAt, date: entry.date, t: t)
            if let ledger = entry.ledger {
                let used = ledger.devices.filter { $0.usd >= 0.5 }
                let top = used.first?.usd ?? 1
                Spacer(minLength: 0)
                ForEach(used.prefix(4), id: \.name) { device in
                    HStack(spacing: 8) {
                        Text(device.name).lineLimit(1).minimumScaleFactor(0.8).frame(width: 96, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(Color.accentColor.opacity(device.stale ? 0.3 : 0.8)).frame(width: max(3, g.size.width * device.usd / top))
                        }.frame(height: 7)
                        Text(dollars(device.usd)).fontWeight(.semibold).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }.font(.system(size: 13))
                }
                Spacer(minLength: 0)
                let idle = ledger.devices.count - min(used.count, 4)
                if idle > 0 { Text(t("另 \(idle) 台本月沒有用量", "\(idle) more with no usage this month")).font(.system(size: 10)).foregroundStyle(.secondary) }
            } else { NoLedger(t: t) }
        }.containerBackground(.background, for: .widget)
    }
}

struct TrendTile: View {
    let entry: Entry
    var body: some View {
        let t = entry.t
        VStack(alignment: .leading, spacing: 6) {
            let trailing = entry.ledger.map { t("今日 \(dollars($0.todayUSD))", "Today \(dollars($0.todayUSD))") } ?? ""
            WidgetHeader(title: t("14 天花費", "14-Day Spend"), source: "ComputAI", trailing: trailing, updatedAt: entry.ledger?.updatedAt, date: entry.date, t: t)
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
                HStack(spacing: 6) {
                    Text(days.first?.day ?? "")
                    Spacer()
                    HStack(spacing: 3) { Circle().fill(Color.orange).frame(width: 6, height: 6); Text("Claude") }
                    HStack(spacing: 3) { Circle().fill(Color.cyan).frame(width: 6, height: 6); Text("Codex") }
                    Text(t("最高 \(dollars(top))", "Peak \(dollars(top))"))
                    Spacer()
                    Text(t("今日", "Today"))
                }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            } else { NoLedger(t: t) }
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
                Rectangle().fill(Color.primary.opacity(0.75)).frame(width: 2).offset(x: g.size.width * (100 - window.elapsedPercent) / 100 - 1)
            }
        }
    }
}

struct PaceStatus: View {
    let window: AccountPace.Window
    let t: Words
    var short = false
    var body: some View {
        if window.runsOutIn == 0 {
            Text(short ? t("已用完", "Used up") : t("已用完 · \(t.span(window.resetsIn))後重置", "Used up · resets in \(t.span(window.resetsIn))")).foregroundStyle(.red)
        } else if let out = window.runsOutIn {
            Text(short ? t("\(t.span(out))後用完", "Out in \(t.span(out))")
                       : t("\(t.span(out))後用完 · \(t.span(window.resetsIn))後重置", "Out in \(t.span(out)) · resets in \(t.span(window.resetsIn))")).foregroundStyle(.orange)
        } else {
            Text(short ? t("撐得到重置", "On track") : t("撐得到重置 · \(t.span(window.resetsIn))", "On track · resets in \(t.span(window.resetsIn))")).foregroundStyle(.secondary)
        }
    }
}

struct PaceTile: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        Fitted { s in layout(s) }.containerBackground(.background, for: .widget)
    }
    func layout(_ s: CGFloat) -> some View {
        let t = entry.t
        let large = family == .systemLarge
        let late = entry.pace.filter { $0.windows.contains { $0.runsOutIn != nil } }.count
        return VStack(alignment: .leading, spacing: (large ? 9 : 5) * s) {
            WidgetHeader(title: t("額度速度", "Limit Pace"), source: "T3 Code",
                         trailing: late == 0 ? t("都撐得到重置", "All on track") : t("\(late) 個帳號會提早用完", "\(late) accounts run out early"),
                         trailingColor: late == 0 ? .secondary : .orange,
                         updatedAt: entry.pace.map(\.updatedAt).min(), date: entry.date, t: t, s: s)
            if entry.pace.isEmpty {
                Text(t("等待 T3 帳號資料", "Waiting for T3 accounts")).font(.system(size: 13 * s, weight: .medium))
            }
            ForEach(Array(entry.pace.enumerated()), id: \.offset) { _, account in
                if large {
                    VStack(alignment: .leading, spacing: 4 * s) {
                        HStack(alignment: .firstTextBaseline, spacing: 5 * s) {
                            Text(providerName(account.provider)).foregroundStyle(providerColor(account.provider)).fontWeight(.bold)
                            Text(account.name).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(account.plan).font(.system(size: 10 * s)).foregroundStyle(.secondary).lineLimit(1)
                        }.font(.system(size: 14 * s))
                        ForEach(Array(account.windows.enumerated()), id: \.offset) { _, window in
                            HStack(spacing: 7 * s) {
                                Text(t.window(window.title)).frame(width: 86 * s, alignment: .leading).lineLimit(1)
                                PaceBar(provider: account.provider, window: window).frame(height: 6 * s)
                                Text("\(Int(window.percentLeft))%").fontWeight(.semibold).monospacedDigit().frame(width: 34 * s, alignment: .trailing)
                                PaceStatus(window: window, t: t, short: true).frame(width: 90 * s, alignment: .trailing).lineLimit(1)
                            }.font(.system(size: 12 * s))
                        }
                    }
                } else {
                    // One line per account: its most urgent window.
                    let window = account.windows[min(account.worst, account.windows.count - 1)]
                    HStack(spacing: 7 * s) {
                        Text(account.name).fontWeight(.semibold).foregroundStyle(providerColor(account.provider))
                            .lineLimit(1).truncationMode(.middle).frame(width: 80 * s, alignment: .leading)
                        Text(t.window(window.title)).font(.system(size: 10 * s)).foregroundStyle(.secondary).lineLimit(1).frame(width: 42 * s, alignment: .leading)
                        PaceBar(provider: account.provider, window: window).frame(height: 6 * s)
                        Text("\(Int(window.percentLeft))%").fontWeight(.semibold).monospacedDigit().frame(width: 34 * s, alignment: .trailing)
                        PaceStatus(window: window, t: t, short: true).font(.system(size: 11 * s)).lineLimit(1).frame(width: 88 * s, alignment: .trailing)
                    }.font(.system(size: 12 * s))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct MachinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComputAIMachines", provider: Provider()) { MachinesTile(entry: $0) }
            .configurationDisplayName("機器 · Machines")
            .description("資料來源：ComputAI。每台機器是否在線，以及 CPU、GPU、功耗。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
struct DeviceSpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComputAIDeviceSpend", provider: Provider()) { DeviceSpendTile(entry: $0) }
            .configurationDisplayName("各機器花費 · Spend by Computer")
            .description("資料來源：ComputAI。本月每台電腦的 Claude 與 Codex 用量，以 API 價格換算。")
            .supportedFamilies([.systemMedium])
    }
}
struct TrendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComputAITrend", provider: Provider()) { TrendTile(entry: $0) }
            .configurationDisplayName("14 天花費 · 14-Day Spend")
            .description("資料來源：ComputAI。最近 14 天每天的 Claude 與 Codex 用量，以 API 價格換算。")
            .supportedFamilies([.systemMedium])
    }
}
struct PaceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ComputAIPace", provider: Provider()) { PaceTile(entry: $0) }
            .configurationDisplayName("額度速度 · Limit Pace")
            .description("資料來源：T3 Code。五個帳號照目前的使用速度，每個額度會不會在重置前用完。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
