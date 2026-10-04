"""Publish T3 quota-only caches to CodexBar's native account widgets."""
import base64
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import socket
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
T3 = ROOT / '.local/bin/t3'
T3_RUNTIME = ROOT / '.t3/userdata/server-runtime.json'
NUDGE_STATE = ROOT / 'Library/Application Support/T3UsageDesktop/nudge.json'
NUDGE_AFTER = 600   # T3 refreshes every 5 minutes; two missed rounds means it has stopped
NUDGE_EVERY = 600


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
            windows.append({'title': row['title'], 'percentLeft': max(0, 100 - used),
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


def epoch(value):
    return dt.datetime.fromisoformat(value.replace('Z', '+00:00')).timestamp()


def should_nudge(accounts, now=None):
    """True when T3 has stopped refreshing quotas and we have not asked it to recently.
    T3 only refreshes while one of its windows reports activity, and that report can stop after sleep."""
    now = time.time() if now is None else now
    checked = [epoch(a['usage']['updatedAt']) for a in accounts if a.get('usage')]
    if not checked or now - min(checked) <= NUDGE_AFTER:
        return False
    try:
        last = json.loads(NUDGE_STATE.read_text()).get('attemptedEpoch', 0)
    except (OSError, ValueError, AttributeError):
        last = 0
    return now - last > NUDGE_EVERY


def record_nudge(now, result):
    NUDGE_STATE.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile('w', dir=NUDGE_STATE.parent, delete=False) as tmp:
        json.dump({'attemptedEpoch': now, 'result': result}, tmp)
    os.replace(tmp.name, NUDGE_STATE)


def nudge(accounts, now=None):
    """Refresh T3 in a detached process so the snapshot is not held up; the next snapshot reads the result."""
    now = time.time() if now is None else now
    if not T3.exists() or not should_nudge(accounts, now):
        return
    record_nudge(now, 'started')
    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--refresh-t3'], start_new_session=True,
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def t3(*args):
    return subprocess.run([str(T3), *args], capture_output=True, text=True, timeout=30, check=True).stdout


def ws_call(port, token, tag, payload, timeout=60):
    """One RPC over T3's /ws endpoint, the same call its own refresh button makes. Returns the exit tag."""
    with socket.create_connection(('127.0.0.1', port), timeout=timeout) as sock:
        key = base64.b64encode(os.urandom(16)).decode()
        sock.sendall(('GET /ws HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                      'Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nAuthorization: Bearer %s\r\n\r\n'
                      % (port, key, token)).encode())
        head = b''
        while b'\r\n\r\n' not in head:
            chunk = sock.recv(1)
            if not chunk:
                raise ConnectionError('T3 closed the connection')
            head += chunk
        if b' 101 ' not in head.split(b'\r\n', 1)[0]:
            raise ConnectionError(head.split(b'\r\n', 1)[0].decode(errors='replace'))

        def read(n):
            data = b''
            while len(data) < n:
                chunk = sock.recv(n - len(data))
                if not chunk:
                    raise ConnectionError('T3 closed the connection')
                data += chunk
            return data

        body = json.dumps({'_tag': 'Request', 'id': '1', 'tag': tag, 'payload': payload, 'headers': []}).encode()
        mask = os.urandom(4)
        size = bytes([0x80 | len(body)]) if len(body) < 126 else bytes([0x80 | 126]) + len(body).to_bytes(2, 'big')
        sock.sendall(bytes([0x81]) + size + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(body)))
        while True:
            first, second = read(2)
            n = second & 127
            if n == 126:
                n = int.from_bytes(read(2), 'big')
            elif n == 127:
                n = int.from_bytes(read(8), 'big')
            data = read(n)
            if first & 15 == 8:
                raise ConnectionError('T3 closed the connection')
            if first & 15 != 1:
                continue
            message = json.loads(data)
            if isinstance(message, dict) and message.get('_tag') == 'Exit' and message.get('requestId') == '1':
                return message['exit']['_tag']


def refresh_t3():
    """Ask the running T3 server to refresh every provider, with a short-lived token revoked right after."""
    port = json.loads(T3_RUNTIME.read_text())['port']
    issued = json.loads(t3('auth', 'session', 'issue', '--json', '--ttl', '5m', '--label', 'T3 quota widget refresh'))
    try:
        return ws_call(port, issued['token'], 'server.refreshProviders', {})
    finally:
        t3('auth', 'session', 'revoke', issued['sessionId'])


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
    try:
        nudge(accounts)
    except (OSError, ValueError, KeyError, TypeError):
        pass
    state = computai_state()
    details = ledger(state) if state else None
    return {'accounts': accounts, 'pace': pace(accounts), 'spend': spend_from(details) if details else spend(settings), 'computai': details, 'entries': [], 'enabledProviders': ['claude', 'codex'], 'usageBarsShowUsed': False, 'generatedAt': dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')}


if __name__ == '__main__' and '--refresh-t3' in sys.argv:
    try:
        result = refresh_t3()
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as error:
        result = type(error).__name__   # never the message: it could carry the token
    record_nudge(time.time(), result)
elif __name__ == '__main__':
    print(json.dumps(build_snapshot(json.loads(SETTINGS.read_text())), separators=(',', ':')))
