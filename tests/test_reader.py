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
