"""Credential destination regressions; run with python3 -m unittest discover -s tests/security.

Requires the same Docker/up setup as render tests. UP_COMMAND can name a wrapper
for running up inside a container on hosts with a remote Docker daemon.
"""
import ast
import json
import os
from pathlib import Path
import shlex
import ssl
import subprocess
import tempfile
import textwrap
import unittest
import urllib.request

ROOT = Path(__file__).resolve().parents[2]


class DiscoveryOriginTests(unittest.TestCase):
    def render(self, url, insecure=False):
        claim = {
            'apiVersion': 'hops.ops.com.ai/v1alpha1', 'kind': 'AuthStack',
            'metadata': {'name': 'identity'},
            'spec': {
                'namespace': 'identity', 'domain': 'auth.example.com',
                'firstInstance': {'masterkey': {'secretRef': {'name': 'masterkey'}}},
                'database': {'external': {'dsnSecretRef': {'name': 'db', 'key': 'dsn'}}},
                'instanceDiscovery': {
                    'enabled': True, 'internalURL': url, 'allowInsecureHTTP': insecure,
                },
            },
        }
        # Keep the input under the source root so containerized renderers see it.
        with tempfile.TemporaryDirectory(dir=ROOT / '.tmp') as directory:
            path = Path(directory) / 'claim.json'
            path.write_text(json.dumps(claim))
            command = shlex.split(os.environ.get('UP_COMMAND', 'up'))
            return subprocess.run(command + [
                'composition', 'render', 'apis/authstacks/composition.yaml', str(path),
            ], cwd=ROOT, capture_output=True, text=True, timeout=180)

    @classmethod
    def setUpClass(cls):
        (ROOT / '.tmp').mkdir(exist_ok=True)

    def test_untrusted_origins_fail_before_rendering_the_pat_job(self):
        for url, insecure in [
            ('https://attacker.example:8080', False),
            ('https://other.identity.svc:8080', False),
            ('https://identity-zitadel.other.svc:8080', False),
            ('https://identity-zitadel.identity.svc:8443', False),
            ('https://identity-zitadel.identity.svc:8080@attacker.example', False),
            ('https://identity-zitadel.identity.svc:8080/path', False),
            ('http://identity-zitadel.identity.svc:8080', False),
            ('http://attacker.identity.svc:8080', True),
        ]:
            with self.subTest(url=url, insecure=insecure):
                result = self.render(url, insecure)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("must target this stack's Zitadel Service", result.stderr + result.stdout)


class DiscoveryTransportTests(unittest.TestCase):
    def setUp(self):
        template = (ROOT / 'functions/render/210-instance-discovery.yaml.gotmpl').read_text()
        script = template.split('                  - |\n', 1)[1].split('                volumeMounts:', 1)[0]
        tree = ast.parse(textwrap.dedent(script))
        # Execute the actual Job transport setup, excluding filesystem/credential
        # reads and the API retry loop. No network or real PAT is needed here.
        self.scope = {'ssl': ssl, 'urllib': __import__('urllib'), 'os': os,
                      'tls': ssl.create_default_context()}
        setup = []
        for node in tree.body:
            if isinstance(node, ast.ClassDef) or (
                isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name)
                and node.targets[0].id in ('zitadel_tls', 'opener', 'api_opener')
            ):
                setup.append(node)
        from unittest.mock import patch
        with patch.dict(os.environ, {'ZITADEL_CA_FILE': '', 'https_proxy': 'http://attacker:8080'}):
            exec(compile(ast.Module(body=setup, type_ignores=[]), '<discovery-transport>', 'exec'), self.scope)

    def test_tls_verifies_service_identity(self):
        self.assertTrue(self.scope['zitadel_tls'].check_hostname)
        self.assertEqual(self.scope['zitadel_tls'].verify_mode, ssl.CERT_REQUIRED)

    def test_redirects_cannot_forward_bearer_headers(self):
        handler = self.scope['NoRedirect']()
        request = urllib.request.Request('https://identity-zitadel.identity.svc:8080',
                                         headers={'Authorization': 'Bearer fake-test-token'})
        for status in (301, 302, 303, 307, 308):
            with self.subTest(status=status), self.assertRaises(ValueError):
                handler.redirect_request(request, None, status, '', {}, 'https://attacker.example')

    def test_proxy_environment_is_ignored_for_both_credentials(self):
        for name in ('opener', 'api_opener'):
            self.assertFalse(any(isinstance(handler, urllib.request.ProxyHandler)
                                 and handler.proxies for handler in self.scope[name].handlers))


if __name__ == '__main__':
    unittest.main()
