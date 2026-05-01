# openshift-sscsi-vault

![Version: 0.0.14](https://img.shields.io/badge/Version-0.0.14-informational?style=flat-square)

Helm chart (library-style) for Vault Secrets Store CSI on OpenShift: hub Vault URL, Kubernetes auth mount/role parity with openshift-external-secrets-chart patterns, and workload RBAC. Consuming charts should render named templates via include (see README); optional bundled manifests are off by default.

This chart is used by the Validated Patterns to configure SSCSI

### Consuming as a library (any parent chart)

Merge your values into the same shape as this chart’s `values.yaml` (`ocpSecretsStoreCsiVault`, `global`, `clusterGroup`), then build a subchart-style context and render **in this order** (same `$vaultCtx` for all `include` calls):

```yaml
{{- $vaultCtx := dict "Chart" $sc.Chart "Capabilities" $sc.Capabilities "Release" $sc.Release "Values" $vaultVals }}
{{- include "openshift_sscsi_vault.renderSyncCaConfigMap" $vaultCtx }}
{{- include "openshift_sscsi_vault.secretproviderclass" $vaultCtx }}
---
{{- include "openshift_sscsi_vault.workload_rbac" $vaultCtx }}

```

Named templates:

- **`openshift_sscsi_vault.vaultTlsCaPemFromCluster`** — PEM for the synced bundle: **`syncProviderCaConfigMap.pemLiteral`** first (Argo CD / `helm template` safe), else optional **`useLookup: true`** cluster copy (ESO-style hub/spoke presets; hub ingress `router-ca` / `router-ca-certs` plus optional `kube-root-ca.crt` concat). Default **`useLookup: false`** because Argo renders manifests without a live API.
- **`openshift_sscsi_vault.syncVaultCsiTlsCaConfigMapYaml`** — ConfigMap manifest when sync is enabled, **`createConfigMap`** is true, and PEM is non-empty.
- **`openshift_sscsi_vault.renderSyncCaConfigMap`** — ConfigMap + trailing `---` when non-empty (convenience).
- **`openshift_sscsi_vault.secretproviderclass`** — SPC; when sync is enabled, sets **`vaultCACertPath`** under **`mountDir`/`keyInConfigMap`** if PEM is present **or** if **`createConfigMap: false`** (you supply the ConfigMap and mount separately).

Mount the synced (or pre-provisioned) ConfigMap on the **Vault CSI provider** DaemonSet at **`caProvider.syncProviderCaConfigMap.mountDir`** (HashiCorp Vault chart **`csi.volumes`** / **`csi.volumeMounts`**; Validated Patterns often use **`extraValueFiles`** — see aap-starter-kit **`overrides/values-vault-csi-tls-ca.yaml`**).

### Argo CD and TLS CA material

Argo CD (and plain **`helm template`**) runs **client-side**: **`helm lookup()`** does not see the cluster API. By default **`createConfigMap: false`** and **`syncProviderCaConfigMap.enabled: true`**: the SecretProviderClass points at **`mountDir`/`keyInConfigMap`** so the Vault CSI provider reads the same PEM that **rhvp.cluster_utils** (`vault_ss_csi_*` tasks during the vault playbook) creates as **`openshift-sscsi-vault-vault-tls-ca`** — mount that ConfigMap on the HashiCorp Vault CSI DaemonSet (see aap-starter-kit **`overrides/values-vault-csi-tls-ca.yaml`**). Alternatively set **`pemLiteral`** (SOPS / parameters), or **`createConfigMap: true`** with **`useLookup: true`** for cluster-side Helm only.

### Notable changes

* v0.0.2: Initial release
* v0.0.3: Provide default CAs to avoid skipping TLS verify
* v0.0.9: Normalize `vaultSkipTLSVerify` to `"true"`/`"false"` strings for HashiCorp vault-csi-provider (`strconv.ParseBool`)
* v0.0.11: Handle injection of CA material
* v0.0.12: CA sync via optional `lookup` (`caProvider.syncProviderCaConfigMap`), `renderSyncCaConfigMap`, hub ingress CA fallbacks; parent charts use includes only
* v0.0.13: Argo-safe TLS CA — `pemLiteral`, `useLookup` (default false), `createConfigMap`; `vaultCACertPath` when PEM is supplied or the ConfigMap is managed out-of-band
* v0.0.14: Default **`syncProviderCaConfigMap.enabled: true`**, **`createConfigMap: false`**, and **`vaultSkipTLSVerify: "false"`** so strict TLS targets the ConfigMap name/key that **rhvp.cluster_utils** provisions; set **`syncProviderCaConfigMap.enabled: false`** to fall back to hub/spoke **`defaultVaultCACertPath`** only

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| clusterGroup.applications | object | `{}` |  |
| global | object | `{"clusterDomain":"foo.example.com","hubClusterDomain":"hub.example.com","localClusterDomain":""}` | Global values aligned with openshift-external-secrets chart patterns |
| ocpSecretsStoreCsiVault | object | see nested keys | Settings for SecretProviderClass + workload ServiceAccount used with Vault CSI |
| ocpSecretsStoreCsiVault.caProvider | object | `{"clientCluster":{"defaultVaultCACertPath":"/etc/pki/vault-ca/hub-kube-root-ca.crt","key":"hub-kube-root-ca.crt","name":"hub-ca","namespace":"external-secrets","type":"Secret"},"enabled":true,"hostCluster":{"defaultVaultCACertPath":"/etc/pki/vault-ca/kube-root-ca.crt","key":"ca.crt","name":"kube-root-ca.crt","namespace":"external-secrets","type":"ConfigMap"},"syncProviderCaConfigMap":{"configMapName":"openshift-sscsi-vault-vault-tls-ca","createConfigMap":false,"enabled":true,"ingressRouterCa":{"key":"ca-bundle.crt","name":"router-ca","namespace":"openshift-ingress"},"keyInConfigMap":"vault-tls-ca.pem","mountDir":"/etc/pki/vault-ca","pemLiteral":"","preset":"auto","targetNamespace":"vault","useLookup":false}}` | Mirrors openshift-external-secrets-chart `ocpExternalSecrets.caProvider`: when enabled and `tls.vaultCACertPath` is empty, `vaultCACertPath` is chosen from `syncProviderCaConfigMap` (default: path to Ansible-managed CM) or else hub/spoke `defaultVaultCACertPath` when sync is disabled. CSI reads a PEM path on the Vault CSI provider pod. Nested: `syncProviderCaConfigMap`, `hostCluster`, `clientCluster`. |
| ocpSecretsStoreCsiVault.caProvider.enabled | bool | `true` | When false, `vaultCACertPath` is omitted unless `tls.vaultCACertPath` is set (same idea as ESO omitting `caProvider` when disabled). |
| ocpSecretsStoreCsiVault.caProvider.hostCluster.defaultVaultCACertPath | string | `"/etc/pki/vault-ca/kube-root-ca.crt"` | PEM path on the Vault CSI provider when hub-style auth (hub cluster or spoke with hashicorp-vault app) |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap | object | `{"configMapName":"openshift-sscsi-vault-vault-tls-ca","createConfigMap":false,"enabled":true,"ingressRouterCa":{"key":"ca-bundle.crt","name":"router-ca","namespace":"openshift-ingress"},"keyInConfigMap":"vault-tls-ca.pem","mountDir":"/etc/pki/vault-ca","pemLiteral":"","preset":"auto","targetNamespace":"vault","useLookup":false}` | TLS CA for Vault HTTPS when `tls.vaultSkipTLSVerify` is `"false"`: default expects ConfigMap `configMapName` mounted at `mountDir` (created by **rhvp.cluster_utils** vault playbook / `vault_ss_csi_*` tasks, or set `pemLiteral` / `createConfigMap`+`useLookup` instead). See chart README. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.configMapName | string | `"openshift-sscsi-vault-vault-tls-ca"` | ConfigMap name; must match **rhvp.cluster_utils** `vault_ss_csi_route_ca_configmap_name` default (`openshift-sscsi-vault-vault-tls-ca`). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.createConfigMap | bool | `false` | When false (default), this chart does not create the ConfigMap — **rhvp.cluster_utils** creates `configMapName` in `vault` and workload namespaces. SPC still gets `vaultCACertPath` at `mountDir`/`keyInConfigMap`. Set true to let Helm emit the CM when `pemLiteral` is set or `useLookup` returns PEM. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.enabled | bool | `true` | When true with `tls.vaultCACertPath` empty, set SPC `vaultCACertPath` to `mountDir`/`keyInConfigMap` (trust bundle on the Vault CSI provider pod). When `createConfigMap` is true and PEM is available, also render a ConfigMap manifest. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.ingressRouterCa | object | `{"key":"ca-bundle.crt","name":"router-ca","namespace":"openshift-ingress"}` | Router CA ConfigMap reference when preset resolves to ingress router CA (`useLookup` path). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.keyInConfigMap | string | `"vault-tls-ca.pem"` | Key within the ConfigMap whose value is the PEM file; must match **rhvp.cluster_utils** `vault_ss_csi_route_ca_configmap_key` default (`vault-tls-ca.pem`). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.mountDir | string | `"/etc/pki/vault-ca"` | Directory on the Vault CSI provider pod where the ConfigMap is mounted (must match HashiCorp Vault chart `csi.volumeMounts`). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.pemLiteral | string | `""` | Inline PEM (full bundle). GitOps-friendly: SOPS-encrypted values, Argo CD helm parameters, or a pattern override file. When set, used instead of cluster lookup for CM content when `createConfigMap` is true. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.preset | string | `"auto"` | Preset for `useLookup` only: `auto` (hub vs spoke), `ingressrouterca`, `esohubkuberootca`, `esospokehubca`. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.targetNamespace | string | `"vault"` | Namespace for the synced ConfigMap when `createConfigMap` is true (Vault CSI provider namespace in typical patterns). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.useLookup | bool | `false` | When true, use helm lookup() against the live API (hub ingress CA, ESO-style hub-ca, etc.). False by default because Argo CD client-side render has no API. |
| ocpSecretsStoreCsiVault.objects | list | example placeholder; replace with your paths | KV objects to expose as files under the CSI mount (Vault CSI `objects` list) |
| ocpSecretsStoreCsiVault.rbac.rolename | string | `"hub-role"` | Vault Kubernetes auth role name when running on the hub (or when local Vault is used) |
| ocpSecretsStoreCsiVault.rbac.serviceAccount.create | bool | `true` | If false, only ClusterRoleBinding is rendered; use an existing SA (e.g. parent chart workload SA) |
| ocpSecretsStoreCsiVault.rbac.serviceAccount.name | string | `"ocp-sscsi-vault"` | ServiceAccount pods must use so Vault role bindings match |
| ocpSecretsStoreCsiVault.rbac.serviceAccount.namespace | string | `"openshift-sscsi-vault-demo"` | Namespace for SA, token Secret, SecretProviderClass, and typical workloads |
| ocpSecretsStoreCsiVault.secretObjects | list | `[]` | Optional: sync mounted objects into native Kubernetes Secrets (CSI secretObjects) |
| ocpSecretsStoreCsiVault.secretProviderClass.enabled | bool | `true` | Create the SecretProviderClass (used by named template and by installDefaultManifests) |
| ocpSecretsStoreCsiVault.secretProviderClass.installDefaultManifests | bool | `false` | When true, render SecretProviderClass + RBAC from this chart's templates (standalone install). Consuming charts typically set this false and use `include` on the named templates instead. |
| ocpSecretsStoreCsiVault.secretProviderClass.name | string | `"vault-hub-secrets"` | metadata.name of the SecretProviderClass (referenced from pod volumeAttributes) |
| ocpSecretsStoreCsiVault.tls | object | `{"vaultCACertPath":"","vaultSkipTLSVerify":"false","vaultTLSServerName":""}` | TLS options for the Vault CSI provider (see HashiCorp vault-csi-provider docs). When `vaultSkipTLSVerify` is `"true"`, `vaultCACertPath` is not emitted (verify is off). |
| ocpSecretsStoreCsiVault.tls.vaultCACertPath | string | `""` | If set, passed as vaultCACertPath (must exist where the CSI provider can read it). When empty and `caProvider.enabled`, uses `syncProviderCaConfigMap` mount path when sync is enabled, else hub/spoke `defaultVaultCACertPath`. |
| ocpSecretsStoreCsiVault.tls.vaultSkipTLSVerify | string | `"false"` | Pass through to the vault-csi-provider as `vaultSkipTLSVerify` (`"true"` / `"false"` strings). |
| ocpSecretsStoreCsiVault.tls.vaultTLSServerName | string | `""` | Optional SNI override for Vault HTTPS (`vaultTLSServerName` in the SPC). |
| ocpSecretsStoreCsiVault.vault.externalAddress | string | `""` | If non-empty, used as spec.parameters.vaultAddress (e.g. https://vault.example.com for an external Vault). When empty, the default hub route https://vault-vault.<global.hubClusterDomain> is used. |
| ocpSecretsStoreCsiVault.vault.hubMountPath | string | `"hub"` | Vault Kubernetes auth mount path on the hub (Validated Patterns default) |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)

