import models.ai.com.ops.hops.v1alpha1 as stacksv1alpha1
import models.io.upbound.dev.meta.v1alpha1 as metav1alpha1

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
            xr = stacksv1alpha1.AuthStack {
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
                    spec.forProvider.values.zitadel.masterkeySecretName = "zitadel-masterkey"
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
            xr = stacksv1alpha1.AuthStack {
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
            xr = stacksv1alpha1.AuthStack {
                metadata.name = "pg-auth"
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
    # Test 3c: AdminPassword + iamAdminPat + loginClientPat external secrets
    # compose ExternalSecret resources. Reconciler CronJob is rendered when
    # adminPassword.secretPath is set (default-on).
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "reconciler-pattern-composes-eso-pushsecret-cronjob"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.AuthStack {
                metadata.name = "rec-auth"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.psqlClusterRef.name = "zitadel-pg"
                    externalSecrets = {
                        enabled = True
                        masterkey.secretPath = "test/zitadel/masterkey"
                        adminPassword.secretPath = "test/zitadel/admin-password"
                        iamAdminPat.secretPath = "test/zitadel/iam-admin-pat"
                        loginClientPat.secretPath = "test/zitadel/login-client"
                    }
                }
            }
            assertResources = [
                # ExternalSecret for admin password
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "rec-auth-external-secret-admin-password"
                    spec.forProvider.manifest = {
                        apiVersion = "external-secrets.io/v1"
                        kind = "ExternalSecret"
                        metadata.name = "zitadel-admin-password"
                        spec = {
                            target.creationPolicy = "Owner"
                            data = [{
                                secretKey = "password"
                                remoteRef = {key = "test/zitadel/admin-password", property = "password"}
                            }]
                        }
                    }
                }
                # PushSecret for iam-admin PAT
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "rec-auth-push-secret-iam-admin-pat"
                    spec.forProvider.manifest = {
                        apiVersion = "external-secrets.io/v1alpha1"
                        kind = "PushSecret"
                        metadata.name = "iam-admin-pat"
                        spec = {
                            updatePolicy = "Replace"
                            selector.secret.name = "iam-admin-pat"
                        }
                    }
                }
                # Reconciler CronJob
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "rec-auth-reconciler-cronjob"
                    spec.forProvider.manifest = {
                        apiVersion = "batch/v1"
                        kind = "CronJob"
                        metadata.name = "rec-auth-reconciler"
                        spec = {
                            schedule = "*/5 * * * *"
                            concurrencyPolicy = "Forbid"
                        }
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 3d: When reconciler is on, FirstInstance.Machine.Pat and
    # FirstInstance.LoginClient.Pat are NOT set (we own the PAT lifecycle).
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "reconciler-disables-chart-pat-sidecars"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.AuthStack {
                metadata.name = "no-sidecar-auth"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    firstInstance.masterkey.secretRef.name = "zitadel-masterkey"
                    database.psqlClusterRef.name = "zitadel-pg"
                    externalSecrets = {
                        enabled = True
                        adminPassword.secretPath = "test/zitadel/admin-password"
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "helm.m.crossplane.io/v1beta1"
                    kind = "Release"
                    metadata.name = "no-sidecar-auth-zitadel"
                    # Machine and LoginClient blocks present (Username +
                    # Name) but no Pat sub-block — we mint via reconciler.
                    spec.forProvider.values.zitadel.configmapConfig.FirstInstance = {
                        Machine.Machine.Username = "iam-admin"
                        LoginClient.Machine.Username = "login-client"
                    }
                }
            ]
        }
    }

    # ==========================================================================
    # Test 3b: externalSecrets composes ExternalSecret for masterkey
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "external-secrets-masterkey-composes-eso"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.AuthStack {
                metadata.name = "eso-auth"
                spec = {
                    clusterName = "test-cluster"
                    domain = "auth.example.com"
                    externalSecrets = {
                        enabled = True
                        masterkey.secretPath = "zitadel/masterkey"
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
                        spec = {
                            secretStoreRef = {
                                name = "hops-aws-secrets-manager"
                                kind = "ClusterSecretStore"
                            }
                            target.name = "zitadel-masterkey"
                            data = [{
                                secretKey = "masterkey"
                                remoteRef = {key = "zitadel/masterkey", property = "masterkey"}
                            }]
                        }
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
            xr = stacksv1alpha1.AuthStack {
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
            xr = stacksv1alpha1.AuthStack {
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
            xr = stacksv1alpha1.AuthStack {
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
    # Test 6: FirstInstance username override flows into chart values
    # ==========================================================================
    metav1alpha1.CompositionTest {
        metadata.name = "first-instance-username-override"
        spec = {
            compositionPath = "apis/authstacks/composition.yaml"
            xrdPath = "apis/authstacks/definition.yaml"
            timeoutSeconds = 60
            validate = False
            xr = stacksv1alpha1.AuthStack {
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
]

items = _items
