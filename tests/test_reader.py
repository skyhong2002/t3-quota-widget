import importlib.util, pathlib, tempfile, json, unittest
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
