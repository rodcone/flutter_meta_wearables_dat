import base64
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('logging_config', Path(__file__).parents[2] / 'example/ios/scripts/configure_investigation_logging.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def flag(value):
    return base64.b64encode(value.encode()).decode()


class LoggingConfigTests(unittest.TestCase):
    def test_instrumented_then_normal_restores_source(self):
        source = {'MWDAT': {'MetaAppID': '0'}}
        built = copy.deepcopy(source)
        built['CFBundleIdentifier'] = 'fixture'
        module.configure(source, built, flag('MWDAT_INVESTIGATION=true'))
        self.assertEqual(built['MWDAT']['Logging']['Level'], 'warning')
        module.configure(source, built, '')
        self.assertNotIn('Logging', built['MWDAT'])
        self.assertEqual(built['CFBundleIdentifier'], 'fixture')
        self.assertNotIn('Logging', source['MWDAT'])

    def test_preserves_source_logging_options(self):
        source = {'MWDAT': {'Logging': {'Level': 'error', 'Other': True}}}
        built = module.configure(source, {}, flag('MWDAT_INVESTIGATION=true'))
        self.assertEqual(built['MWDAT']['Logging'], {'Level': 'warning', 'Other': True})
        module.configure(source, built, '')
        self.assertEqual(built['MWDAT'], source['MWDAT'])

    def test_requires_exact_flag(self):
        for value in ['MWDAT_INVESTIGATION=false', 'MWDAT_RECOVERY_EXPERIMENT=true',
                      'OTHER=MWDAT_INVESTIGATION=true', 'MWDAT_INVESTIGATION=trueish']:
            self.assertNotIn('Logging', module.configure({}, {}, flag(value))['MWDAT'])
        combined = ','.join(map(flag, ['OTHER=x', 'MWDAT_INVESTIGATION=true']))
        self.assertEqual(module.configure({}, {}, combined)['MWDAT']['Logging']['Level'], 'warning')

    def test_malformed_flag_fails_before_mutation(self):
        built = {'MWDAT': {'Logging': {'Level': 'error'}}}
        before = copy.deepcopy(built)
        with self.assertRaises(ValueError):
            module.configure({}, built, 'not-base64!')
        self.assertEqual(built, before)


if __name__ == '__main__':
    unittest.main()
