# auth-stack

Installs Zitadel into a Kubernetes cluster as the platform identity provider. Wraps the upstream `zitadel/zitadel` Helm chart with a typed XRD surface that handles the namespace, the database wiring, Gateway API routing, and re-projects the chart-managed bootstrap secrets (admin PAT + login-client PAT) into XR status for downstream consumers.

## Quick Start

Local-dev (colima cluster, bundled Postgres, no TLS):

```yaml
apiVersion: hops.ops.com.ai/v1alpha1
kind: AuthStack
metadata:
  name: auth
  namespace: default
spec:
  clusterName: colima
  domain: auth.localtest.me
  externalSecure: false
  database:
    bundled: true
```

Production (managed Postgres + Gateway API):

```yaml
apiVersion: hops.ops.com.ai/v1alpha1
kind: AuthStack
metadata:
  name: auth
  namespace: platform
spec:
  clusterName: prod
  domain: auth.example.com
  firstInstance:
    org: hops-ops
  database:
    external:
      dsnSecretRef:
        name: zitadel-db
        key: dsn
  gateway:
    enabled: true
    parentRef:
      name: platform-gateway
      namespace: istio-system
```

## Database Modes

Exactly one of:

| Mode | When | Notes |
|---|---|---|
| `external` | Production with managed Postgres (RDS, CNPG cluster, etc.) | Provide a Secret containing the DSN; chart reads `ZITADEL_DATABASE_POSTGRES_DSN`. |
| `bundled` | Local dev only | Sets `postgresql.enabled=true` so the chart uses its bundled Bitnami subchart. Not for production. |
| `psqlStack` | Future | Reserved for the platform PSQLStack integration; pending the `PSQLDatabase` XRD. The composition currently rejects this mode. |

## Bootstrap & Status Contract

The `zitadel/zitadel` chart's setup hook creates two machine users on first install:

- `<iamAdmin.username>` — JWT machine key in a chart-managed Secret named after the username
- `<iamAdmin.username>-pat` — admin PAT
- `<loginClient.username>` — login-client PAT

This stack does not author its own init Job. It re-projects those Secret references into XR status so downstream consumers (the future Zitadel Crossplane provider, ad-hoc admin tooling) have a stable place to read the credentials:

```yaml
status:
  oidc:
    issuerURL: https://auth.example.com
    discoveryURL: https://auth.example.com/.well-known/openid-configuration
  bootstrap:
    iamAdminPatSecretRef:    { name: iam-admin-pat,  namespace: zitadel, key: pat }
    iamAdminKeySecretRef:    { name: iam-admin,      namespace: zitadel, key: key }
    loginClientPatSecretRef: { name: login-client,   namespace: zitadel, key: pat }
```

## Cross-Stack Integration

The intent is for consumer stacks (gitops/ArgoCD, observe/Grafana, the-website) to wire to AuthStack's status surface rather than configuring OIDC manually. Today, those consumers still need a Zitadel OIDC application created out-of-band (via the Zitadel UI/API) and a client ID/secret provided to them. Once the Zitadel Crossplane provider lands, consumer stacks can declaratively create OIDC applications by referencing `status.bootstrap.iamAdminPatSecretRef`.

See [[specs/auth-stack-zitadel]] for the design and open questions.

## Out of Scope

- Per-app OIDC client creation (lives with the Zitadel API or the future Zitadel Crossplane provider).
- Istio `RequestAuthentication` / `AuthorizationPolicy` (per-app concern, may land later).
- Authentik decommission (per-consumer migration tracked separately).

## References

- Spec: `[[specs/auth-stack-zitadel]]`
- Task: `[[tasks/auth-stack]]`
- Upstream chart: `zitadel/zitadel` 9.34.1 (ships Zitadel v4)
