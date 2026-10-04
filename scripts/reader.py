"""Publish T3 quota-only caches to CodexBar's native account widgets."""
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = Path.home()
CACHE = ROOT / '.t3/caches'
SETTINGS = ROOT / '.t3/userdata/settings.json'
SOURCES = ('claude-nycu', 'claudeAgent', 'claude-cs14', 'codex-nycu', 'codex')
COMPUTAI = ROOT / '.local/bin/computai'
SPEND_CACHE = ROOT / 'Library/Application Support/T3UsageDesktop/spend.json'
SPEND_EVERY = 300
STATE_URL = 'http://127.0.0.1:8765/api/state'
WINDOWS = {'Session': '5 小時', 'Weekly': '每週'}


def iso(value):
    parsed = dt.datetime.fromisoformat(value.replace('Z', '+00:00'))
    if parsed.tzinfo is None:
        raise ValueError('Missing timezone')
    return parsed.astimezone(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')


def account(source, settings):
    config = settings['providerInstances'][source]
    provider = 'codex' if config['driver'] == 'codex' else 'claude'
    expected = config.get('displayName', '').strip().lower()
    pin = provider + '/t3:' + hashlib.sha256((source + ':' + expected).encode()).hexdigest()
    result = {'id': pin, 'provider': provider, 'label': config['displayName']}
    if not config.get('enabled'):
        return result
    data = json.loads((CACHE / (source + '.json')).read_text())
    if data.get('driver') != config['driver'] or data.get('auth', {}).get('email', '').strip().lower() != expected:
        return result
    limits = data.get('usageLimits', {})
    result['plan'] = data.get('auth', {}).get('label') or data.get('auth', {}).get('type')
    credits = limits.get('resetCredits', {})
    count = credits.get('availableCount')
    if isinstance(count, int) and not isinstance(count, bool) and count >= 0:
        result['resetCredits'] = {'availableCount': count}
        if credits.get('nextExpiresAt'):
            result['resetCredits']['nextExpiresAt'] = iso(credits['nextExpiresAt'])
    usage = {'provider': provider, 'updatedAt': iso(limits['checkedAt']), 'dailyUsage': [], 'usageRows': []}
    for window in limits.get('windows', []):
        used = window.get('usedPercent')
        if isinstance(used, bool) or not isinstance(used, (int, float)) or not math.isfinite(used) or not 0 <= used <= 100:
            continue
        rate = {'usedPercent': used}
        if window.get('resetsAt'):
            rate['resetsAt'] = iso(window['resetsAt'])
        if window.get('windowDurationMins'):
            rate['windowMinutes'] = window['windowDurationMins']
        label = window['label']
        row = {'id': window['id'], 'title': label, 'percentLeft': 100 - used, 'window': rate}
        usage['usageRows'].append(row)
        if window.get('kind') == 'session':
            usage['primary'] = rate
        elif label == 'Weekly':
            usage['secondary'] = rate
        elif 'tertiary' not in usage:
            usage['tertiary'] = rate
    if usage['usageRows']:
        result['usage'] = usage
    return result


def claude_homes(settings):
    """Every Claude home T3 knows about, including proxy accounts, so ComputAI counts all of them."""
    homes = []
    for config in settings.get('providerInstances', {}).values():
        home = config.get('config', {}).get('homePath')
        if config.get('driver') == 'claudeAgent' and home and Path(home, 'projects').is_dir() and home not in homes:
            homes.append(home)
    return homes


def computai(settings, *args):
    env = dict(os.environ, COMPUTAI_NO_UPDATE_CHECK='1')
    homes = claude_homes(settings)
    if homes:
        env['CLAUDE_CONFIG_DIR'] = ','.join(homes)
    out = subprocess.run([str(COMPUTAI), *args, '--json'], env=env, capture_output=True, timeout=180, check=True)
    return json.loads(out.stdout)


def spend(settings, now=None):
    """API-equivalent spend from ComputAI, refreshed every SPEND_EVERY seconds. None when ComputAI is absent."""
    now = time.time() if now is None else now
    try:
        cached = json.loads(SPEND_CACHE.read_text())
    except (OSError, ValueError):
        cached = None
    if cached and now - cached.get('checkedEpoch', 0) < SPEND_EVERY:
        return cached['spend']
    if not COMPUTAI.exists():
        return None
    try:
        month = computai(settings, '--summary', '--month')
        today = computai(settings, '--line')
        result = {'todayUSD': round(float(today['today_usd']), 2),
                  'monthUSD': round(float(month['total_cost_usd']), 2),
                  'devices': max(1, len(month.get('devices', []))),
                  'unpricedModels': len(month.get('unpriced_models', [])),
                  'updatedAt': dt.datetime.fromtimestamp(now, dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')}
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return cached['spend'] if cached else None
    SPEND_CACHE.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', dir=SPEND_CACHE.parent, delete=False) as tmp:
        json.dump({'checkedEpoch': now, 'spend': result}, tmp)
    os.replace(tmp.name, SPEND_CACHE)
    return result


def utc(epoch):
    return dt.datetime.fromtimestamp(epoch, dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')


def computai_state():
    """State of the running ComputAI dashboard (computai --web), or None when it is not running."""
    try:
        with urllib.request.urlopen(STATE_URL, timeout=3) as response:
            return json.load(response)
    except (OSError, ValueError):
        return None


def ledger(state):
    """Trim the dashboard state to what the widgets draw. Machine and device names only; no projects."""
    daily = state.get('daily') or {}
    series = daily.get('sources') or {}
    days = []
    for i, day in enumerate(daily.get('days', [])):
        days.append({'day': day[5:].replace('-', '/'),
                     'claude': round(series.get('claude', [])[i] if i < len(series.get('claude', [])) else 0, 2),
                     'codex': round(series.get('codex', [])[i] if i < len(series.get('codex', [])) else 0, 2)})
    days = days[-14:]
    projected = (state.get('forecast') or {}).get('subscription_value_projected') or {}
    machines = []
    for m in state.get('machines', []):
        memory = m.get('mem_total')
        machines.append({'name': m['machine'], 'online': not m.get('stale'),
                         'cpu': round(m.get('cpu_pct') or 0),
                         'gpu': round(m['gpu_util']) if m.get('gpus') and m.get('gpu_util') is not None else None,
                         'memory': round(100 * m.get('mem_used', 0) / memory) if memory else None,
                         'watts': round(m['power_w']) if m.get('power_w') is not None else None})
    return {'updatedAt': utc(state.get('time', time.time())),
            'todayUSD': round(state.get('today_usd') or 0, 2),
            'yesterdayUSD': round(days[-2]['claude'] + days[-2]['codex'], 2) if len(days) > 1 else None,
            'monthUSD': round(state.get('total_cost_usd') or 0, 2),
            'projectedUSD': round(sum(projected.values()), 2) if projected else None,
            'sources': [{'provider': s['source'], 'usd': round(s.get('cost_usd') or 0, 2)} for s in state.get('sources', [])],
            'devices': sorted(({'name': d['name'], 'usd': round(d.get('cost_usd') or 0, 2), 'stale': bool(d.get('stale'))}
                               for d in state.get('devices', [])), key=lambda d: -d['usd']),
            'machines': machines, 'days': days,
            'unpricedModels': len(state.get('unpriced_models') or [])}


def window_title(title):
    """Session -> 5 小時, Weekly -> 每週, Weekly · Fable -> Fable 每週."""
    window, _, model = title.partition(' · ')
    return ((model + ' ') if model else '') + WINDOWS.get(window, window)


def pace(accounts, now=None):
    """How fast every T3 account burns each window, as a straight line from the window start.
    runsOutIn is set only when the window would run out before it resets (0 when it already has)."""
    now = time.time() if now is None else now
    result = []
    for account in accounts:
        usage = account.get('usage')
        if not usage:
            continue
        windows = []
        for row in usage['usageRows']:
            rate = row['window']
            if not rate.get('resetsAt') or not rate.get('windowMinutes'):
                continue
            length = rate['windowMinutes'] * 60
            resets_in = max(0.0, dt.datetime.fromisoformat(rate['resetsAt'].replace('Z', '+00:00')).timestamp() - now)
            elapsed = max(0.0, length - resets_in)
            used = rate['usedPercent']
            runs_out = None
            if used >= 100:
                runs_out = 0
            elif used > 0 and elapsed >= length * 0.05:   # too early in the window to project
                eta = (100 - used) * elapsed / used
                runs_out = round(eta) if eta < resets_in else None
            windows.append({'title': window_title(row['title']), 'percentLeft': max(0, 100 - used),
                            'elapsedPercent': round(100 * elapsed / length, 1), 'resetsIn': round(resets_in), 'runsOutIn': runs_out})
        if windows:
            worst = min(range(len(windows)), key=lambda i: (windows[i]['runsOutIn'] is None, windows[i]['runsOutIn'] or 0, windows[i]['percentLeft']))
            result.append({'provider': account['provider'], 'name': account['label'].split('@')[0],
                           'plan': (account.get('plan') or '').replace(' Subscription', ''),
                           'updatedAt': usage['updatedAt'], 'worst': worst, 'windows': windows})
    return result


def spend_from(ledger):
    return {'todayUSD': ledger['todayUSD'], 'monthUSD': ledger['monthUSD'], 'devices': max(1, len(ledger['devices'])),
            'unpricedModels': ledger['unpricedModels'], 'updatedAt': ledger['updatedAt']}


def build_snapshot(settings):
    accounts = []
    for source in SOURCES:
        try:
            accounts.append(account(source, settings))
        except (OSError, ValueError, KeyError, TypeError):
            config = settings.get('providerInstances', {}).get(source, {})
            expected = config.get('displayName', source)
            provider = 'codex' if source.startswith('codex') else 'claude'
            accounts.append({'id': provider + '/t3:' + hashlib.sha256((source + ':' + expected.strip().lower()).encode()).hexdigest(), 'provider': provider, 'label': expected})
    state = computai_state()
    details = ledger(state) if state else None
    return {'accounts': accounts, 'pace': pace(accounts), 'spend': spend_from(details) if details else spend(settings), 'computai': details, 'entries': [], 'enabledProviders': ['claude', 'codex'], 'usageBarsShowUsed': False, 'generatedAt': dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')}


if __name__ == '__main__':
    print(json.dumps(build_snapshot(json.loads(SETTINGS.read_text())), separators=(',', ':')))
