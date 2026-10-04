import SwiftUI
import WidgetKit

// Widgets drawn from the running ComputAI dashboard (computai --web): machines, spend per device,
// the last 14 days and how fast each limit is burning.

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

struct PaceTile: View {
    let entry: Entry
    @Environment(\.widgetFamily) var family
    var body: some View {
        let large = family == .systemLarge
        VStack(alignment: .leading, spacing: large ? 12 : 5) {
            LedgerHeader(title: "額度速度", trailing: "照目前速度推算", ledger: entry.ledger, date: entry.date)
            if let pace = entry.ledger?.pace, !pace.isEmpty {
                ForEach(Array(pace.prefix(large ? 8 : 4).enumerated()), id: \.offset) { _, limit in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(limit.provider == "claude" ? "Claude" : "Codex").foregroundStyle(providerColor(limit.provider)).fontWeight(.semibold)
                            Text(limit.title)
                            Spacer()
                            Text("剩 \(Int(limit.percentLeft))%").fontWeight(.semibold).monospacedDigit()
                        }.font(.system(size: large ? 12 : 9))
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.primary.opacity(0.1))
                                Capsule().fill(limit.runsOutIn == nil ? providerColor(limit.provider) : .red).frame(width: g.size.width * limit.percentLeft / 100)
                                if let elapsed = limit.elapsedPercent {
                                    // Time left in the window: a bar shorter than this mark is burning faster than time.
                                    Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 1.5).offset(x: g.size.width * (100 - elapsed) / 100)
                                }
                            }
                        }.frame(height: large ? 5 : 4)
                        Group {
                            if let out = limit.runsOutIn, let reset = limit.resetsIn {
                                Text("\(span(out)) 後用完 · \(span(reset)) 後才重置").foregroundStyle(.orange)
                            } else if let reset = limit.resetsIn {
                                Text("撐得到重置 · \(span(reset)) 後重置").foregroundStyle(.secondary)
                            }
                        }.font(.system(size: large ? 10 : 7)).lineLimit(1)
                    }.opacity(limit.stale ? 0.5 : 1)
                }
                Spacer(minLength: 0)
            } else { NoLedger() }
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
            .description("照目前的使用速度，每個額度會不會在重置前用完。")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}
