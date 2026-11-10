### What's changed in v1.13.0

* feat: generate masterkey and admin password with ESO (#38) (by @patrickleet)

  feat: generate masterkey and admin password with ESO

  `externalSecrets.generate: true` composes ESO Password generators, a
  CreatedOnce ExternalSecret and an IfNotExists PushSecret that writes
  both inputs as one JSON object to `secretPath`, so a fresh install needs
  no `hops auth bootstrap` seeding. The pull ExternalSecrets are unchanged
  and remain the only path into the chart's Secrets; an existing store
  entry is never overwritten. Off by default: renders without it are
  unchanged.

  fix: guard generated Zitadel bootstrap inputs [[tasks/production-zita…

  …del-durable-inputs]]

  fix: declare embedded PostgreSQL package dependency [[tasks/productio…

  …n-zitadel-durable-inputs]]

  docs: describe generated-input safety tests [[tasks/production-zitade…

  …l-durable-inputs]]


See full diff: [v1.12.2...v1.13.0](https://github.com/hops-ops/auth-stack/compare/v1.12.2...v1.13.0)
