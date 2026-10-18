import argparse
import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('tuxun', Path(__file__).resolve().parents[1] / 'tuxun.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class SettingsTests(unittest.TestCase):
    def args(self, **kw):
        return argparse.Namespace(**dict(dict(delay=None, random_delay=None, delay_mode=None, offset_meters=None), **kw))
    def test_legacy_config(self):
        self.assertEqual(module.settings({'delay_seconds':12}, self.args())['delayMs'],12000)
    def test_overrides(self):
        self.assertEqual(module.settings({'delay_mode':'random'},self.args(delay=3))['delayMode'],'fixed')
        settings=module.settings({},self.args(random_delay=[2,4],offset_meters=0))
        self.assertEqual((settings['delayMode'],settings['delayMinMs'],settings['delayMaxMs'],settings['offsetMeters']),('random',2000,4000,0))
    def test_invalid(self):
        for kw in [dict(random_delay=[9,2]),dict(delay=float('nan')),dict(offset_meters=-1),dict(offset_meters=float('inf')),dict(delay=3601)]:
            with self.subTest(kw=kw), self.assertRaises(ValueError):module.settings({},self.args(**kw))
if __name__=='__main__':unittest.main()
