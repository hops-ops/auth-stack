# SPDX-FileCopyrightText: 2026 The Crossplane Authors
# SPDX-License-Identifier: Apache-2.0

"""Live XR -> native provider -> Zitadel checks, with isolated disposable identities."""
import unittest
from live import LiveSuite


class Relationships(LiveSuite):
    def relationship(self, kind, name, spec, namespace=None, wait=True):
        ns = namespace or self.namespace
        obj = {'apiVersion': 'auth.hops.ops.com.ai/v1alpha1', 'kind': kind,
               'metadata': {'name': name, 'namespace': ns},
               'spec': dict(spec, providerConfigRef=self.provider)}
        resource, _ = self.apply(obj)
        return self.ready(resource, name, ns) if wait else self.get(resource, name, ns)

    def native(self, xr):
        kind = xr['kind']
        group = 'authorization' if kind == 'Authorization' else 'internalpermission'
        name = xr['metadata']['name'] + '-' + kind.lower()
        return self.ready(kind + '.' + group + '.zitadel.m.crossplane.io', name, xr['metadata']['namespace'])

    def assert_locks(self, xr, count):
        refs = xr['spec']['crossplane']['resourceRefs']
        locks = [r for r in refs if r['kind'] == 'Usage']
        self.assertEqual(len(locks), count)
        for r in locks:
            lock = self.get('usages.protection.crossplane.io', r['name'], xr['metadata']['namespace'])
            self.assertEqual(lock['spec']['by']['resourceRef']['name'], xr['metadata']['name'] + '-' + xr['kind'].lower())
            self.assertNotIn('namespace', lock['spec']['by']['resourceRef'])

    def test_authorizations(self):
        resource = 'authorizations.auth.hops.ops.com.ai'
        for name, kind, organization in [('human', 'HumanUser', 'owner'),
                                         ('machine', 'MachineUser', 'owner'),
                                         ('delegated', 'MachineUser', 'grantee')]:
            with self.subTest(subject=name):
                spec = {'subjectRef': {'name': 'human' if kind == 'HumanUser' else 'machine', 'kind': kind},
                        'projectRef': {'name': 'product'}, 'organizationRef': {'name': organization}, 'roles': ['reader']}
                if organization == 'grantee':
                    spec['projectGrantRef'] = {'name': 'shared'}
                x = self.relationship('Authorization', name, spec)
                self.assertTrue(x['status']['bindingIdentityVerified'])
                n = self.native(x)
                fp = n['spec']['forProvider']
                identifier = x['status']['bindingId']
                self.assert_authorization(identifier, fp, ['reader'])
                self.assert_locks(x, 4 if organization == 'grantee' else 3)
                spec['roles'] = ['writer']
                x = self.relationship('Authorization', name, spec)
                self.assertEqual(x['status']['bindingId'], identifier)
                self.assert_authorization(identifier, fp, ['writer'])
                observer = dict(spec, managementPolicies=['Observe'], binding={'externalName': identifier})
                observed = self.relationship('Authorization', name + '-import', observer)
                self.assertTrue(observed['status']['bindingIdentityVerified'])
                self.assertEqual(observed['status']['bindingId'], identifier)
                self.delete(resource, name + '-import')
                self.assert_authorization(identifier, fp, ['writer'])
                if name == 'machine':
                    # Import an existing assignment using the wrong user. It must
                    # remain unready, Observe-only and unable to delete it.
                    bad = dict(observer, subjectRef={'name': 'human', 'kind': 'HumanUser'})
                    self.relationship('Authorization', 'mismatch', bad, wait=False)
                    bad_xr = self.wait(lambda: self.mismatch_ready(), 'mismatched import rejection')
                    bad_native = self.get('authorizations.authorization.zitadel.m.crossplane.io', 'mismatch-authorization')
                    self.assertEqual(bad_native['spec']['managementPolicies'], ['Observe'])
                    self.assertFalse(bad_xr['status']['ready'])
                    self.delete(resource, 'mismatch')
                    self.assert_authorization(identifier, fp, ['writer'])
                    # Explicit cross-namespace opt-in must resolve identities
                    # and create Usages protecting resources in their source ns.
                    other = self.namespace + '-observer'
                    self.kube('create', 'namespace', other)
                    self.namespaces.append(other)
                    cross = dict(observer, allowCrossNamespaceReferences=True,
                        subjectRef=dict(spec['subjectRef'], namespace=self.namespace),
                        projectRef=dict(spec['projectRef'], namespace=self.namespace),
                        organizationRef=dict(spec['organizationRef'], namespace=self.namespace))
                    imported = self.relationship('Authorization', 'cross-namespace', cross, namespace=other)
                    self.assertTrue(imported['status']['bindingIdentityVerified'])
                    self.assertEqual(imported['status']['bindingId'], identifier)
                    self.assert_locks(imported, 3)
                    for ref in imported['spec']['crossplane']['resourceRefs']:
                        if ref['kind'] == 'Usage':
                            lock = self.get('usages.protection.crossplane.io', ref['name'], other)
                            self.assertEqual(lock['spec']['of']['resourceRef']['namespace'], self.namespace)
                    self.delete(resource, 'cross-namespace', other)
                    self.assert_authorization(identifier, fp, ['writer'])
                self.delete(resource, name)
                self.wait(lambda: not self.authorizations(identifier), 'remote authorization deletion')

    def mismatch_ready(self):
        x = self.get('authorizations.auth.hops.ops.com.ai', 'mismatch')
        if x and x.get('status', {}).get('bindingId') and x['status'].get('bindingIdentityVerified') is False:
            return x
        return False

    def test_administrators(self):
        resource = 'administrators.auth.hops.ops.com.ai'
        cases = [
            ('instance', {'instance': True}, 'IAM_OWNER_VIEWER', 'IAM_USER_MANAGER', 1),
            ('organization', {'organizationRef': {'name': 'owner'}}, 'ORG_USER_MANAGER', 'ORG_OWNER_VIEWER', 2),
            ('project', {'projectRef': {'name': 'product'}}, 'PROJECT_OWNER_VIEWER', 'PROJECT_OWNER', 2),
            ('project-grant', {'projectGrantRef': {'name': 'shared'}}, 'PROJECT_GRANT_OWNER_VIEWER', 'PROJECT_GRANT_OWNER', 2)]
        for name, target, first, second, locks in cases:
            with self.subTest(scope=name):
                spec = {'subjectRef': {'name': 'machine', 'kind': 'MachineUser'}, 'target': target, 'roles': [first]}
                x = self.relationship('Administrator', name, spec)
                identifier = x['status']['bindingId']
                fp = self.native(x)['spec']['forProvider']
                self.assert_administrator(fp, [first])
                self.assert_locks(x, locks)
                spec['roles'] = [second]
                x = self.relationship('Administrator', name, spec)
                self.assertEqual(x['status']['bindingId'], identifier)
                self.assert_administrator(fp, [second])
                observer = dict(spec, managementPolicies=['Observe'], binding={'externalName': identifier})
                imported = self.relationship('Administrator', name + '-import', observer)
                self.assertTrue(imported['status']['bindingIdentityVerified'])
                self.assertEqual(imported['status']['bindingId'], identifier)
                self.delete(resource, name + '-import')
                self.assert_administrator(fp, [second])
                self.delete(resource, name)
                self.wait(lambda: not self.administrators(fp), 'remote administrator deletion')


if __name__ == '__main__':
    unittest.main(verbosity=2)
