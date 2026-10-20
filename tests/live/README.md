# Live relationship end-to-end tests

These tests exercise the full XR -> composition functions -> native provider ->
Zitadel chain on an existing test cluster. The fixture helper is self-contained;
no checkout of the provider's test repository is needed.

Coverage: human/machine and delegated Authorizations, all four Administrator
targets, full role replacement preserving binding IDs, Observe-only import,
mismatched-subject import rejection, explicit cross-namespace Observe imports,
dependency Usage locks, and remote deletion.
Each case checks real Authorization/InternalPermission v2 API responses rather
than trusting Ready conditions alone. The shared project delegation is an
independent fixture, not composed separately for each relationship.

Requirements: Python 3 (standard library), kubectl, Zitadel 4.x, and healthy source
or containing-release provider/AuthStack packages with the new APIs. The
cluster-scoped ProviderConfig and the API credentials must address the same
instance with permissions to manage all disposable fixture resources/scopes.

```sh
export ZITADEL_E2E_CONTEXT=<explicit-test-context>
export ZITADEL_E2E_API_URL=https://id.example.com
export ZITADEL_E2E_CREDENTIALS_SECRET=<namespace>/<provider-secret>
# Optional: ZITADEL_E2E_PROVIDER_CONFIG (default default), ZITADEL_E2E_CA_FILE
make e2e-relationships  # also included by make e2e
```

The Secret's `credentials` key contains provider JSON with `access_token` and
optional `transport_headers`; credentials stay in memory. The Make target fails
without the opt-in settings; direct unittest discovery explicitly skips instead.
HTTPS validates certificates. An explicit loopback HTTP port-forward is also
supported. Tests use unique namespaces/identities and delete bindings before
their dependencies. Cleanup failure fails the suite and retains its namespace.
The requested long-lived application examples are not used or modified.

This suite does not install AuthStack's Helm/database/routing infrastructure or
run automatically in the reusable Upbound `tests/e2e*` CI job. That job has no
KCL E2ETest definitions for these relationships. Existing render/security tests
and successful empty e2e jobs do not establish live coverage. Run this target
against an explicitly prepared source/containing-release test cluster before
release, and publish its result separately from render tests.
