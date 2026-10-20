import models.io.upbound.dev.meta.v1alpha1 as meta

# Typed subject resolution is the composition's value; other identity lifecycle
# belongs to native resources and the owning application environment.
_subjects = ["HumanUser", "MachineUser"]
items = [meta.CompositionTest {
    metadata.name = "authorization-resolves-" + subject.lower()
    spec = {
        compositionPath = "apis/authorizations/composition.yaml"
        xrdPath = "apis/authorizations/definition.yaml"
        timeoutSeconds = 90
        validate = False
        xr = {
            apiVersion = "auth.hops.ops.com.ai/v1alpha1"
            kind = "Authorization"
            metadata = {name = "reader", namespace = "app"}
            spec = {
                subjectRef = {name = "person", kind = subject}
                projectRef = {name = "project"}
                organizationRef = {name = "tenant"}
                roles = ["reader"]
                providerConfigRef = {name = "zitadel", kind = "ProviderConfig"}
            }
        }
        extraResources = [
            {
                apiVersion = "user.zitadel.m.crossplane.io/v1alpha1"
                kind = subject
                metadata = {name = "person", namespace = "app"}
                status.atProvider.id = "user-id"
            },
            {
                apiVersion = "project.zitadel.m.crossplane.io/v1alpha1"
                kind = "ProjectV2"
                metadata = {name = "project", namespace = "app"}
                status.atProvider = {id = "project-id", orgId = "org-id"}
            },
            {
                apiVersion = "org.zitadel.m.crossplane.io/v1alpha1"
                kind = "Organization"
                metadata = {name = "tenant", namespace = "app"}
                status.atProvider.id = "org-id"
            }
        ]
        assertResources = [{
            apiVersion = "authorization.zitadel.m.crossplane.io/v1alpha1"
            kind = "Authorization"
            metadata.name = "reader-authorization"
            spec.forProvider = {userId = "user-id", projectId = "project-id", orgId = "org-id", roleKeys = ["reader"]}
        }]
    }
} for subject in _subjects]
