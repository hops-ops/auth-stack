### What's changed in v1.11.1

* fix(deps): update helm release zitadel to v10.3.0 (by @renovate[bot])

  XR chart pin 10.1.0→10.3.0. Upstream adds optional probe timeoutSeconds/successThreshold/terminationGracePeriodSeconds and bundles k8s schemas for air-gapped installs; neither changes our chartValues/defaults usage. e2e/validate/test/publish green.


See full diff: [v1.11.0...v1.11.1](https://github.com/hops-ops/auth-stack/compare/v1.11.0...v1.11.1)
