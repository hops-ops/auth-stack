"""Generated-input safety contracts exercised through the real render function."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]


class GeneratedInputsTests(unittest.TestCase):
    def xr(self):
        return {
            'apiVersion': 'hops.ops.com.ai/v1alpha1', 'kind': 'AuthStack',
            'metadata': {'name': 'auth', 'namespace': 'platform'},
            'spec': {
                'clusterName': 'staging', 'namespace': 'zitadel',
                'domain': 'auth.example.com',
                'firstInstance': {'masterkey': {'secretRef': {'name': 'masterkey'}}},
                'database': {'external': {'dsnSecretRef': {'name': 'db'}}},
                'externalSecrets': {'enabled': True, 'generate': True,
                                    'secretPath': 'staging/zitadel'},
            },
        }

    def render(self, xr):
        (ROOT / '.tmp').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / '.tmp') as directory:
            path = Path(directory) / 'xr.json'
            path.write_text(json.dumps(xr))
            # Bypass XRD admission to independently exercise composition guards.
            command = shlex.split(os.environ.get('UP_COMMAND', 'up')) + [
                'composition', 'render', '--quiet', 'apis/authstacks/composition.yaml', str(path)]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
        docs = list(yaml.safe_load_all(result.stdout)) if result.returncode == 0 else []
        return result, docs

    def rejected(self, xr, message):
        result, _ = self.render(xr)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stdout + result.stderr)

    def test_generation_rejects_missing_disabled_or_empty_store_settings(self):
        for key, value in [('enabled', None), ('enabled', False),
                           ('secretPath', None), ('secretPath', '')]:
            with self.subTest(key=key, value=value):
                xr = self.xr()
                if value is None:
                    del xr['spec']['externalSecrets'][key]
                else:
                    xr['spec']['externalSecrets'][key] = value
                self.rejected(xr, 'requires enabled: true and a non-empty secretPath')

    def test_generation_rejects_inline_or_missing_masterkey_reference(self):
        for masterkey in ({'inline': 'A' * 32}, {},
                          {'inline': 'A' * 32, 'secretRef': {'name': 'masterkey'}}):
            with self.subTest(masterkey=masterkey):
                xr = self.xr()
                xr['spec']['firstInstance']['masterkey'] = masterkey
                self.rejected(xr, 'requires firstInstance.masterkey.secretRef.name')

    def test_generation_rejects_explicit_and_default_pat_path_collisions(self):
        explicit = self.xr()
        explicit['spec']['externalSecrets']['pushCredentials'] = {'path': 'staging/zitadel'}
        default = self.xr()
        default['spec']['externalSecrets']['secretPath'] = 'push/staging/zitadel-credentials'
        for xr in (explicit, default):
            with self.subTest(settings=xr['spec']['externalSecrets']):
                self.rejected(xr, 'secretPath and pushCredentials.path must differ')

    def test_disabled_pat_push_allows_its_unused_path_to_match(self):
        xr = self.xr()
        xr['spec']['externalSecrets']['pushCredentials'] = {
            'enabled': False, 'path': 'staging/zitadel'}
        result, docs = self.render(xr)
        self.assertEqual(result.returncode, 0, result.stderr)
        pushes = [d['spec']['forProvider']['manifest'] for d in docs
                  if d and d.get('kind') == 'Object'
                  and d.get('spec', {}).get('forProvider', {}).get('manifest', {}).get('kind') == 'PushSecret']
        self.assertEqual(len(pushes), 1)
        self.assertEqual(pushes[0]['spec']['updatePolicy'], 'IfNotExists')

    def test_generated_targets_are_isolated_by_xr_namespace_and_name(self):
        names = []
        for namespace, name in [('platform', 'auth'), ('platform', 'other'), ('other', 'auth')]:
            xr = self.xr()
            xr['metadata'].update(namespace=namespace, name=name)
            result, docs = self.render(xr)
            self.assertEqual(result.returncode, 0, result.stderr)
            generated = {}
            for d in docs:
                if d and d.get('kind') == 'Object':
                    annotation = d['metadata'].get('annotations', {}).get('crossplane.io/composition-resource-name')
                    if annotation in {'masterkey-generator', 'admin-password-generator',
                                      'generated-inputs', 'generated-inputs-pushsecret'}:
                        generated[annotation] = d['spec']['forProvider']['manifest']
            self.assertEqual(len(generated), 4)
            names.append({(d['kind'], d['metadata']['name']) for d in generated.values()})
            secret = generated['generated-inputs']['spec']
            push = generated['generated-inputs-pushsecret']['spec']
            self.assertEqual(push['selector']['secret']['name'], secret['target']['name'])
            self.assertEqual(secret['refreshPolicy'], 'CreatedOnce')
            self.assertEqual(push['updatePolicy'], 'IfNotExists')
            self.assertEqual(push['deletionPolicy'], 'None')
            for source, generator in zip(secret['dataFrom'], ['masterkey-generator', 'admin-password-generator']):
                self.assertEqual(source['sourceRef']['generatorRef']['name'],
                                 generated[generator]['metadata']['name'])
        for index, current in enumerate(names):
            for other in names[index + 1:]:
                self.assertTrue(current.isdisjoint(other))

    def test_generation_disabled_preserves_inline_masterkey_contract(self):
        xr = self.xr()
        xr['spec']['externalSecrets']['generate'] = False
        xr['spec']['firstInstance']['masterkey'] = {'inline': 'A' * 32}
        result, docs = self.render(xr)
        self.assertEqual(result.returncode, 0, result.stderr)
        release = next(d for d in docs if d and d.get('kind') == 'Release')
        self.assertEqual(release['spec']['forProvider']['values']['zitadel']['masterkey'], 'A' * 32)
        self.assertFalse(any(d and d.get('metadata', {}).get('annotations', {}).get(
            'crossplane.io/composition-resource-name') == 'generated-inputs' for d in docs))
