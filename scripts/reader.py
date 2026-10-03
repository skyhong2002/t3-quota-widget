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
    return {'accounts': accounts, 'entries': [], 'enabledProviders': ['claude', 'codex'], 'usageBarsShowUsed': False, 'generatedAt': dt.datetime.now(dt.timezone.utc).isoformat(timespec='seconds').replace('+00:00', 'Z')}


if __name__ == '__main__':
    print(json.dumps(build_snapshot(json.loads(SETTINGS.read_text())), separators=(',', ':')))
