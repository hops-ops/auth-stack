import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

# ==============================================================================
# Unit tests for Grant XRD (auth.hops.ops.com.ai)
#
# Verifies the polymorphic dispatch (same-org vs cross-org) and the
# multi-iter gating of user/Grant on observed project/Grant id.
# ==============================================================================

_items = [
    # ==========================================================================
    # Test 1: same-org — userOrgId == projectOrgId. Composes ONE
    # user/Grant MR with no projectGrantId.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "same-org-emits-only-user-grant"
        spec = {
            compositionPath = "apis/grants/composition.yaml"
            xrdPath = "apis/grants/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "Grant"
                metadata = {name = "openpanel-provider-grant", namespace = "default"}
                spec = {
                    userId = "373509289836287598"
                    userOrgId = "373268222482392664"
                    projectId = "373410628280264299"
                    projectOrgId = "373268222482392664"
                    roles = ["openpanel:platform-admin"]
                    providerConfigRef = {name = "zitadel-tenant-stack", kind = "ProviderConfig"}
                }
            }
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "Grant"
                    metadata.name = "openpanel-provider-grant-user-grant"
                    spec = {
                        forProvider = {
                            orgId = "373268222482392664"
                            projectId = "373410628280264299"
                            userId = "373509289836287598"
                            roleKeys = ["openpanel:platform-admin"]
                        }
                        providerConfigRef = {name = "zitadel-tenant-stack", kind = "ProviderConfig"}
                    }
                }
            ]
        }
    },

    # ==========================================================================
    # Test 2: cross-org iter 1 — userOrgId != projectOrgId. Composes the
    # project/Grant MR; user/Grant gated until projectGrant.atProvider.id
    # is observed.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "cross-org-iter1-only-project-grant"
        spec = {
            compositionPath = "apis/grants/composition.yaml"
            xrdPath = "apis/grants/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "Grant"
                metadata = {name = "pat-platform-admin", namespace = "default"}
                spec = {
                    userId = "pat-user-uuid"
                    userOrgId = "pat-brand-org-uuid"
                    projectId = "ops-com-ai-platform-services-uuid"
                    projectOrgId = "ops-com-ai-org-uuid"
                    roles = ["platform-admin"]
                    providerConfigRef = {name = "zitadel-tenant-stack", kind = "ProviderConfig"}
                }
            }
            assertResources = [
                {
                    apiVersion = "project.zitadel.m.crossplane.io/v1alpha1"
                    kind = "Grant"
                    metadata.name = "pat-platform-admin-project-grant"
                    spec.forProvider = {
                        orgId = "ops-com-ai-org-uuid"
                        projectId = "ops-com-ai-platform-services-uuid"
                        grantedOrgId = "pat-brand-org-uuid"
                        roleKeys = ["platform-admin"]
                    }
                }
            ]
        }
    },

    # ==========================================================================
    # Test 3: multi-role grant — multiple roleKeys propagate to the
    # user/Grant MR's forProvider.roleKeys list.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "same-org-multi-role"
        spec = {
            compositionPath = "apis/grants/composition.yaml"
            xrdPath = "apis/grants/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "Grant"
                metadata = {name = "alice-grant", namespace = "default"}
                spec = {
                    userId = "alice-user-uuid"
                    userOrgId = "thrivendale-org-uuid"
                    projectId = "thrivendale-default-project-uuid"
                    projectOrgId = "thrivendale-org-uuid"
                    roles = ["tenant-admin", "tenant-member"]
                    providerConfigRef = {name = "zitadel-tenant-stack", kind = "ProviderConfig"}
                }
            }
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "Grant"
                    metadata.name = "alice-grant-user-grant"
                    spec.forProvider.roleKeys = ["tenant-admin", "tenant-member"]
                }
            ]
        }
    },

    # ==========================================================================
    # Test 4: managementPolicies propagates to all composed MRs (same-org).
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "management-policies-propagated"
        spec = {
            compositionPath = "apis/grants/composition.yaml"
            xrdPath = "apis/grants/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "Grant"
                metadata = {name = "adopt-grant", namespace = "default"}
                spec = {
                    userId = "u"
                    userOrgId = "o"
                    projectId = "p"
                    projectOrgId = "o"
                    roles = ["r"]
                    providerConfigRef = {name = "zitadel-tenant-stack", kind = "ProviderConfig"}
                    managementPolicies = ["Observe", "Update", "LateInitialize"]
                }
            }
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "Grant"
                    metadata.name = "adopt-grant-user-grant"
                    spec.managementPolicies = ["Observe", "Update", "LateInitialize"]
                }
            ]
        }
    },

    # ==========================================================================
    # Test 5: local references remain pending until both namespaced targets
    # are returned by ExtraResources.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "local-references-wait-for-targets"
        spec = {
            compositionPath = "apis/grants/composition.yaml"
            xrdPath = "apis/grants/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "Grant"
                metadata = {name = "alice-grant", namespace = "default"}
                spec = {
                    userIdRef = {name = "e2e-alice"}
                    projectIdRef = {name = "e2e-ui"}
                    roles = ["user"]
                    providerConfigRef = {name = "default", kind = "ClusterProviderConfig"}
                }
            }
            assertResources = [
                {
                    apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                    kind = "Grant"
                    metadata.name = "alice-grant"
                    status.mode = "pending"
                    status.referencesResolved = False
                }
            ]
        }
    },

    # ==========================================================================
    # Test 6: a Hops HumanUser reference uses its typed status contract while
    # the Project reference continues to use raw provider atProvider status.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "hops-human-user-reference-resolves"
        spec = {
            compositionPath = "apis/grants/composition.yaml"
            xrdPath = "apis/grants/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "Grant"
                metadata = {name = "alice-grant", namespace = "default"}
                spec = {
                    userIdRef = {
                        name = "e2e-alice"
                        apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                        kind = "HumanUser"
                    }
                    projectIdRef = {name = "e2e-ui"}
                    roles = ["user"]
                    providerConfigRef = {name = "default", kind = "ClusterProviderConfig"}
                }
            }
            extraResources = [
                {
                    apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                    kind = "HumanUser"
                    metadata = {name = "e2e-alice", namespace = "default"}
                    status = {userId = "user-123", orgId = "org-456", loginName = "alice"}
                }
                {
                    apiVersion = "project.zitadel.m.crossplane.io/v1alpha1"
                    kind = "Project"
                    metadata = {name = "e2e-ui", namespace = "default"}
                    status.atProvider = {id = "project-123", orgId = "org-456"}
                }
            ]
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "Grant"
                    metadata.name = "alice-grant-user-grant"
                    spec.forProvider = {
                        orgId = "org-456"
                        projectId = "project-123"
                        userId = "user-123"
                        roleKeys = ["user"]
                    }
                }
            ]
        }
    },
]

items = _items
