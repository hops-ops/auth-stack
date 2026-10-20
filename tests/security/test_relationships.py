"""Exercise relationship reference resolution, retention and adoption through render."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[2]
USER_API = 'user.zitadel.m.crossplane.io/v1alpha1'
PROJECT_API = 'project.zitadel.m.crossplane.io/v1alpha1'
ORG_API = 'org.zitadel.m.crossplane.io/v1alpha1'
XR_API = 'auth.hops.ops.com.ai/v1alpha1'


class RelationshipTests(unittest.TestCase):
    def xr(self, kind='Authorization', subject='HumanUser'):
        spec = {'subjectRef': {'name': 'person', 'kind': subject}, 'roles': ['reader'],
                'providerConfigRef': {'name': 'zitadel', 'kind': 'ProviderConfig'}}
        if kind == 'Authorization':
            spec.update(projectRef={'name': 'product'}, organizationRef={'name': 'tenant'})
        else:
            spec.update(roles=['ORG_USER_MANAGER'], target={'organizationRef': {'name': 'tenant'}})
        return {'apiVersion': XR_API, 'kind': kind,
                'metadata': {'name': 'binding', 'namespace': 'app'}, 'spec': spec}

    def sources(self, subject='HumanUser', namespace='app', ready=True):
        def obj(api, kind, name, values):
            return {'apiVersion': api, 'kind': kind, 'metadata': {'name': name, 'namespace': namespace},
                    'status': {'atProvider': values, 'conditions': [{'type': 'Ready', 'status': str(ready)}]}}
        return [obj(USER_API, subject, 'person', {'id': 'user-id', 'orgId': 'user-home-org'}),
                obj(PROJECT_API, 'ProjectV2', 'product', {'id': 'project-id', 'orgId': 'owner-org'}),
                obj(ORG_API, 'Organization', 'tenant', {'id': 'grantee-org'}),
                obj(PROJECT_API, 'Grant', 'delegation', {'id': 'grant-id', 'projectId': 'project-id', 'grantedOrgId': 'grantee-org'})]

    def binding(self, kind='Authorization', policies=None):
        fp = {'userId': 'user-id', 'projectId': 'project-id', 'orgId': 'grantee-org', 'roleKeys': ['old-role']}
        api = 'authorization.zitadel.m.crossplane.io/v1alpha1'
        if kind == 'Administrator':
            api = 'internalpermission.zitadel.m.crossplane.io/v1alpha1'
            fp = {'userId': 'user-id', 'orgId': 'grantee-org', 'resourceType': 'organization', 'roles': ['ORG_USER_MANAGER']}
        return {'apiVersion': api, 'kind': kind,
                'metadata': {'name': 'binding-' + kind.lower(), 'namespace': 'app', 'generation': 3,
                             'annotations': {'crossplane.io/composition-resource-name': 'binding', 'crossplane.io/external-name': 'existing-id'}},
                'spec': {'forProvider': fp, 'managementPolicies': policies if policies is not None else ['*'],
                         'providerConfigRef': {'name': 'zitadel', 'kind': 'ProviderConfig'}},
                'status': {'atProvider': {'id': 'existing-id', **fp}, 'conditions': [
                    {'type': 'Ready', 'status': 'True', 'observedGeneration': 3},
                    {'type': 'Synced', 'status': 'True', 'observedGeneration': 3}]}}

    def render(self, xr, extra=None, observed=None, success=True):
        (ROOT / '.tmp').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=ROOT / '.tmp') as directory:
            p = Path(directory)
            (p / 'xr.json').write_text(json.dumps(xr))
            plural = 'authorizations' if xr['kind'] == 'Authorization' else 'administrators'
            cmd = shlex.split(os.environ.get('RELATIONSHIP_RENDER_COMMAND', 'up composition render --quiet')) + [
                '--xrd=apis/' + plural + '/definition.yaml',
                'apis/' + plural + '/composition.yaml', str(p / 'xr.json')]
            if os.environ.get('RELATIONSHIP_FUNCTIONS_FILE'):
                cmd = ['crossplane', 'render', str(p / 'xr.json'),
                       'apis/' + plural + '/composition.yaml', os.environ['RELATIONSHIP_FUNCTIONS_FILE'],
                       '--xrd=apis/' + plural + '/definition.yaml']
            for flag, resources in [('extra-resources', extra), ('observed-resources', observed)]:
                if resources:
                    (p / (flag + '.yaml')).write_text(yaml.safe_dump_all(resources))
                    cmd.append('--' + flag + '=' + str(p / (flag + '.yaml')))
            result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=240)
        if not success:
            self.assertNotEqual(result.returncode, 0, result.stdout)
            return
        self.assertEqual(result.returncode, 0, result.stderr)
        return [d for d in yaml.safe_load_all(result.stdout) if d]

    def native(self, docs, kind='Authorization'):
        return next(d for d in docs if d['kind'] == kind and d['apiVersion'] != XR_API)

    def status(self, docs):
        return next(d['status'] for d in docs if d['apiVersion'] == XR_API)

    def assert_not_ready(self, docs):
        status = self.status(docs)
        self.assertFalse(status['ready'])
        self.assertEqual(next(c['status'] for c in status['conditions'] if c['type'] == 'Ready'), 'False')

    def test_missing_initial_references_never_create_a_binding(self):
        docs = self.render(self.xr())
        self.assertEqual(len(docs), 1)
        self.assert_not_ready(docs)
        self.assertFalse(self.status(docs)['referencesResolved'])

    def test_both_subject_kinds_resolve_observed_ids_and_own_only_assignment(self):
        for subject in ['HumanUser', 'MachineUser']:
            with self.subTest(subject=subject):
                xr = self.xr(subject=subject)
                xr['spec']['forProvider'] = {'userId': 'wrong-user', 'orgId': 'wrong-org', 'roleKeys': ['wrong-role'], 'orgIdRef': {'name': 'wrong-org', 'policy': {'resolve': 'Always'}}}
                xr['spec']['labels'] = {'team': 'identity', 'hops.ops.com.ai/managed': 'custom'}
                docs = self.render(xr, self.sources(subject))
                native = self.native(docs)
                self.assertEqual(native['spec']['forProvider'], {'userId': 'user-id', 'projectId': 'project-id', 'orgId': 'grantee-org', 'roleKeys': ['reader']})
                self.assertEqual(native['metadata']['labels']['hops.ops.com.ai/managed'], 'custom')
                self.assertEqual(len(docs), 2)
                self.assert_not_ready(docs)

    def test_all_administrator_scopes(self):
        for scope, target, fields in [
            ('organization', {'organizationRef': {'name': 'tenant'}}, {'orgId': 'grantee-org'}),
            ('project', {'projectRef': {'name': 'product'}}, {'projectId': 'project-id'}),
            ('project_grant', {'projectGrantRef': {'name': 'delegation'}}, {'projectId': 'project-id', 'orgId': 'grantee-org'}),
            ('instance', {'instance': True}, {}),
        ]:
            with self.subTest(scope=scope):
                xr = self.xr('Administrator', 'MachineUser')
                xr['spec']['target'] = target
                xr['spec']['forProvider'] = {'orgId': 'stale-org', 'projectId': 'stale-project', 'resourceType': 'stale'}
                docs = self.render(xr, self.sources('MachineUser'))
                self.assertEqual(self.native(docs, 'Administrator')['spec']['forProvider'],
                                 {'userId': 'user-id', 'resourceType': scope, 'roles': ['ORG_USER_MANAGER'], **fields})
                self.assertFalse(any(d['kind'] == 'Grant' for d in docs))

    def test_cross_namespace_requires_opt_in_and_protects_exact_sources(self):
        xr = self.xr()
        for key in ['subjectRef', 'projectRef', 'organizationRef']:
            xr['spec'][key]['namespace'] = 'identity'
        self.render(xr, self.sources(namespace='identity'), success=False)
        xr['spec']['allowCrossNamespaceReferences'] = True
        docs = self.render(xr, self.sources(namespace='identity'), [self.binding()])
        self.assertTrue(self.status(docs)['ready'])
        usages = [d for d in docs if d['kind'] == 'Usage']
        self.assertEqual(len(usages), 3)
        for usage in usages:
            self.assertEqual(usage['spec']['of']['resourceRef']['namespace'], 'identity')
            self.assertEqual(usage['metadata']['namespace'], 'app')
            # Usage.by is local to the Usage; its schema has no namespace field.
            self.assertNotIn('namespace', usage['spec']['by']['resourceRef'])

    def test_unready_reference_with_id_does_not_remove_assignment(self):
        docs = self.render(self.xr(), self.sources(ready=False), [self.binding()])
        self.assertEqual(self.native(docs)['spec']['forProvider']['roleKeys'], ['reader'])
        self.assertTrue(self.status(docs)['referencesResolved'])
        self.assertFalse(any(d['kind'] == 'Usage' for d in docs))

    def test_missing_or_replaced_reference_retains_old_binding_without_writes(self):
        for kind in ['Authorization', 'Administrator']:
            for changed in [False, True]:
                with self.subTest(kind=kind, changed=changed):
                    extra = self.sources()
                    if changed:
                        extra[0]['status']['atProvider']['id'] = 'replacement-user'
                    else:
                        extra = extra[1:]
                    old = self.binding(kind)
                    docs = self.render(self.xr(kind), extra, [old])
                    native = self.native(docs, kind)
                    self.assertEqual(native['spec']['forProvider'], old['spec']['forProvider'])
                    self.assertEqual(native['spec']['managementPolicies'], ['Observe', 'Delete'])
                    self.assertEqual(native['metadata']['annotations']['crossplane.io/external-name'], 'existing-id')
                    self.assert_not_ready(docs)
                    self.assertFalse(self.status(docs)['referencesResolved'])
                    condition = next(c for c in self.status(docs)['conditions'] if c['type'] == 'ReferencesResolved')
                    self.assertEqual(condition['reason'], 'IdentityChanged' if changed else 'WaitingForReferences')

    def test_existing_usage_survives_reference_loss_and_stale_native_is_not_ready(self):
        usage = {'apiVersion': 'protection.crossplane.io/v1beta1', 'kind': 'Usage',
                 'metadata': {'name': 'binding-delete-authorization-before-subject', 'namespace': 'app',
                              'annotations': {'crossplane.io/composition-resource-name': 'usage-subject'}},
                 'spec': {'replayDeletion': True, 'of': {'apiVersion': USER_API, 'kind': 'HumanUser', 'resourceRef': {'name': 'person', 'namespace': 'app'}},
                          'by': {'apiVersion': self.binding()['apiVersion'], 'kind': 'Authorization', 'resourceRef': {'name': 'binding-authorization'}}}}
        docs = self.render(self.xr(), self.sources()[1:], [self.binding(), usage])
        self.assertEqual(next(d['spec'] for d in docs if d['kind'] == 'Usage'), usage['spec'])
        self.assert_not_ready(docs)
        old = self.binding()
        old['status']['conditions'][1]['observedGeneration'] = 2
        docs = self.render(self.xr(), self.sources(), [old])
        self.assert_not_ready(docs)
        self.assertTrue(self.status(docs)['referencesResolved'])

    def test_import_and_retention_policies(self):
        xr = self.xr()
        xr['spec'].update(binding={'resourceName': 'adopt-existing', 'externalName': 'remote-existing'}, managementPolicies=['Observe'])
        docs = self.render(xr, self.sources())
        native = self.native(docs)
        self.assertEqual(native['metadata']['name'], 'adopt-existing')
        self.assertEqual(native['metadata']['annotations']['crossplane.io/external-name'], 'remote-existing')
        self.assertEqual(native['spec']['managementPolicies'], ['Observe'])
        docs = self.render(self.xr(), self.sources()[1:], [self.binding(policies=['Observe', 'Update'])])
        self.assertEqual(self.native(docs)['spec']['managementPolicies'], ['Observe'])

    def test_import_waits_for_verified_observation_before_writes(self):
        xr = self.xr()
        xr['spec']['binding'] = {'externalName': 'existing-id'}
        docs = self.render(xr, self.sources())
        self.assertEqual(self.native(docs)['spec']['managementPolicies'], ['Observe'])
        self.assert_not_ready(docs)
        old = self.binding()
        docs = self.render(xr, self.sources(), [old])
        self.assertEqual(self.native(docs)['spec']['managementPolicies'], ['*'])
        self.assertTrue(self.status(docs)['bindingIdentityVerified'])
        missing = self.render(xr, self.sources()[1:], [old])
        self.assertEqual(self.native(missing)['spec']['managementPolicies'], ['Observe', 'Delete'])
        old['status']['atProvider']['userId'] = 'unexpected-remote-user'
        docs = self.render(xr, self.sources(), [old])
        self.assertEqual(self.native(docs)['spec']['managementPolicies'], ['Observe'])
        self.assertFalse(self.status(docs)['bindingIdentityVerified'])
        self.assert_not_ready(docs)

    def test_project_delegation_must_match_and_is_never_created_per_user(self):
        xr = self.xr()
        xr['spec']['projectGrantRef'] = {'name': 'delegation'}
        extra = self.sources()
        extra[-1]['status']['atProvider']['grantedOrgId'] = 'wrong-grantee'
        docs = self.render(xr, extra, [self.binding()])
        self.assert_not_ready(docs)
        self.assertEqual(self.native(docs)['spec']['managementPolicies'], ['Observe', 'Delete'])
        extra[-1]['status']['atProvider']['grantedOrgId'] = 'grantee-org'
        docs = self.render(xr, extra, [self.binding()])
        self.assertEqual(len([d for d in docs if d['kind'] == 'Usage']), 4)
        self.assertFalse(any(d['kind'] == 'Grant' for d in docs))


if __name__ == '__main__':
    unittest.main()
