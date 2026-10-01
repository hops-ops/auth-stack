### What's changed in v1.11.0

* feat: expose System API keys and observed Zitadel instance ID (#29) (by @patrickleet)

  * feat: expose system API keys and observed Zitadel instance ID

  Opt-in inputs keep AuthStack environment-neutral; only public keys mount into Zitadel. Read-only discovery publishes metadata for provider-managed domains.

  [[tasks/harmony-1847]]

  * fix(auth)!: constrain instance discovery credential transport

  Bind discovery to the rendered Zitadel Service, verify HTTPS certificates, disable redirects and proxy inheritance, and support explicit CA bundles. Remove the startup wall-clock deadline while retaining API retry and Job backoff limits. Correct PAT rotation documentation.

  BREAKING CHANGE: the opt-in discovery feature requires HTTPS by default; trusted plaintext local clusters must explicitly set allowInsecureHTTP. Harmony PR #135 includes this local-only setting. [[tasks/harmony-1847]]


See full diff: [v1.10.4...v1.11.0](https://github.com/hops-ops/auth-stack/compare/v1.10.4...v1.11.0)
