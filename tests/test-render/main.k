import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

_ready_conditions = [
    {type = "Ready", status = "True"}
    {type = "Synced", status = "True"}
]

# ==============================================================================
# Unit tests for AuthStack XRD
#
# Philosophy: test YOUR API surface. The chart's behavior is the chart's
# concern; we verify spec → composed Helm Release values + status projection.
# ==============================================================================

_items = [
    # ==========================================================================
    # Test 1: Masterkey secretRef wires masterkeySecretName
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "masterkey-secretref-wires-name"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "mk-secret"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "mk-secret-zitadel"
                    spec.forProvider.values = {
                        zitadel.masterkeySecretName = "zitadel-masterkey"
                        resources = {
                            requests = {cpu = "23m", memory = "156Mi"}
                            limits = {cpu = "200m", memory = "384Mi"}
                        }
                        login.resources = {
                            requests = {cpu = "15m", memory = "105Mi"}
                            limits = {cpu = "500m", memory = "512Mi"}
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 2: Masterkey inline writes the value directly (dev only)
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "masterkey-inline-sets-value"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "mk-inline"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance.masterkey.inline = "01234567890123456789012345678901"
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "mk-inline-zitadel"
                    spec.forProvider.values.zitadel.masterkey = "01234567890123456789012345678901"
                }
            ]
        }
    }

    # ==========================================================================
    # Test 3a: psqlClusterRef wires the Postgres connection details and pins
    # Admin.ExistingDatabase so Zitadel's init VerifyDatabase short-circuits.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "psql-cluster-ref-pins-existing-database"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "pg-auth"
                metadata.namespace = "zitadel"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.psqlClusterRef.name = "zitadel-pg"
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "pg-auth-zitadel"
                    spec.forProvider.values.zitadel.configmapConfig.Database.Postgres = {
                        Host = "zitadel-pg-rw.zitadel.svc.cluster.local"
                        Port = 5432
                        Database = "app"
                        User.SSL.Mode = "disable"
                        Admin.SSL.Mode = "disable"
                        # ExistingDatabase pins the Admin connection to the
                        # already-existing app DB so Zitadel's init verify
                        # short-circuits CREATE DATABASE (CNPG app user has no
                        # CREATEDB).
                        Admin.ExistingDatabase = "app"
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 3c: spec.database.embedded composes a PSQLCluster XR with the
    # AuthStack install ns as its targetNamespace.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "embedded-composes-psql-cluster-xr"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "emb-auth"
                metadata.namespace = "default"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    namespace = "zitadel"
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.embedded = {
                        storage.size = "2Gi"
                    }
                }
            }
            assertResources = [
                # Embedded PSQLCluster XR — name derived from AuthStack name,
                # targetNamespace = install ns so CNPG resources land where
                # Zitadel pods can env-var-mount the app Secret.
                {
                    apiVersion = "hops.ops.com.ai/v1alpha1"
                    kind = "PSQLCluster"
                    metadata = {
                        name = "emb-auth-pg"
                        namespace = "default"
                    }
                    spec = {
                        clusterName = "test-cluster"
                        targetNamespace = "zitadel"
                        storage.size = "2Gi"
                        app.role = "zitadel"
                        app.database = "zitadel"
                    }
                }
                # Helm release wires DB connection from the composed
                # PSQLCluster's expected CNPG service + app Secret.
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "emb-auth-zitadel"
                    spec.forProvider.values.zitadel.configmapConfig.Database.Postgres = {
                        Host = "emb-auth-pg-rw.zitadel.svc.cluster.local"
                        Port = 5432
                        Database = "zitadel"
                        Admin.ExistingDatabase = "zitadel"
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 3b: externalSecrets composes masterkey + admin-password ExternalSecrets
    # against ONE shared AWS SM secret with different `property:` selectors.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "external-secrets-composes-from-shared-aws-sm-path"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "eso-auth"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    externalSecrets = {
                        enabled = True
                        secretPath = "test/zitadel"
                    }
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.psqlClusterRef.name = "zitadel-pg"
                }
            }
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "eso-auth-external-secret-masterkey"
                    spec.forProvider.manifest = {
                        apiVersion = "external-secrets.io/v1"
                        kind = "ExternalSecret"
                        metadata.name = "zitadel-masterkey"
                        spec.data = [{
                            secretKey = "masterkey"
                            remoteRef = {key = "test/zitadel", property = "masterkey"}
                        }]
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "eso-auth-external-secret-admin-password"
                    spec.forProvider.manifest = {
                        apiVersion = "external-secrets.io/v1"
                        kind = "ExternalSecret"
                        metadata.name = "zitadel-admin-password"
                        spec.data = [{
                            secretKey = "password"
                            remoteRef = {key = "test/zitadel", property = "admin-password"}
                        }]
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 4: External DSN populates ZITADEL_DATABASE_POSTGRES_DSN env
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "external-dsn-wires-secret-env"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "ext-auth"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "ext-auth-zitadel"
                    spec.forProvider.values.env = [
                        {
                            name = "ZITADEL_DATABASE_POSTGRES_DSN"
                            valueFrom.secretKeyRef = {
                                name = "zitadel-db"
                                key = "dsn"
                            }
                        }
                    ]
                }
            ]
        }
    }

    # ==========================================================================
    # Test 4: Gateway enabled drives chart's gateway.httpRoute and grpcRoute
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "gateway-enabled-renders-routes"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "gw-auth"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                    gateway = {
                        enabled = True
                        parentRef = {
                            name = "platform-gateway"
                            namespace = "istio-system"
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "gw-auth-zitadel"
                    spec.forProvider.values.gateway = {
                        httpRoute = {
                            enabled = True
                            parentRefs = [{name = "platform-gateway", namespace = "istio-system"}]
                            hostnames = ["auth.example.com"]
                        }
                        grpcRoute = {
                            enabled = True
                            parentRefs = [{name = "platform-gateway", namespace = "istio-system"}]
                            hostnames = ["auth.example.com"]
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 5: Custom labels merged with defaults on every resource
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "custom-labels-merged-with-defaults"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "labeled-auth"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    labels = {team = "platform", environment = "staging"}
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata = {
                        name = "labeled-auth-namespace"
                        labels = {
                            "hops.ops.com.ai/managed" = "true"
                            "hops.ops.com.ai/authstack" = "labeled-auth"
                            team = "platform"
                            environment = "staging"
                        }
                    }
                }
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata = {
                        name = "labeled-auth-zitadel"
                        labels = {
                            "hops.ops.com.ai/managed" = "true"
                            "hops.ops.com.ai/authstack" = "labeled-auth"
                            team = "platform"
                            environment = "staging"
                        }
                    }
                }
            ]
        }
    }


    # ==========================================================================
    # Test 7a: externalSecrets.enabled=false — no PushSecret composed.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "pushsecret-disabled-without-externalsecrets"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "no-push"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "no-push-zitadel"
                }
            ]
        }
    }

    # ==========================================================================
    # Test 7b: externalSecrets.enabled=true composes the iam-admin PAT
    # PushSecret on the target cluster with the default AWS SM path
    # `<clusterName>/pushed/zitadel-credentials` and property `access_token`.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "pushsecret-defaults-from-externalsecrets-enabled"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "ps-defaults"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    externalSecrets = {
                        enabled = True
                        secretPath = "test/zitadel"
                    }
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "ps-defaults-credentials-pushsecret"
                    spec = {
                        forProvider.manifest = {
                            apiVersion = "external-secrets.io/v1alpha1"
                            kind = "PushSecret"
                            metadata = {
                                name = "zitadel-iam-admin-pat"
                                namespace = "zitadel"
                            }
                            spec = {
                                refreshInterval = "1h"
                                secretStoreRefs = [{
                                    name = "hops-aws-secrets-manager"
                                    kind = "ClusterSecretStore"
                                }]
                                selector.secret.name = "iam-admin-pat"
                                data = [{
                                    match = {
                                        secretKey = "pat"
                                        remoteRef = {
                                            remoteKey = "push/test-cluster/zitadel-credentials"
                                            property = "access_token"
                                        }
                                    }
                                    # AWS SM tag set: composition defaults + AuthStack labels.
                                    metadata = {
                                        apiVersion = "kubernetes.external-secrets.io/v1alpha1"
                                        kind = "PushSecretMetadata"
                                        spec.tags = {
                                            "hops.ops.com.ai/apiVersion" = "hops.ops.com.ai/v1alpha1"
                                            "hops.ops.com.ai/authstack" = "ps-defaults"
                                            "hops.ops.com.ai/cluster" = "test-cluster"
                                            "hops.ops.com.ai/kind" = "AuthStack"
                                            "hops.ops.com.ai/managed" = "true"
                                            "hops.ops.com.ai/managed-by" = "pushsecret"
                                            "hops.ops.com.ai/name" = "ps-defaults"
                                            "hops.ops.com.ai/namespace" = "default"
                                            "hops.ops.com.ai/secret" = "true"
                                        }
                                    }
                                }]
                            }
                        }
                        providerConfigRef = {
                            name = "test-cluster"
                            kind = "ProviderConfig"
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 7c: explicit pushCredentials overrides (path + property).
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "pushsecret-explicit-path-and-property"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "ps-explicit"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    externalSecrets = {
                        enabled = True
                        secretPath = "test/zitadel"
                        pushCredentials = {
                            enabled = True
                            path = "team-a/zitadel/iam-admin-credentials"
                            accessTokenProperty = "pat"
                        }
                    }
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "ps-explicit-credentials-pushsecret"
                    spec.forProvider.manifest.spec.data = [{
                        match = {
                            secretKey = "pat"
                            remoteRef = {
                                remoteKey = "team-a/zitadel/iam-admin-credentials"
                                property = "pat"
                            }
                        }
                    }]
                }
            ]
        }
    }

    # ==========================================================================
    # Test 7d: pushCredentials.enabled=false explicitly disables PushSecret
    # even when externalSecrets.enabled=true.
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "pushsecret-explicitly-disabled"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "ps-off"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    externalSecrets = {
                        enabled = True
                        secretPath = "test/zitadel"
                        pushCredentials.enabled = False
                    }
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                }
            }
            assertResources = [
                # ExternalSecret for masterkey still composed (externalSecrets.enabled),
                # but no credentials-pushsecret Object.
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "ps-off-external-secret-masterkey"
                }
            ]
        }
    }

    # ==========================================================================
    # Test 6: FirstInstance username override flows into chart values
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "first-instance-username-override"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "fi-auth"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance = {
                        org = "hops-ops"
                        masterkey.secretRef.name = "zitadel-masterkey"
                        iamAdmin.username = "platform-admin"
                    }
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "fi-auth-zitadel"
                    spec.forProvider.values.zitadel.configmapConfig.FirstInstance = {
                        Skip = False
                        Org.Name = "hops-ops"
                        Machine = {
                            Machine = {
                                Username = "platform-admin"
                                Name = "Automatically Initialized IAM Admin"
                            }
                            MachineKey.ExpirationDate = "2029-01-01T00:00:00Z"
                            Pat.ExpirationDate = "2029-01-01T00:00:00Z"
                        }
                        LoginClient = {
                            Machine.Username = "login-client"
                            Pat.ExpirationDate = "2029-01-01T00:00:00Z"
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 14: spec.smtp wires the SMTPSender consumer chain
    #
    # Given an observed SMTPSender (host/port/username + DKIM verified) and a
    # Ready Zitadel release, spec.smtp.enabled composes the SES password
    # ExternalSecret (whole-secret pull, NO property), the iam-admin PAT ->
    # credentials ExternalSecret (push auto-enabled), the zitadel SMTP
    # ProviderConfig, and the zitadel SMTP Config MR (host:port from observed).
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "smtp-wires-smtpsender-consumer-chain"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "smtp-auth"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance = {
                        org = "hops-ops"
                        iamAdmin.username = "platform-admin"
                        masterkey.secretRef.name = "zitadel-masterkey"
                    }
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                    smtp = {
                        enabled = True
                        smtpSenderRef.name = "ops"
                        fromAddress = "no-reply@auth.example.com"
                        fromName = "Hops Ops"
                        replyToAddress = "support@auth.example.com"
                    }
                }
            }
            observedResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "smtp-auth-observed-smtp-sender"
                    metadata.annotations = {
                        "crossplane.io/composition-resource-name" = "observed-smtp-sender"
                    }
                    status.atProvider.manifest = {
                        apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                        kind = "SMTPSender"
                        metadata.name = "ops"
                        status = {
                            smtp = {
                                host = "email-smtp.us-east-2.amazonaws.com"
                                port = 587
                                username = "AKIAIOSFODNN7EXAMPLE"
                                awsSecretsManagerPath = "push/test-cluster/ops-smtp"
                            }
                            dkim.verified = True
                        }
                    }
                }
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "smtp-auth-zitadel"
                    metadata.annotations = {
                        "crossplane.io/composition-resource-name" = "helm-release-zitadel"
                    }
                    status.conditions = _ready_conditions
                }
            ]
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "smtp-auth-external-secret-smtp-password"
                    spec.forProvider.manifest = {
                        apiVersion = "external-secrets.io/v1"
                        kind = "ExternalSecret"
                        metadata.name = "zitadel-smtp"
                        # Whole-secret pull: remoteRef has key but NO property.
                        spec.data = [{
                            secretKey = "smtp-password"
                            remoteRef.key = "push/test-cluster/ops-smtp"
                        }]
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "smtp-auth-zitadel-smtp-credentials"
                    spec.forProvider.manifest = {
                        apiVersion = "external-secrets.io/v1"
                        kind = "ExternalSecret"
                        metadata.name = "zitadel-smtp-credentials"
                        spec.data = [{
                            secretKey = "access_token"
                            remoteRef = {key = "push/test-cluster/zitadel-credentials", property = "access_token"}
                        }]
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "smtp-auth-zitadel-smtp-providerconfig"
                    spec.forProvider.manifest = {
                        apiVersion = "zitadel.m.crossplane.io/v1beta1"
                        kind = "ProviderConfig"
                        metadata.name = "smtp-auth-smtp"
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "smtp-auth-zitadel-smtp-config"
                    spec.forProvider.manifest = {
                        apiVersion = "smtp.zitadel.m.crossplane.io/v1alpha1"
                        kind = "Config"
                        spec.forProvider = {
                            host = "email-smtp.us-east-2.amazonaws.com:587"
                            user = "AKIAIOSFODNN7EXAMPLE"
                            senderAddress = "no-reply@auth.example.com"
                            senderName = "Hops Ops"
                            replyToAddress = "support@auth.example.com"
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 15: SMTP durable resources render on intent alone (no observed yet)
    #
    # The password ES, credentials ES, and ProviderConfig gate on stable user
    # intent (smtp.enabled + smtpSenderRef.name), NOT on observed state, so they
    # render even before the SMTPSender is observed and therefore cannot vanish
    # on a transient Observe miss (destructive-omit guard). The Config MR (180)
    # gates on $smtp.render and so stays absent until the secret path is observed
    # (proven present in Test 14).
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "smtp-durable-resources-render-without-observed"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "hops.ops.com.ai/v1alpha1"
                kind = "AuthStack"
                metadata.name = "smtp-noobs"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance = {
                        org = "hops-ops"
                        iamAdmin.username = "platform-admin"
                        masterkey.secretRef.name = "zitadel-masterkey"
                    }
                    database.external.dsnSecretRef = {
                        name = "zitadel-db"
                        key = "dsn"
                    }
                    smtp = {
                        enabled = True
                        smtpSenderRef.name = "ops"
                        fromAddress = "no-reply@auth.example.com"
                    }
                }
            }
            # Deliberately NO observedResources: the SMTPSender is not yet observed.
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "smtp-noobs-external-secret-smtp-password"
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "smtp-noobs-zitadel-smtp-credentials"
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "smtp-noobs-zitadel-smtp-providerconfig"
                }
            ]
        }
    }
]

items = _items
