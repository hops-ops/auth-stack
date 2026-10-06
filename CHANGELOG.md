### What's changed in v1.12.0

* feat: observe installed Zitadel instances through native references (#32) (by @patrickleet)

  * feat: observe installed instances through native references

  Replace the discovery Job and metadata ConfigMap with a read-only Instance using a consumer-owned ProviderConfig. Expose its typed name reference and require current-generation successful observation for readiness.

  BREAKING CHANGE: enabled instanceDiscovery requires providerConfigRef; the Job transport fields are removed. Discovery remains disabled by default, and instanceId status remains available after successful observation.

  Signed-off-by: Patrick Lee Scott <pat@patscott.io>

  * test: align CI validation with all local examples

  Signed-off-by: Patrick Lee Scott <pat@patscott.io>

  ---------

  Signed-off-by: Patrick Lee Scott <pat@patscott.io>


See full diff: [v1.11.1...v1.12.0](https://github.com/hops-ops/auth-stack/compare/v1.11.1...v1.12.0)
