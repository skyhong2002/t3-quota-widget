#!/usr/bin/env python3
"""Render README previews of every widget from the real SwiftUI views, with synthetic accounts.

    python3 scripts/previews.py            # writes docs/preview.png and docs/previews/*.png

Nothing here reads local accounts or ComputAI: the snapshot below is made up, and pace is worked out
by reader.pace() so the projections match what the widget would show.
"""
import datetime as dt
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NOW = dt.datetime(2026, 10, 4, 6, 0, tzinfo=dt.timezone.utc)

spec = importlib.util.spec_from_file_location('reader', ROOT / 'scripts/reader.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


def at(minutes):
    return (NOW + dt.timedelta(minutes=minutes)).isoformat().replace('+00:00', 'Z')


def row(id, title, used, resets_in_minutes, window_minutes):
    return {'id': id, 'title': title, 'percentLeft': 100 - used,
            'window': {'usedPercent': used, 'resetsAt': at(resets_in_minutes), 'windowMinutes': window_minutes}}


def account(provider, email, plan, rows, credits=None):
    result = {'id': provider + '/' + email, 'provider': provider, 'label': email, 'plan': plan,
              'usage': {'provider': provider, 'updatedAt': at(-2), 'usageRows': rows}}
    if credits:
        result['resetCredits'] = {'availableCount': credits[0], 'nextExpiresAt': at(credits[1])}
    return result


WEEK = 10080
ACCOUNTS = [
    account('claude', 'personal@example.com', 'Claude Max Subscription',
            [row('five_hour', 'Session', 38, 130, 300), row('seven_day', 'Weekly', 29, 4560, WEEK), row('fable', 'Weekly · Fable', 16, 4560, WEEK)]),
    account('claude', 'work@example.com', 'Claude Max Subscription',
            [row('five_hour', 'Session', 82, 170, 300), row('seven_day', 'Weekly', 65, 6900, WEEK), row('fable', 'Weekly · Fable', 48, 6900, WEEK)]),
    account('claude', 'team@example.com', 'Claude Team Subscription',
            [row('five_hour', 'Session', 100, 52, 300), row('seven_day', 'Weekly', 44, 2600, WEEK)]),
    account('codex', 'primary@example.com', 'ChatGPT Pro 20x Subscription',
            [row('primary', 'Weekly', 19, 7300, WEEK)], credits=(2, 26000)),
    account('codex', 'secondary@example.com', 'ChatGPT Pro 20x Subscription',
            [row('primary', 'Weekly', 61, 8400, WEEK)], credits=(1, 37000)),
]

DAYS = [(31, 120), (0, 210), (64, 390), (88, 254), (47, 105), (0, 160), (12, 230),
        (119, 303), (81, 190), (31, 205), (90, 235), (240, 244), (118, 410), (22, 96)]
LEDGER = {
    'updatedAt': at(-1), 'todayUSD': 118.4, 'yesterdayUSD': 528.3, 'monthUSD': 1302.6, 'projectedUSD': 11240.0,
    'sources': [{'provider': 'claude', 'usd': 402.1}, {'provider': 'codex', 'usd': 900.5}],
    'devices': [{'name': 'studio', 'usd': 612.4, 'stale': False}, {'name': 'laptop', 'usd': 388.0, 'stale': False},
                {'name': 'gpu-box', 'usd': 206.1, 'stale': False}, {'name': 'mini', 'usd': 96.1, 'stale': False},
                {'name': 'vps', 'usd': 0.0, 'stale': False}],
    'machines': [{'name': 'gpu-box', 'online': True, 'cpu': 41, 'gpu': 63, 'memory': 48, 'watts': 312},
                 {'name': 'laptop', 'online': True, 'cpu': 18, 'gpu': 4, 'memory': 71, 'watts': 22},
                 {'name': 'mini', 'online': True, 'cpu': 9, 'gpu': 0, 'memory': 58, 'watts': 14},
                 {'name': 'nas', 'online': True, 'cpu': 6, 'gpu': None, 'memory': 92, 'watts': None},
                 {'name': 'studio', 'online': True, 'cpu': 27, 'gpu': 12, 'memory': 64, 'watts': 61},
                 {'name': 'vps', 'online': True, 'cpu': 14, 'gpu': None, 'memory': 37, 'watts': None},
                 {'name': 'old-desktop', 'online': False, 'cpu': 0, 'gpu': None, 'memory': None, 'watts': None}],
    'days': [{'day': (NOW - dt.timedelta(days=13 - i)).strftime('%m/%d'), 'claude': c, 'codex': x} for i, (c, x) in enumerate(DAYS)],
    'unpricedModels': 0,
}
SNAPSHOT = {'accounts': ACCOUNTS, 'pace': reader.pace(ACCOUNTS, now=NOW.timestamp()),
            'spend': {'todayUSD': LEDGER['todayUSD'], 'monthUSD': LEDGER['monthUSD'], 'devices': 4, 'unpricedModels': 0, 'updatedAt': at(-1)},
            'computai': LEDGER, 'language': 'en'}

# Each widget at its macOS desktop size; the gallery places them in three columns.
MAIN = r'''
import SwiftUI
import AppKit
import WidgetKit

let snap = try! JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
let out = URL(fileURLWithPath: CommandLine.arguments[2])
let now = ISO8601DateFormatter().date(from: CommandLine.arguments[3])!
let e = Entry(date: now, accounts: snap.accounts, pace: snap.pace ?? [], spend: snap.spend, ledger: snap.computai, language: "en")
let single = SingleEntry(date: now, account: snap.accounts.first, language: "en")
let S = CGSize(width: 170, height: 170), M = CGSize(width: 364, height: 170), L = CGSize(width: 364, height: 382)

struct Card<V: View>: View {
    let size: CGSize
    let content: V
    var body: some View {
        content.padding(16).frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(Color(white: 0.115)).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

@MainActor func save<V: View>(_ view: V, _ name: String) {
    let r = ImageRenderer(content: view); r.scale = 2
    guard let image = r.cgImage else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

MainActor.assumeIsolated {
    let widgets: [(String, CGSize, AnyView)] = [
        ("limit-pace-large", L, AnyView(PaceTile(entry: e, family: .systemLarge))),
        ("limit-pace-medium", M, AnyView(PaceTile(entry: e))),
        ("account-claude-medium", M, AnyView(SingleTile(entry: single))),
        ("account-quotas-large", L, AnyView(Tile(entry: e))),
        ("spend-14-day-medium", M, AnyView(TrendTile(entry: e))),
        ("spend-by-computer-medium", M, AnyView(DeviceSpendTile(entry: e))),
        ("machines-large", L, AnyView(MachinesTile(entry: e, family: .systemLarge))),
        ("ai-spend-medium", M, AnyView(SpendTile(entry: e))),
        ("ai-spend-small", S, AnyView(SpendTile(entry: e, family: .systemSmall))),
        ("machines-medium", M, AnyView(MachinesTile(entry: e))),
    ]
    for (name, size, view) in widgets { save(Card(size: size, content: view).padding(8), "previews/\(name).png") }
    let cards = widgets.map { Card(size: $0.1, content: $0.2) }
    let gallery = HStack(alignment: .top, spacing: 20) {
        VStack(spacing: 20) { cards[0]; cards[1]; cards[2] }
        VStack(spacing: 20) { cards[3]; cards[4]; cards[5] }
        VStack(alignment: .leading, spacing: 20) { cards[6]; cards[7]; HStack(spacing: 20) { cards[8]; Spacer(minLength: 0) } }
    }
    .padding(28)
    .background(LinearGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.27), Color(red: 0.09, green: 0.09, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
    save(gallery, "preview.png")
}
'''


def main():
    docs = ROOT / 'docs'
    (docs / 'previews').mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        for source in ('Widget.swift', 'LedgerWidgets.swift'):
            text = (ROOT / 'Sources' / source).read_text()
            text = text.replace('@main struct', 'struct')
            # Outside WidgetKit the family can't come from the environment; make it a parameter.
            text = re.sub(r'@Environment\(\\\.widgetFamily\) var family', 'var family: WidgetFamily = .systemMedium', text)
            (tmp / source).write_text(text)
        (tmp / 'main.swift').write_text(MAIN)
        (tmp / 'snapshot.json').write_text(json.dumps(SNAPSHOT))
        binary = tmp / 'render'
        subprocess.run(['swiftc', '-O', '-o', str(binary), str(tmp / 'Widget.swift'), str(tmp / 'LedgerWidgets.swift'), str(tmp / 'main.swift'),
                        '-framework', 'WidgetKit', '-framework', 'SwiftUI', '-framework', 'AppKit'], check=True)
        subprocess.run([str(binary), str(tmp / 'snapshot.json'), str(docs), at(0)], check=True)
    print(docs / 'preview.png')


if __name__ == '__main__':
    main()
