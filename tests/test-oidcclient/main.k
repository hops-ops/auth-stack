import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

_xr = {
    apiVersion = "auth.hops.ops.com.ai/v1alpha1"
    kind = "OIDCClient"
    metadata = {name = "storybook-pr-381", namespace = "storybook-pr-381"}
    spec = {
        projectId = "project-123"
        redirectUris = ["https://storybook-pr-381.example.com/oauth2/callback"]
        postLogoutRedirectUris = ["https://storybook-pr-381.example.com/"]
        connectionSecretRef = {name = "storybook-oidc-client"}
        credentials = {
            domain = "auth.example.com"
            secretStoreRef = {name = "aws-secrets-manager", kind = "ClusterSecretStore"}
            remoteRef = {key = "push/production/zitadel-credentials", property = "access_token"}
        }
    }
}

items = [
    metav1alpha1.CompositionTest {
        metadata.name = "composes-bootstrap-provider-and-application"
        spec = {
            compositionPath = "apis/oidcclients/composition.yaml"
            xrdPath = "apis/oidcclients/definition.yaml"
            timeoutSeconds = 120
            validate = False
            xr = _xr
            # CompositionTest excludes ProviderConfig kinds from resource
            # assertions. The Object and Oidc references still pin both names.
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata = {
                        name = "storybook-pr-381-zitadel-credentials"
                        namespace = "storybook-pr-381"
                    }
                    spec = {
                        forProvider.manifest = {
                            apiVersion = "external-secrets.io/v1"
                            kind = "ExternalSecret"
                            metadata = {
                                name = "storybook-pr-381-zitadel-credentials"
                                namespace = "storybook-pr-381"
                            }
                            spec = {
                                refreshInterval = "1h"
                                secretStoreRef = {name = "aws-secrets-manager", kind = "ClusterSecretStore"}
                                target = {
                                    name = "storybook-pr-381-zitadel-credentials"
                                    creationPolicy = "Owner"
                                    deletionPolicy = "Retain"
                                }
                                data = [{
                                    secretKey = "access_token"
                                    remoteRef = {key = "push/production/zitadel-credentials", property = "access_token"}
                                }]
                            }
                        }
                        providerConfigRef = {name = "storybook-pr-381-kubernetes", kind = "ProviderConfig"}
                    }
                }
                {
                    apiVersion = "application.zitadel.m.crossplane.io/v1alpha1"
                    kind = "Oidc"
                    metadata = {
                        name = "storybook-pr-381"
                        namespace = "storybook-pr-381"
                    }
                    spec = {
                        forProvider = {
                            name = "storybook-pr-381"
                            projectId = "project-123"
                            redirectUris = ["https://storybook-pr-381.example.com/oauth2/callback"]
                            postLogoutRedirectUris = ["https://storybook-pr-381.example.com/"]
                        }
                        writeConnectionSecretToRef = {name = "storybook-oidc-client"}
                        providerConfigRef = {name = "storybook-pr-381", kind = "ProviderConfig"}
                    }
                }
            ]
        }
    }
    metav1alpha1.CompositionTest {
        metadata.name = "reports-observed-application"
        spec = {
            compositionPath = "apis/oidcclients/composition.yaml"
            xrdPath = "apis/oidcclients/definition.yaml"
            timeoutSeconds = 120
            validate = False
            xr = _xr
            observedResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "ProviderConfig"
                    metadata = {
                        name = "storybook-pr-381-kubernetes"
                        namespace = "storybook-pr-381"
                        annotations = {"crossplane.io/composition-resource-name" = "kubernetes-providerconfig"}
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata = {
                        name = "storybook-pr-381-zitadel-credentials"
                        namespace = "storybook-pr-381"
                        annotations = {"crossplane.io/composition-resource-name" = "credentials"}
                    }
                    status.conditions = [{type = "Ready", status = "True"}]
                }
                {
                    apiVersion = "zitadel.m.crossplane.io/v1beta1"
                    kind = "ProviderConfig"
                    metadata = {
                        name = "storybook-pr-381"
                        namespace = "storybook-pr-381"
                        annotations = {"crossplane.io/composition-resource-name" = "providerconfig"}
                    }
                }
                {
                    apiVersion = "application.zitadel.m.crossplane.io/v1alpha1"
                    kind = "Oidc"
                    metadata = {
                        name = "storybook-pr-381"
                        namespace = "storybook-pr-381"
                        annotations = {"crossplane.io/composition-resource-name" = "oidc"}
                    }
                    status = {
                        atProvider = {id = "app-123", clientId = "client-123"}
                        conditions = [{type = "Ready", status = "True"}]
                    }
                }
            ]
            assertResources = [
                {
                    apiVersion = "auth.hops.ops.com.ai/v1alpha1"
                    kind = "OIDCClient"
                    metadata.name = "storybook-pr-381"
                    status = {applicationId = "app-123", clientId = "client-123"}
                }
                {
                    apiVersion = "protection.crossplane.io/v1beta1"
                    kind = "Usage"
                    metadata = {
                        name = "storybook-pr-381-delete-credentials-before-kubernetes-providerconfig"
                        namespace = "storybook-pr-381"
                    }
                    spec = {
                        replayDeletion = True
                        of = {
                            apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                            kind = "ProviderConfig"
                            resourceRef.name = "storybook-pr-381-kubernetes"
                        }
                        by = {
                            apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                            kind = "Object"
                            resourceRef.name = "storybook-pr-381-zitadel-credentials"
                        }
                    }
                }
                {
                    apiVersion = "protection.crossplane.io/v1beta1"
                    kind = "Usage"
                    metadata = {
                        name = "storybook-pr-381-delete-zitadel-providerconfig-before-credentials"
                        namespace = "storybook-pr-381"
                    }
                    spec = {
                        replayDeletion = True
                        of = {
                            apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                            kind = "Object"
                            resourceRef.name = "storybook-pr-381-zitadel-credentials"
                        }
                        by = {
                            apiVersion = "zitadel.m.crossplane.io/v1beta1"
                            kind = "ProviderConfig"
                            resourceRef.name = "storybook-pr-381"
                        }
                    }
                }
                {
                    apiVersion = "protection.crossplane.io/v1beta1"
                    kind = "Usage"
                    metadata = {
                        name = "storybook-pr-381-delete-oidc-before-zitadel-providerconfig"
                        namespace = "storybook-pr-381"
                    }
                    spec = {
                        replayDeletion = True
                        of = {
                            apiVersion = "zitadel.m.crossplane.io/v1beta1"
                            kind = "ProviderConfig"
                            resourceRef.name = "storybook-pr-381"
                        }
                        by = {
                            apiVersion = "application.zitadel.m.crossplane.io/v1alpha1"
                            kind = "Oidc"
                            resourceRef.name = "storybook-pr-381"
                        }
                    }
                }
            ]
        }
    }
]
