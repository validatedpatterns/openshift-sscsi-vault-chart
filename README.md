# openshift-sscsi-vault

![Version: 0.2.0](https://img.shields.io/badge/Version-0.2.0-informational?style=flat-square)

OpenShift Vault Secrets Store CSI: optional synced TLS trust ConfigMap for the provider, HashiCorp Vault CSI provider DaemonSet (hub or spoke), projected trust mount, and OpenShift SCC wiring. Per-application SecretProviderClass manifests use the vp-sscsi-spc library chart.

This chart is used by the Validated Patterns to configure cluster-wide Vault CSI support.

### Scope and chart split

This chart owns **cluster-wide Vault SSCSI infrastructure** on OpenShift:

- Optional synced TLS trust **`ConfigMap`** for the provider (`caProvider.syncProviderCaConfigMap`) and named-template helpers (`vaultTlsCaPemFromCluster`, `renderSyncCaConfigMap`, and related).
- **Vault CSI provider** DaemonSet and upstream CSI RBAC via the bundled **HashiCorp `vault` Helm subchart** (`vault` values), when **`ocpSecretsStoreCsiVault.vaultCsiProvider.enabled`** is **true** (default).
- **Projected trust volume** on the provider pods (`vault.csi.volumes` / `volumeMounts`), defaulting to the same **`ConfigMap`** name as **`caProvider.syncProviderCaConfigMap.configMapName`** so the bundle this chart manages is mounted at **`/etc/pki/vault-ca`**.
- **`privileged` SCC** `RoleBinding` for the provider ServiceAccount on OpenShift when **`vaultCsiProvider.openshiftPrivilegedSCCRoleBinding.enabled`** is **true** (default).

It does **not** run the Vault **server** by default (`vault.server.enabled: false`). Enable server-related values only when you intentionally colocate a server with this release.

**Per-application** `SecretProviderClass` objects stay in the **`vp-sscsi-spc`** library (**per app**, with **`applicationKey`** / **`ssCsiWorkloadAuth`** on Validated Patterns where used).

### Cluster-wide usage

Install this chart as the single owner of provider trust material:

```yaml
ocpSecretsStoreCsiVault:
  clusterWide:
    installDefaultManifests: true
```

Set `installDefaultManifests: false` when reusing only named templates.

Set **`ocpSecretsStoreCsiVault.vaultCsiProvider.enabled: false`** only if you want trust **`ConfigMap`** templates without installing the Vault CSI provider from this chart (unusual for new installs).

### Hub, spoke, and clusters without a local Vault server

**Trust `ConfigMap`** is still **cluster-local** (CNO-injected bundle, PEM, or lookup modes as before). **Vault CSI provider** pods in this release read that material via **`vault.csi`** volume projection.

**Where it runs**

- Install on **each** cluster (hub and relevant spokes) that runs the Vault CSI **provider** for SSCSI workloads.
- Spokes without a local Vault **server** must set **`vault.global.externalVaultAddr`** to the reachable hub Vault URL (for example **`https://vault-vault.apps.<hubClusterDomain>`**, consistent with **openshift-external-secrets** `ClusterSecretStore` when **`vault.externalAddress`** is empty). Derive this in **clustergroup** values so spokes do not hand-maintain a separate file.

**Helm release namespace and the trust ConfigMap**

- The synced trust **`ConfigMap`** is created in **`caProvider.syncProviderCaConfigMap.targetNamespace`** (default **`vault`**).
- With **`vaultCsiProvider.enabled: true`** (default), the **HashiCorp `vault` subchart** deploys the CSI **DaemonSet into the Helm release namespace**. Projected `ConfigMap` volumes **cannot** reference another namespace, so **install this Application into `vault`** (or set **`targetNamespace`** and **`vault.csi.volumes`** / names together so the `ConfigMap` and DaemonSet share one namespace).
- Legacy layouts that applied only the **`ConfigMap`** from a **config** namespace while the provider lived elsewhere should either **move this Application to `vault`** or disable **`vaultCsiProvider`** here and manage the provider separately.

**Validated Patterns**

- Hub and spoke: add **`clusterGroup.applications`** and overrides; merge **`vault.global.externalVaultAddr`** for spokes from **`global.hubClusterDomain`** (or equivalent) in clustergroup.

### Validated Patterns clustergroup application

Declare this chart under `clusterGroup.applications` in your pattern cluster values (for example `values-hub.yaml`). The clustergroup chart renders an Argo CD `Application` per entry.

**1. Chart published in the pattern Helm repo (multi-source)**

```yaml
clusterGroup:
  namespaces:
    vault: {}
  argoProjects:
    - hub
  applications:
    openshift-sscsi-vault:
      name: openshift-sscsi-vault-cluster
      namespace: vault
      argoProject: hub
      chart: openshift-sscsi-vault
      chartVersion: 0.2.*
      extraValueFiles:
        - $patternref/overrides/values-openshift-sscsi-vault-cluster.yaml
      ignoreDifferences:
        - group: ""
          kind: ConfigMap
          name: openshift-sscsi-vault-vault-tls-ca
          namespace: vault
          jsonPointers:
            - /data
          jqPathExpressions:
            - .data
```

Use **`namespace: vault`** so the bundled CSI provider can project the trust `ConfigMap` rendered into **`vault`**. Adjust `name`, `argoProject`, and overrides to your pattern. The `ignoreDifferences` block matches the default CNO-injected trust `ConfigMap` when you use `injectTrustedCabundle`.

**2. Chart in its own Git repository (multi-source)**

```yaml
clusterGroup:
  applications:
    openshift-sscsi-vault:
      name: openshift-sscsi-vault-cluster
      namespace: vault
      argoProject: hub
      repoURL: https://github.com/yourorg/openshift-sscsi-vault-chart.git
      path: "."
      chartVersion: main
      extraValueFiles:
        - $patternref/overrides/values-openshift-sscsi-vault-cluster.yaml
```

Ensure **`vault`** (or your chosen release namespace) exists under `clusterGroup.namespaces` and the Argo `AppProject` is listed under `clusterGroup.argoProjects`.

### Named templates

- **`openshift_sscsi_vault.syncProviderVaultCACertPath`** — single filesystem path for the CA PEM the **SecretProviderClass** should use (`vaultCACertPath`) when trust is mounted by this chart: **`mountDir`/`trustedCabundleDataKey`** if **`injectTrustedCabundle`** is true (CNO cluster/proxy bundle), else **`mountDir`/`keyInConfigMap`**. Parent charts that render SPCs outside **vp-sscsi-spc** can `include` this helper so paths stay aligned with **`syncProviderCaConfigMap`**.
- **`openshift_sscsi_vault.vaultTlsCaPemFromCluster`** — PEM for the synced bundle: **`syncProviderCaConfigMap.pemLiteral`** first (Argo CD / `helm template` safe), else optional **`useLookup: true`** cluster copy (ESO-style hub/spoke presets; hub ingress `router-ca` / `router-ca-certs` plus optional `kube-root-ca.crt` concat). Default **`useLookup: false`** because Argo renders manifests without a live API.
- **`openshift_sscsi_vault.syncVaultCsiTlsCaConfigMapYaml`** — ConfigMap manifest when sync is enabled, **`createConfigMap`** is true, and either PEM from **`vaultTlsCaPemFromCluster`** is non-empty **or** **`syncProviderCaConfigMap.injectTrustedCabundle`** is true (OpenShift `config.openshift.io/inject-trusted-cabundle` label; CNO fills **`trustedCabundleDataKey`**, default **`ca-bundle.crt`**).
- **`openshift_sscsi_vault.renderSyncCaConfigMap`** — ConfigMap + trailing `---` when non-empty (convenience).

With **`vaultCsiProvider.enabled: true`**, this chart sets **`vault.csi.volumes`** / **`volumeMounts`** to project the default trust **`ConfigMap`** at **`/etc/pki/vault-ca`**. Override **`vault.csi`** if you use a different bundle name or proxy-only **`ConfigMap`** layout; keep names aligned with **`caProvider.syncProviderCaConfigMap`**.

### Namespaces

The trust **`ConfigMap`** is created in **`caProvider.syncProviderCaConfigMap.targetNamespace`**. The CSI **DaemonSet** uses the **Helm release namespace**; for the default projected volume to work, those must match (see **Helm release namespace and the trust ConfigMap** above).

### Argo CD and TLS CA material

Argo CD (and plain **`helm template`**) runs **client-side**: **`helm lookup()`** does not see the cluster API. By default **`syncProviderCaConfigMap.enabled: true`**, **`createConfigMap: true`**, and **`injectTrustedCabundle: true`**: the chart renders a **`ConfigMap`** labeled **`config.openshift.io/inject-trusted-cabundle: "true"`** (empty **`data`** until the Cluster Network Operator fills **`trustedCabundleDataKey`**, default **`ca-bundle.crt`**). The ConfigMap includes **`argocd.argoproj.io/ignore-differences`** as a small **YAML** document with **`jsonPointers`** (`/data`) and **`jqPathExpressions`** (`.data`) so drift tooling ignores the CNO-managed trust bundle map. Disable with **`argocdIgnoreInjectedTrustedCabundleData: false`**. If your Argo / OpenShift GitOps build does not honor per-resource ignore rules, duplicate both entries under the **Application** **`spec.ignoreDifferences`** for that **`ConfigMap`** and use sync option **`RespectIgnoreDifferences=true`**. Mount only that key on the Vault CSI DaemonSet with a **`projected`** volume (**`configMap.items`** + **`optional: true`**) so the pod tolerates the key appearing after CNO injection. For the previous **rhvp.cluster_utils** flow (Ansible creates **`vault-tls-ca.pem`**), set **`injectTrustedCabundle: false`**, **`createConfigMap: false`**, and avoid duplicate applies for the same **`configMapName`**. Alternatively set **`pemLiteral`** or **`createConfigMap: true`** with **`useLookup: true`** for cluster-side Helm only.

### Notable changes

* v0.0.2: Initial release
* v0.0.3: Provide default CAs to avoid skipping TLS verify
* v0.0.9: Normalize `vaultSkipTLSVerify` to `"true"`/`"false"` strings for HashiCorp vault-csi-provider (`strconv.ParseBool`)
* v0.0.11: Handle injection of CA material
* v0.0.12: CA sync via optional `lookup` (`caProvider.syncProviderCaConfigMap`), `renderSyncCaConfigMap`, hub ingress CA fallbacks; parent charts use includes only
* v0.0.13: Argo-safe TLS CA - `pemLiteral`, `useLookup` (default false), `createConfigMap`; `vaultCACertPath` when PEM is supplied or the ConfigMap is managed out-of-band
* v0.0.14: Default **`syncProviderCaConfigMap.enabled: true`**, **`createConfigMap: false`**, and **`vaultSkipTLSVerify: "false"`** so strict TLS targets the ConfigMap name/key that **rhvp.cluster_utils** provisions; set **`syncProviderCaConfigMap.enabled: false`** to fall back to hub/spoke **`defaultVaultCACertPath`** only
* v0.0.15: **`injectTrustedCabundle`** defaults to **true** in chart **`values.yaml`** and in named templates when the key is absent or non-boolean (CNO-injected trust bundle aligned with cluster **`Proxy`** / **`trustedCA`**); set **`injectTrustedCabundle: false`** (and typically **`createConfigMap: false`**) for legacy **rhvp.cluster_utils** **`vault-tls-ca.pem`**, **`pemLiteral`**, or **`useLookup`** PEM paths
* v0.0.16: CNO inject **`ConfigMap`** defaults **`argocd.argoproj.io/ignore-differences`** to **`/data/<trustedCabundleDataKey>`** (toggle **`argocdIgnoreInjectedTrustedCabundleData`**); optional **`configMapAnnotations`**
* v0.0.17: **`argocd.argoproj.io/ignore-differences`** now embeds **`jsonPointers`** and **`jqPathExpressions`** for the injected data key (correct jq for keys like **`ca-bundle.crt`**)
* v0.0.18: Default injected trust drift ignore now targets full **`/data`** (**`jqPathExpressions: [.data]`**) to reduce persistent OutOfSync when injected keys vary
* v0.1.0: Split responsibilities by scope: this chart now focuses on cluster-wide Vault CSI trust/config components only; app-level SecretProviderClass rendering moves to a dedicated SPC chart
* v0.2.0: Bundle HashiCorp **`vault`** subchart for Vault **CSI provider**, default projected trust mount aligned with synced **`ConfigMap`**, OpenShift **`privileged`** SCC **RoleBinding**; install release in **`vault`** namespace by default so projection works

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| https://helm.releases.hashicorp.com | vault | 0.32.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| clusterGroup.applications | object | `{}` |  |
| global | object | `{"clusterDomain":"foo.example.com","hubClusterDomain":"hub.example.com","localClusterDomain":""}` | Global values aligned with openshift-external-secrets chart patterns |
| ocpSecretsStoreCsiVault | object | see nested keys | Settings for cluster-wide Vault CSI support components |
| ocpSecretsStoreCsiVault.caProvider | object | `{"clientCluster":{"defaultVaultCACertPath":"/etc/pki/vault-ca/hub-kube-root-ca.crt","key":"hub-kube-root-ca.crt","name":"hub-ca","namespace":"external-secrets","type":"Secret"},"enabled":true,"hostCluster":{"defaultVaultCACertPath":"/etc/pki/vault-ca/kube-root-ca.crt","key":"ca.crt","name":"kube-root-ca.crt","namespace":"external-secrets","type":"ConfigMap"},"syncProviderCaConfigMap":{"argocdIgnoreInjectedTrustedCabundleData":true,"configMapAnnotations":{},"configMapName":"openshift-sscsi-vault-vault-tls-ca","createConfigMap":true,"enabled":true,"ingressRouterCa":{"key":"ca-bundle.crt","name":"router-ca","namespace":"openshift-ingress"},"injectTrustedCabundle":true,"keyInConfigMap":"vault-tls-ca.pem","mountDir":"/etc/pki/vault-ca","pemLiteral":"","preset":"auto","targetNamespace":"vault","trustedCabundleDataKey":"ca-bundle.crt","useLookup":false}}` | Provider trust-bundle sourcing for Vault CSI. Supports CNO injected trust, inline PEM, or optional cluster lookup-based copy flows for hub/spoke patterns. Nested: `syncProviderCaConfigMap`, `hostCluster`, `clientCluster`. |
| ocpSecretsStoreCsiVault.caProvider.enabled | bool | `true` | Enables CA source resolution helpers and optional synced ConfigMap rendering. |
| ocpSecretsStoreCsiVault.caProvider.hostCluster.defaultVaultCACertPath | string | `"/etc/pki/vault-ca/kube-root-ca.crt"` | Default CA bundle path convention for hub-style deployments. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap | object | `{"argocdIgnoreInjectedTrustedCabundleData":true,"configMapAnnotations":{},"configMapName":"openshift-sscsi-vault-vault-tls-ca","createConfigMap":true,"enabled":true,"ingressRouterCa":{"key":"ca-bundle.crt","name":"router-ca","namespace":"openshift-ingress"},"injectTrustedCabundle":true,"keyInConfigMap":"vault-tls-ca.pem","mountDir":"/etc/pki/vault-ca","pemLiteral":"","preset":"auto","targetNamespace":"vault","trustedCabundleDataKey":"ca-bundle.crt","useLookup":false}` | Controls generation of the provider-namespace ConfigMap used to mount trust material into Vault CSI provider pods. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.argocdIgnoreInjectedTrustedCabundleData | bool | `true` | When `injectTrustedCabundle` and this chart renders the TLS ConfigMap: set `argocd.argoproj.io/ignore-differences` to a YAML snippet with `jsonPointers` `/data` and `jqPathExpressions` `.data` so Argo ignores CNO-managed bundle content. Honor depends on Argo / OpenShift GitOps version—duplicate under Application `spec.ignoreDifferences` if needed (see README). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.configMapAnnotations | object | `{}` | Extra annotations merged onto the rendered sync TLS ConfigMap (overrides `argocdIgnoreInjectedTrustedCabundleData` annotation keys when the same key is set). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.configMapName | string | `"openshift-sscsi-vault-vault-tls-ca"` | ConfigMap name; must match **rhvp.cluster_utils** `vault_ss_csi_route_ca_configmap_name` default (`openshift-sscsi-vault-vault-tls-ca`). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.createConfigMap | bool | `true` | When true, Helm emits the ConfigMap (injection-labeled or PEM from `pemLiteral`/`useLookup`). When false, GitOps/Ansible must create `configMapName`. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.enabled | bool | `true` | Enables synced trust ConfigMap behavior and template helpers. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.ingressRouterCa | object | `{"key":"ca-bundle.crt","name":"router-ca","namespace":"openshift-ingress"}` | Router CA ConfigMap reference when preset resolves to ingress router CA (`useLookup` path). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.injectTrustedCabundle | bool | `true` | When true with `createConfigMap` true (default), render a ConfigMap with label `config.openshift.io/inject-trusted-cabundle: "true"` and empty `data` so the Cluster Network Operator injects the cluster merged CA bundle. Mutually exclusive with rendered PEM content; set false to use PEM/`lookup` or an out-of-band ConfigMap. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.keyInConfigMap | string | `"vault-tls-ca.pem"` | Key within the ConfigMap whose value is the PEM file; must match **rhvp.cluster_utils** `vault_ss_csi_route_ca_configmap_key` default (`vault-tls-ca.pem`). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.mountDir | string | `"/etc/pki/vault-ca"` | Directory on the Vault CSI provider pod where the ConfigMap is mounted (must match HashiCorp Vault chart `csi.volumeMounts`). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.pemLiteral | string | `""` | Inline PEM (full bundle). GitOps-friendly: SOPS-encrypted values, Argo CD helm parameters, or a pattern override file. When set, used instead of cluster lookup for CM content when `createConfigMap` is true. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.preset | string | `"auto"` | Preset for `useLookup` only: `auto` (hub vs spoke), `ingressrouterca`, `esohubkuberootca`, `esospokehubca`. |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.targetNamespace | string | `"vault"` | Namespace for the synced ConfigMap when `createConfigMap` is true (Vault CSI provider namespace in typical patterns). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.trustedCabundleDataKey | string | `"ca-bundle.crt"` | Data key populated by OpenShift after injection (see "Certificate injection using Operators" / custom PKI docs). |
| ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.useLookup | bool | `false` | When true, use helm lookup() against the live API (hub ingress CA, ESO-style hub-ca, etc.). False by default because Argo CD client-side render has no API. |
| ocpSecretsStoreCsiVault.clusterWide.installDefaultManifests | bool | `true` | When true, install cluster-wide manifests owned by this chart (currently the optional Vault CSI TLS CA sync ConfigMap). |
| ocpSecretsStoreCsiVault.vaultCsiProvider | object | `{"enabled":true,"openshiftPrivilegedSCCRoleBinding":{"enabled":true}}` | HashiCorp Vault Helm subchart: deploys the Vault CSI provider DaemonSet and related RBAC when enabled. Disable if you only render trust `ConfigMap` templates from another release (not recommended for new installs). |
| ocpSecretsStoreCsiVault.vaultCsiProvider.openshiftPrivilegedSCCRoleBinding | object | `{"enabled":true}` | When true with CSI enabled on OpenShift, grant the provider ServiceAccount the `privileged` SCC. |
| vault | object | see nested keys | HashiCorp `vault` subchart (https://github.com/hashicorp/vault-helm). Defaults: CSI provider only (no Vault server), OpenShift paths and UBI images. Keep `csi.volumes` ConfigMap `name` aligned with `ocpSecretsStoreCsiVault.caProvider.syncProviderCaConfigMap.configMapName` (Helm values do not cross-reference keys). Install this Helm release into the **same namespace** as that ConfigMap (default `vault`) so the projected volume can mount it. |
| vault.global.externalVaultAddr | string | `""` | Hub Vault API URL for CSI `VAULT_ADDR` when `csi.agent.enabled` is false (required on spokes unless you set it from the clustergroup layer). Example: `https://vault-vault.apps.<hubClusterDomain>`. |

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
