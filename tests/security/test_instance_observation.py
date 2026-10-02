"""Native observation migration and readiness regressions."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[2]

class InstanceObservationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (ROOT / '.tmp').mkdir(exist_ok=True)

    def render(self, enabled=True, observed=None, config=None, first_instance=True):
        xr = {'apiVersion': 'hops.ops.com.ai/v1alpha1', 'kind': 'AuthStack',
              'metadata': {'name': 'identity', 'namespace': 'platform'},
              'spec': {'domain': 'auth.example.com',
                       'firstInstance': {'masterkey': {'secretRef': {'name': 'masterkey'}}},
                       'database': {'external': {'dsnSecretRef': {'name': 'db', 'key': 'dsn'}}}}}
        if not first_instance:
            xr['spec']['firstInstance']['enabled'] = False
        if enabled:
            xr['spec']['instanceDiscovery'] = config or {
                'enabled': True, 'providerConfigRef': {'name': 'admin', 'kind': 'ClusterProviderConfig'}}
        with tempfile.TemporaryDirectory(dir=ROOT / '.tmp') as directory:
            path = Path(directory)
            (path / 'xr.json').write_text(json.dumps(xr))
            command = shlex.split(os.environ.get('UP_COMMAND', 'up')) + [
                'composition', 'render', '--quiet', 'apis/authstacks/composition.yaml', str(path / 'xr.json')]
            if observed:
                directory = path / 'observed'
                directory.mkdir()
                for index, obj in enumerate(observed):
                    (directory / f'{index}.yaml').write_text(yaml.safe_dump(obj))
                command += ['--observed-resources', str(directory)]
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=180)
        return result, list(yaml.safe_load_all(result.stdout)) if result.returncode == 0 else []

    def observation(self, synced='True', generation=3, observed_generation=3):
        return [
            {'apiVersion': 'helm.m.crossplane.io/v1beta1', 'kind': 'Release',
             'metadata': {'name': 'identity-zitadel', 'namespace': 'platform', 'annotations': {'crossplane.io/composition-resource-name': 'helm-release-zitadel'}},
             'status': {'conditions': [{'type': 'Ready', 'status': 'True'}]}},
            {'apiVersion': 'instance.zitadel.m.crossplane.io/v1alpha1', 'kind': 'Instance',
             'metadata': {'name': 'identity-instance', 'namespace': 'platform', 'generation': generation,
                          'annotations': {'crossplane.io/composition-resource-name': 'instance'}},
             'status': {'atProvider': {'id': 'installed-instance'}, 'conditions': [
                 {'type': 'Ready', 'status': 'True'},
                 {'type': 'Synced', 'status': synced, 'observedGeneration': observed_generation}]}}
        ]

    def test_disabled_does_not_render_native_or_probe_resources(self):
        result, docs = self.render(enabled=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(d.get('kind') == 'Instance' for d in docs))
        self.assertFalse(any('instance-' in d.get('metadata', {}).get('name', '') for d in docs))

    def test_pending_keeps_observer_without_credential_or_job_wiring(self):
        result, docs = self.render()
        self.assertEqual(result.returncode, 0, result.stderr)
        instance = next(d for d in docs if d.get('kind') == 'Instance')
        self.assertEqual(instance['spec'], {'managementPolicies': ['Observe'],
                                          'providerConfigRef': {'name': 'admin', 'kind': 'ClusterProviderConfig'}})
        self.assertFalse(any(d.get('spec', {}).get('forProvider', {}).get('manifest', {}).get('kind')
                             in ['Job', 'ConfigMap', 'Role', 'RoleBinding', 'ServiceAccount'] for d in docs))
        status = next(d['status'] for d in docs if d.get('kind') == 'AuthStack')
        self.assertFalse(status['ready'])
        self.assertEqual(status['instanceId'], '')

    def test_ready_publishes_typed_id_and_reference_with_usage(self):
        result, docs = self.render(observed=self.observation())
        self.assertEqual(result.returncode, 0, result.stderr)
        status = next(d['status'] for d in docs if d.get('kind') == 'AuthStack')
        self.assertTrue(status['ready'])
        self.assertEqual(status['instanceId'], 'installed-instance')
        self.assertEqual(status['instanceRef'], {'name': 'identity-instance', 'namespace': 'platform'})
        usage = next(d for d in docs if d.get('metadata', {}).get('name') == 'identity-delete-instance-before-zitadel')
        self.assertEqual(usage['spec']['of']['resourceRef']['name'], 'identity-zitadel')
        self.assertEqual(usage['spec']['by']['resourceRef']['name'], 'identity-instance')

    def test_failure_stale_and_deleting_observations_clear_status_and_keep_observer(self):
        variants = [self.observation(synced='False'), self.observation(observed_generation=2), self.observation()]
        variants[-1][1]['metadata']['deletionTimestamp'] = '2026-10-02T00:00:00Z'
        for observed in variants:
            with self.subTest(observed=observed[1]['metadata']):
                result, docs = self.render(observed=observed)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertTrue(any(d.get('kind') == 'Instance' for d in docs))
                status = next(d['status'] for d in docs if d.get('kind') == 'AuthStack')
                self.assertFalse(status['ready'])
                condition = next(c for c in status['conditions'] if c['type'] == 'Ready')
                self.assertEqual(condition['status'], 'False')
                self.assertRegex(condition['message'], r'(?<![-\w])instance(?![-\w])')
                self.assertEqual(status['instanceId'], '')
                self.assertEqual(status['instanceRef'], {'name': '', 'namespace': ''})

    def test_old_opt_in_config_is_rejected_without_provider_config(self):
        result, _ = self.render(config={'enabled': True, 'internalURL': 'https://identity-zitadel.zitadel.svc:8080'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('providerConfigRef is required', result.stdout + result.stderr)

    def test_namespaced_provider_config_is_supported_without_first_instance_bootstrap(self):
        result, docs = self.render(config={'enabled': True, 'providerConfigRef': {'name': 'admin', 'kind': 'ProviderConfig'}}, first_instance=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(next(d for d in docs if d.get('kind') == 'Instance')['spec']['providerConfigRef']['kind'], 'ProviderConfig')
