import importlib.util, pathlib, tempfile, json, socket, threading, unittest
spec = importlib.util.spec_from_file_location('reader', pathlib.Path(__file__).resolve().parents[1]/'scripts/reader.py')
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
class ReaderTest(unittest.TestCase):
    def test_identity_gate_and_reset_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            old = r.CACHE; r.CACHE = pathlib.Path(directory)
            try:
                config={'providerInstances':{'codex':{'driver':'codex','displayName':'demo@example.test','enabled':True}}}
                cache={'driver':'codex','auth':{'email':'demo@example.test','label':'Demo Plan'},'usageLimits':{'checkedAt':'2026-01-01T00:00:00Z','windows':[{'id':'weekly','label':'Weekly','usedPercent':20,'resetsAt':'2026-01-02T00:00:00Z'}],'resetCredits':{'availableCount':2,'nextExpiresAt':'2026-01-03T00:00:00Z'}}}
                path=r.CACHE/'codex.json'; path.write_text(json.dumps(cache))
                a=r.account('codex',config); self.assertEqual(a['plan'],'Demo Plan'); self.assertEqual(a['resetCredits']['availableCount'],2); self.assertEqual(a['usage']['usageRows'][0]['percentLeft'],80)
                cache['auth']['email']='wrong@example.test';path.write_text(json.dumps(cache));a=r.account('codex',config)
                for key in ('usage','plan','resetCredits'): self.assertNotIn(key,a)
            finally: r.CACHE=old
    def test_spend_from_computai_is_cached_and_survives_failures(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory); old = (r.COMPUTAI, r.SPEND_CACHE)
            fake = root/'computai'
            fake.write_text('#!/bin/sh\nprintf "%s" "$CLAUDE_CONFIG_DIR" > "$(dirname "$0")/homes"\ncase "$1" in --line) echo \'{"today_usd": 12.345}\';; *) echo \'{"total_cost_usd": 400.5, "devices": [{}, {}], "unpriced_models": ["x"]}\';; esac\n')
            fake.chmod(0o755); (root/'claude-a/projects').mkdir(parents=True)
            r.COMPUTAI, r.SPEND_CACHE = fake, root/'spend.json'
            try:
                settings = {'providerInstances': {'a': {'driver': 'claudeAgent', 'config': {'homePath': str(root/'claude-a')}},
                                                  'b': {'driver': 'claudeAgent', 'config': {'homePath': str(root/'missing')}}}}
                s = r.spend(settings, now=1000)
                self.assertEqual((s['todayUSD'], s['monthUSD'], s['devices'], s['unpricedModels']), (12.35, 400.5, 2, 1))
                self.assertEqual((root/'homes').read_text(), str(root/'claude-a'))
                fake.write_text('#!/bin/sh\nexit 1\n')
                self.assertEqual(r.spend(settings, now=1100)['monthUSD'], 400.5)
                self.assertEqual(r.spend(settings, now=2000)['monthUSD'], 400.5)
            finally: r.COMPUTAI, r.SPEND_CACHE = old
    def test_ledger_keeps_widget_fields_and_no_projects(self):
        state = {'time': 1791099277, 'today_usd': 10.004, 'total_cost_usd': 100.5, 'unpriced_models': [],
                 'daily': {'days': ['2026-10-03', '2026-10-04'], 'sources': {'claude': [1, 2], 'codex': [3]}},
                 'forecast': {'subscription_value_projected': {'claude': 10, 'codex': 20}},
                 'sources': [{'source': 'claude', 'cost_usd': 40}],
                 'devices': [{'name': 'mini', 'cost_usd': 5, 'stale': False}, {'name': 'mbp', 'cost_usd': 50, 'stale': False}],
                 'machines': [{'machine': 'gpu-box', 'stale': False, 'cpu_pct': 12.4, 'gpu_util': 50.0, 'gpus': [{}], 'mem_used': 4, 'mem_total': 16, 'power_w': 99.6},
                              {'machine': 'nas', 'stale': True, 'cpu_pct': None, 'gpu_util': 0.0, 'gpus': [], 'mem_total': 0, 'power_w': None}],
                 'timeline': {'rows': [{'label': 'secret-project@mbp'}]}}
        l = r.ledger(state)
        self.assertEqual((l['yesterdayUSD'], l['projectedUSD'], l['days'][-1]), (4, 30, {'day': '10/04', 'claude': 2, 'codex': 0}))
        self.assertEqual([d['name'] for d in l['devices']], ['mbp', 'mini'])
        self.assertEqual(l['machines'][0], {'name': 'gpu-box', 'online': True, 'cpu': 12, 'gpu': 50, 'memory': 25, 'watts': 100})
        self.assertEqual(l['machines'][1], {'name': 'nas', 'online': False, 'cpu': 0, 'gpu': None, 'memory': None, 'watts': None})
        self.assertNotIn('secret-project', json.dumps(l))
    def test_pace_projects_every_account_from_window_start(self):
        def row(title, used, resets_in_minutes, minutes):
            return {'title': title, 'window': {'usedPercent': used, 'windowMinutes': minutes,
                    'resetsAt': r.utc(1000 * 60 + resets_in_minutes * 60)}}
        accounts = [{'provider': 'claude', 'label': 'me@example.test', 'plan': 'Claude Max Subscription',
                     'usage': {'updatedAt': 'x', 'usageRows': [row('Session', 50, 200, 300), row('Weekly · Fable', 10, 5000, 10080),
                                                               row('Weekly', 100, 60, 10080), row('Weekly', 1, 10079, 10080)]}},
                    {'provider': 'codex', 'label': 'other', 'usage': None}]
        p = r.pace(accounts, now=1000 * 60)
        self.assertEqual(len(p), 1)
        a = p[0]
        self.assertEqual((a['name'], a['plan']), ('me', 'Claude Max'))
        session, fable, spent, fresh = a['windows']
        self.assertEqual((session['title'], session['runsOutIn']), ('Session', 6000))   # 50% in 100 min -> 100 more min, reset in 200
        self.assertEqual((fable['title'], fable['runsOutIn']), ('Weekly · Fable', None))
        self.assertEqual((spent['runsOutIn'], spent['percentLeft']), (0, 0))
        self.assertIsNone(fresh['runsOutIn'])                                        # too early in the window to project
        self.assertEqual(a['worst'], 2)
    def test_nudge_only_when_t3_stopped_and_not_asked_recently(self):
        with tempfile.TemporaryDirectory() as directory:
            old = r.NUDGE_STATE; r.NUDGE_STATE = pathlib.Path(directory)/'nudge.json'
            try:
                fresh = [{'usage': {'updatedAt': r.utc(10000 - 600)}}, {'label': 'no usage'}]
                stale = fresh + [{'usage': {'updatedAt': r.utc(10000 - 601)}}]
                self.assertFalse(r.should_nudge(fresh, now=10000))
                self.assertFalse(r.should_nudge([{'label': 'no usage'}], now=10000))
                self.assertTrue(r.should_nudge(stale, now=10000))
                r.record_nudge(10000, 'started')
                self.assertFalse(r.should_nudge(stale, now=10600))
                self.assertTrue(r.should_nudge(stale, now=10601))
            finally: r.NUDGE_STATE = old
    def test_ws_call_sends_one_rpc_and_reads_its_exit(self):
        server = socket.socket(); server.bind(('127.0.0.1', 0)); server.listen(1); seen = {}
        def serve():
            conn, _ = server.accept(); head = b''
            while b'\r\n\r\n' not in head: head += conn.recv(1)
            seen['auth'] = b'Authorization: Bearer secret-token' in head
            conn.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n')
            h = conn.recv(2); n = h[1] & 127; mask = conn.recv(4); body = b''
            while len(body) < n: body += conn.recv(n - len(body))
            seen['request'] = json.loads(bytes(b ^ mask[i % 4] for i, b in enumerate(body)))
            for message in ({'_tag': 'Chunk', 'requestId': '1'}, {'_tag': 'Exit', 'requestId': '1', 'exit': {'_tag': 'Success'}}):
                data = json.dumps(message).encode(); conn.sendall(bytes([0x81, len(data)]) + data)
            conn.close()
        thread = threading.Thread(target=serve); thread.start()
        try: self.assertEqual(r.ws_call(server.getsockname()[1], 'secret-token', 'server.refreshProviders', {}), 'Success')
        finally: thread.join(); server.close()
        self.assertTrue(seen['auth'])
        self.assertEqual((seen['request']['tag'], seen['request']['payload']), ('server.refreshProviders', {}))
    def test_refresh_revokes_its_token_even_when_t3_is_unreachable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory); old = (r.T3, r.T3_RUNTIME)
            fake = root/'t3'
            fake.write_text('#!/bin/sh\necho "$@" >> "$(dirname "$0")/calls"\n[ "$3" = issue ] && echo \'{"token": "t", "sessionId": "s1"}\'\nexit 0\n')
            fake.chmod(0o755)
            closed = socket.socket(); closed.bind(('127.0.0.1', 0)); port = closed.getsockname()[1]; closed.close()
            (root/'runtime.json').write_text(json.dumps({'port': port}))
            r.T3, r.T3_RUNTIME = fake, root/'runtime.json'
            try:
                with self.assertRaises(OSError): r.refresh_t3()
                self.assertEqual((root/'calls').read_text().splitlines()[-1], 'auth session revoke s1')
            finally: r.T3, r.T3_RUNTIME = old
