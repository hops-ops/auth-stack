import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

# ==============================================================================
# Unit tests for MachineUser XRD (auth.hops.ops.com.ai)
#
# Verifies first-iteration emission + the conditional behaviors:
#   - pat.enabled default false → only MachineUser MR composes
#   - pat.enabled true → AccessToken composes once userId observed
#   - pat.pushToAwsSm true → AWS SM Secret + ESO PushSecret compose once
#     patTokenId observed
#
# Multi-iter convergence (Project + Roles + AWS-SM/PushSecret after their
# upstream observations) is verified via `up composition render
# --observed-resources` against tests/test-machineuser/observed/*.yaml.
# ==============================================================================

_items = [
    # ==========================================================================
    # Test 1: minimal — only MachineUser MR composes; no PAT, no push.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "minimal-machineuser-only"
        spec = {
            compositionPath = "apis/machineusers/composition.yaml"
            xrdPath = "apis/machineusers/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "MachineUser"
                metadata = {name = "zitadel-provider", namespace = "default"}
                spec = {
                    orgId = "373268222482392664"
                    displayName = "zitadel-provider"
                    accessTokenType = "ACCESS_TOKEN_TYPE_JWT"
                    providerConfigRef = {name = "zitadel-tenant-stack", kind = "ProviderConfig"}
                }
            }
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "MachineUser"
                    metadata.name = "zitadel-provider"
                    spec = {
                        forProvider = {
                            orgId = "373268222482392664"
                            userName = "zitadel-provider"
                            name = "zitadel-provider"
                            accessTokenType = "ACCESS_TOKEN_TYPE_JWT"
                        }
                        providerConfigRef = {name = "zitadel-tenant-stack", kind = "ProviderConfig"}
                    }
                }
            ]
        }
    },

    # ==========================================================================
    # Test 2: pat.enabled (iter 1) — AccessToken gated until userId observed,
    # so iter-1 still emits only MachineUser. AccessToken emission is
    # verified separately via observed-resources fixture.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "pat-enabled-iter1-still-only-machineuser"
        spec = {
            compositionPath = "apis/machineusers/composition.yaml"
            xrdPath = "apis/machineusers/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "MachineUser"
                metadata = {name = "ci-bot", namespace = "default"}
                spec = {
                    orgId = "373268222482392664"
                    pat = {enabled = True}
                    providerConfigRef = {name = "zitadel-tenant-stack", kind = "ProviderConfig"}
                }
            }
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "MachineUser"
                    metadata.name = "ci-bot"
                }
            ]
        }
    },

    # ==========================================================================
    # Test 3: adoption — spec.machineUserId propagates as external-name;
    # managementPolicies excludes Create.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "adopt-existing-machineuser-via-id"
        spec = {
            compositionPath = "apis/machineusers/composition.yaml"
            xrdPath = "apis/machineusers/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "MachineUser"
                metadata = {name = "iam-admin", namespace = "default"}
                spec = {
                    orgId = "373268222482392664"
                    machineUserId = "existing-iam-admin-uuid"
                    providerConfigRef = {name = "zitadel-tenant-stack", kind = "ProviderConfig"}
                    managementPolicies = ["Observe", "Update", "LateInitialize"]
                }
            }
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "MachineUser"
                    metadata = {
                        name = "iam-admin"
                        annotations = {"crossplane.io/external-name" = "existing-iam-admin-uuid"}
                    }
                    spec.managementPolicies = ["Observe", "Update", "LateInitialize"]
                }
            ]
        }
    },

    # ==========================================================================
    # Test 4: userName + displayName + description override defaults.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "field-overrides"
        spec = {
            compositionPath = "apis/machineusers/composition.yaml"
            xrdPath = "apis/machineusers/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "MachineUser"
                metadata = {name = "openpanel-provider", namespace = "default"}
                spec = {
                    orgId = "373268222482392664"
                    userName = "openpanel-crossplane-admin"
                    displayName = "OpenPanel Crossplane Admin"
                    description = "/manage credential for provider-upjet-openpanel"
                    accessTokenType = "ACCESS_TOKEN_TYPE_BEARER"
                    providerConfigRef = {name = "zitadel-tenant-stack", kind = "ProviderConfig"}
                }
            }
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "MachineUser"
                    metadata.name = "openpanel-provider"
                    spec.forProvider = {
                        orgId = "373268222482392664"
                        userName = "openpanel-crossplane-admin"
                        name = "OpenPanel Crossplane Admin"
                        description = "/manage credential for provider-upjet-openpanel"
                        accessTokenType = "ACCESS_TOKEN_TYPE_BEARER"
                    }
                }
            ]
        }
    },
]

items = _items
