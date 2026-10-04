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

ROOT = Path.home()
CACHE = ROOT / '.t3/caches'
SETTINGS = ROOT / '.t3/userdata/settings.json'
SOURCES = ('claude-nycu', 'claudeAgent', 'claude-cs14', 'codex-nycu', 'codex')
COMPUTAI = ROOT / '.local/bin/computai'
SPEND_CACHE = ROOT / 'Library/Application Support/T3UsageDesktop/spend.json'
SPEND_EVERY = 300


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
    return {'accounts': accounts, 'spend': spend(settings), 'entries': [], 'enabledProviders': ['claude', 'codex'], 'usageBarsShowUsed': False, 'generatedAt': dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')}


if __name__ == '__main__':
    print(json.dumps(build_snapshot(json.loads(SETTINGS.read_text())), separators=(',', ':')))
