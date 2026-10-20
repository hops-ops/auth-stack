# SPDX-FileCopyrightText: 2026 The Crossplane Authors
# SPDX-License-Identifier: Apache-2.0

"""Opt-in live-cluster helpers. No credentials or existing application IDs are stored."""
import base64
import json
import os
import ssl
import subprocess
import time
import unittest
import urllib.request
import uuid


class LiveSuite(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        required = ('ZITADEL_E2E_CONTEXT', 'ZITADEL_E2E_API_URL', 'ZITADEL_E2E_CREDENTIALS_SECRET')
        missing = [key for key in required if not os.environ.get(key)]
        if missing:
            raise unittest.SkipTest('live cluster opt-in required: ' + ', '.join(missing))
        cls.context = os.environ['ZITADEL_E2E_CONTEXT']
        cls.url = os.environ['ZITADEL_E2E_API_URL'].rstrip('/')
        cls.namespace = 'zitadel-bindings-e2e-' + uuid.uuid4().hex[:10]
        cls.owned = []
        cls.namespaces = [cls.namespace]
        cls.provider = {'name': os.environ.get('ZITADEL_E2E_PROVIDER_CONFIG', 'default'), 'kind': 'ClusterProviderConfig'}
        secret_namespace, secret_name = os.environ['ZITADEL_E2E_CREDENTIALS_SECRET'].split('/', 1)
        secret = cls.kube('get', 'secret', secret_name, '-n', secret_namespace, '-o', 'json')
        credentials = json.loads(base64.b64decode(secret['data']['credentials']))
        cls.headers = dict(credentials.get('transport_headers', {}))
        cls.headers.update({'Authorization': 'Bearer ' + credentials['access_token'],
                            'Content-Type': 'application/json', 'Connect-Protocol-Version': '1'})
        cls.tls = ssl.create_default_context(cafile=os.environ.get('ZITADEL_E2E_CA_FILE'))
        cls.kube('create', 'namespace', cls.namespace)
        print('Disposable fixture namespace: ' + cls.namespace, flush=True)
        cls.addClassCleanup(cls.cleanup)
        cls.owner = cls.managed('Organization', 'owner', 'org', {'name': cls.namespace + '-owner'})
        cls.grantee = cls.managed('Organization', 'grantee', 'org', {'name': cls.namespace + '-grantee'})
        cls.human = cls.managed('HumanUser', 'human', 'user', {
            'orgIdRef': {'name': 'owner'}, 'userName': cls.namespace + '-human', 'firstName': 'E2E',
            'lastName': 'User', 'email': cls.namespace + '@example.com'})
        cls.machine = cls.managed('MachineUser', 'machine', 'user', {
            'orgIdRef': {'name': 'owner'}, 'userName': cls.namespace + '-machine', 'name': 'E2E machine'})
        cls.project = cls.managed('ProjectV2', 'product', 'project', {
            'orgIdRef': {'name': 'owner'}, 'name': 'E2E product'})
        for role in ('reader', 'writer'):
            cls.managed('Role', role, 'project', {'orgId': cls.remote_id(cls.owner),
                'projectId': cls.remote_id(cls.project), 'roleKey': role, 'displayName': role})
        cls.delegation = cls.managed('Grant', 'shared', 'project', {
            'orgId': cls.remote_id(cls.owner), 'projectId': cls.remote_id(cls.project),
            'grantedOrgId': cls.remote_id(cls.grantee), 'roleKeys': ['reader', 'writer']})

    @classmethod
    def kube(cls, *args, body=None):
        p = subprocess.run(['kubectl', '--context', cls.context, '--request-timeout=30s', *args],
            input=json.dumps(body) if body is not None else None, text=True, capture_output=True, timeout=40)
        if p.returncode:
            raise RuntimeError('kubectl failed: ' + p.stderr)
        return json.loads(p.stdout) if p.stdout.strip().startswith(('{', '[')) else p.stdout

    @classmethod
    def api(cls, service, method, body):
        req = urllib.request.Request(cls.url + '/zitadel.' + service + '/' + method,
            data=json.dumps(body).encode(), headers=cls.headers, method='POST')
        with urllib.request.urlopen(req, context=cls.tls, timeout=30) as response:
            return json.load(response)

    @staticmethod
    def remote_id(resource):
        return resource['status']['atProvider']['id']

    @classmethod
    def wait(cls, check, description, timeout=180):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            result = check()
            if result:
                return result
            time.sleep(1)
        raise AssertionError('Timed out: ' + description)

    @classmethod
    def get(cls, resource, name, namespace=None):
        result = cls.kube('get', resource, name, '-n', namespace or cls.namespace,
                          '--ignore-not-found', '-o', 'json')
        return result if isinstance(result, dict) else None

    @classmethod
    def ready(cls, resource, name, namespace=None):
        def observed():
            x = cls.get(resource, name, namespace)
            if not x:
                return False
            conditions = {c['type']: c for c in x.get('status', {}).get('conditions', [])}
            synced = conditions.get('Synced', {})
            return x if conditions.get('Ready', {}).get('status') == 'True' and \
                synced.get('status') == 'True' and synced.get('observedGeneration') == x['metadata']['generation'] else False
        return cls.wait(observed, resource + '/' + name + ' Ready/Synced')

    @classmethod
    def apply(cls, obj):
        resource = obj['kind'] + '.' + obj['apiVersion'].split('/')[0]
        ns, name = obj['metadata']['namespace'], obj['metadata']['name']
        key = (resource, name, ns)
        if key not in cls.owned:
            cls.owned.append(key)
        cls.kube('apply', '-f', '-', body=obj)
        return resource, name

    @classmethod
    def managed(cls, kind, name, group, parameters, policies=None, external_name=None):
        obj = {'apiVersion': group + '.zitadel.m.crossplane.io/v1alpha1', 'kind': kind,
            'metadata': {'name': name, 'namespace': cls.namespace}, 'spec': {
                'managementPolicies': policies or ['*'], 'forProvider': parameters,
                'providerConfigRef': cls.provider}}
        if external_name:
            obj['metadata']['annotations'] = {'crossplane.io/external-name': external_name}
        resource, name = cls.apply(obj)
        result = cls.ready(resource, name)
        print(kind + '/' + name + ' Ready/Synced', flush=True)
        return result

    @classmethod
    def delete(cls, resource, name, namespace=None):
        ns = namespace or cls.namespace
        before = cls.get(resource, name, ns) or {}
        children = before.get('spec', {}).get('crossplane', {}).get('resourceRefs', [])
        cls.kube('delete', resource, name, '-n', ns, '--ignore-not-found', '--wait=false')
        cls.wait(lambda: not cls.get(resource, name, ns), 'deletion of ' + resource + '/' + name)
        # XR removal can precede garbage collection of its native binding and
        # Usages. Wait for both before attempting to delete protected parents.
        for child in children:
            child_type = child['kind'] + '.' + child['apiVersion'].split('/')[0]
            cls.wait(lambda child=child, child_type=child_type:
                     not cls.get(child_type, child['name'], ns), 'composed-resource cleanup')
        key = (resource, name, ns)
        if key in cls.owned:
            cls.owned.remove(key)

    @classmethod
    def cleanup(cls):
        errors = []
        # Reverse dependency order: bindings before delegation, roles, project,
        # users and organizations. Do not remove the namespace to hide failures.
        for resource, name, ns in list(reversed(cls.owned)):
            try:
                cls.delete(resource, name, ns)
            except Exception as error:
                errors.append(str(error))
                break
        if errors:
            raise AssertionError('Cleanup failed; retained namespace ' + cls.namespace + ': ' + '; '.join(errors))
        for ns in reversed(cls.namespaces):
            cls.kube('delete', 'namespace', ns, '--wait=false')
            cls.wait(lambda ns=ns: not cls.kube('get', 'namespace', ns, '--ignore-not-found', '-o', 'json'), 'namespace cleanup')

    @classmethod
    def authorizations(cls, identifier):
        return cls.api('authorization.v2.AuthorizationService', 'ListAuthorizations', {
            'pagination': {'limit': 2}, 'filters': [{'authorizationIds': {'ids': [identifier]}}]}).get('authorizations', [])

    def assert_authorization(self, identifier, parameters, roles):
        rows = self.authorizations(identifier)
        self.assertEqual(len(rows), 1)
        r = rows[0]
        self.assertEqual((r['id'], r['user']['id'], r['project']['id'], r['organization']['id']),
            (identifier, parameters['userId'], parameters['projectId'], parameters['orgId']))
        self.assertEqual({r['key'] for r in r['roles']}, set(roles))

    @classmethod
    def administrators(cls, parameters):
        scope = parameters['resourceType']
        target = {'instance': True} if scope == 'instance' else \
            {'organizationId': parameters['orgId']} if scope == 'organization' else \
            {'projectId': parameters['projectId']} if scope == 'project' else \
            {'projectGrant': {'projectId': parameters['projectId'], 'organizationId': parameters['orgId']}}
        return cls.api('internal_permission.v2.InternalPermissionService', 'ListAdministrators', {
            'pagination': {'limit': 2}, 'filters': [
                {'inUserIdsFilter': {'ids': [parameters['userId']]}}, {'resource': target}]}).get('administrators', [])

    def assert_administrator(self, parameters, roles):
        rows = self.administrators(parameters)
        self.assertEqual(len(rows), 1)
        r = rows[0]
        self.assertEqual(r['user']['id'], parameters['userId'])
        self.assertEqual(set(r['roles']), set(roles))
        scope = parameters['resourceType']
        if scope == 'instance':
            self.assertTrue(r['instance'])
        elif scope == 'organization':
            self.assertEqual(r['organization']['id'], parameters['orgId'])
        elif scope == 'project':
            self.assertEqual(r['project']['id'], parameters['projectId'])
        else:
            self.assertEqual(r['projectGrant']['projectId'], parameters['projectId'])
            self.assertEqual(r['projectGrant']['grantedOrganizationId'], parameters['orgId'])
