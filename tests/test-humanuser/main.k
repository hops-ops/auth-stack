import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

_base_spec = {
    firstName = "Alice"
    lastName = "Example"
    email = "alice@example.com"
    providerConfigRef = {name = "default", kind = "ClusterProviderConfig"}
}

_items = [
    # Explicit IDs render on the first iteration and map the intent fields.
    metav1alpha1.CompositionTest {
        metadata.name = "explicit-org-renders-human-user"
        spec = {
            compositionPath = "apis/humanusers/composition.yaml"
            xrdPath = "apis/humanusers/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "HumanUser"
                metadata = {name = "alice", namespace = "default"}
                spec = _base_spec | {
                    orgId = "org-123"
                    displayName = "Alice"
                    isEmailVerified = True
                    initialSkipPasswordChange = True
                    initialPasswordSecretRef = {name = "human-passwords", key = "alice"}
                }
            }
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "HumanUser"
                    metadata = {
                        name = "alice"
                        labels = {
                            "hops.ops.com.ai/managed" = "true"
                            "hops.ops.com.ai/auth-humanuser" = "alice"
                        }
                    }
                    spec = {
                        forProvider = {
                            orgId = "org-123"
                            userName = "alice"
                            firstName = "Alice"
                            lastName = "Example"
                            email = "alice@example.com"
                            displayName = "Alice"
                            isEmailVerified = True
                            initialSkipPasswordChange = True
                            initialPasswordSecretRef = {name = "human-passwords", key = "alice"}
                        }
                        providerConfigRef = {name = "default", kind = "ClusterProviderConfig"}
                    }
                }
            ]
        }
    }

    # A referenced Project supplies status.atProvider.orgId without requiring a
    # generated UUID in the HumanUser spec.
    metav1alpha1.CompositionTest {
        metadata.name = "project-reference-resolves-org"
        spec = {
            compositionPath = "apis/humanusers/composition.yaml"
            xrdPath = "apis/humanusers/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "HumanUser"
                metadata = {name = "alice", namespace = "default"}
                spec = _base_spec | {orgIdRef = {name = "e2e-ui"}}
            }
            extraResources = [
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
                    kind = "HumanUser"
                    metadata.name = "alice"
                    spec.forProvider.orgId = "org-456"
                }
            ]
        }
    }

    # An unresolved reference still renders the raw resource so canonical
    # readiness cannot report an empty desired set as ready.
    metav1alpha1.CompositionTest {
        metadata.name = "missing-project-keeps-user-pending"
        spec = {
            compositionPath = "apis/humanusers/composition.yaml"
            xrdPath = "apis/humanusers/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "HumanUser"
                metadata = {name = "alice", namespace = "default"}
                spec = _base_spec | {orgIdRef = {name = "e2e-ui"}}
            }
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "HumanUser"
                    metadata.name = "alice"
                    spec.forProvider.orgId = ""
                }
            ]
        }
    }

    # A transient source lookup miss does not un-render an existing user. The
    # composed user's observed orgId is an existence-stable fallback.
    metav1alpha1.CompositionTest {
        metadata.name = "observed-user-keeps-rendering-without-source"
        spec = {
            compositionPath = "apis/humanusers/composition.yaml"
            xrdPath = "apis/humanusers/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "HumanUser"
                metadata = {name = "alice", namespace = "default"}
                spec = _base_spec | {orgIdRef = {name = "e2e-ui"}}
            }
            observedResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "HumanUser"
                    metadata = {
                        name = "alice"
                        namespace = "default"
                        annotations = {
                            "crossplane.io/composition-resource-name" = "humanuser"
                            "gotemplating.fn.crossplane.io/composition-resource-name" = "humanuser"
                        }
                    }
                    status = {
                        atProvider = {id = "user-123", orgId = "org-456", preferredLoginName = "alice"}
                        conditions = [{type = "Ready", status = "False"}]
                    }
                }
            ]
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "HumanUser"
                    metadata.name = "alice"
                    spec.forProvider.orgId = "org-456"
                }
                {
                    apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                    kind = "HumanUser"
                    metadata.name = "alice"
                    status = {userId = "user-123", orgId = "org-456", loginName = "alice"}
                }
            ]
        }
    }

    # Adoption propagates only the stable external identifier and policies.
    metav1alpha1.CompositionTest {
        metadata.name = "adopt-existing-human-user"
        spec = {
            compositionPath = "apis/humanusers/composition.yaml"
            xrdPath = "apis/humanusers/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                kind = "HumanUser"
                metadata = {name = "alice", namespace = "default"}
                spec = _base_spec | {
                    orgId = "org-123"
                    humanUserId = "user-123"
                    managementPolicies = ["Observe", "Update", "LateInitialize"]
                }
            }
            assertResources = [
                {
                    apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                    kind = "HumanUser"
                    metadata = {
                        name = "alice"
                        annotations = {"crossplane.io/external-name" = "user-123"}
                    }
                    spec.managementPolicies = ["Observe", "Update", "LateInitialize"]
                }
            ]
        }
    }
]

items = _items
