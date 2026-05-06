# openshift-sscsi-vault

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square)

Helm chart for cluster-wide Vault Secrets Store CSI support on OpenShift. It focuses on provider-facing trust material (optional synced CA ConfigMap) across hub, spoke, and external Vault topologies. App-specific SecretProviderClass manifests are split into a dedicated chart.

This chart is used by the Validated Patterns to configure cluster-wide Vault CSI support.

### Scope and chart split

This repository now owns cluster-wide components only. Specifically:

- Optional synced CA ConfigMap for the Vault CSI provider namespace (`caProvider.syncProviderCaConfigMap`)
- Hub/spoke/external-aware CA source resolution helpers (`vaultTlsCaPemFromCluster`)

Application-owned SecretProviderClass resources should live in a separate SPC-focused chart and be included by each workload chart that needs Vault CSI objects.

### Cluster-wide usage

Install this chart as the single owner of provider trust material:

```yaml
ocpSecretsStoreCsiVault:
  clusterWide:
    installDefaultManifests: true
```

Set `installDefaultManifests: false` when reusing only named templates.

### Validated Patterns clustergroup application

Declare this chart under `clusterGroup.applications` in your pattern cluster values (for example `values-hub.yaml`). The clustergroup chart renders an Argo CD `Application` per entry.

**1. Chart published in the pattern Helm repo (multi-source)**

```yaml
clusterGroup:
  namespaces:
    vault: {}
    config-demo: {}
  argoProjects:
    - config-demo
  applications:
    openshift-sscsi-vault:
      name: openshift-sscsi-vault-cluster
      namespace: config-demo
      argoProject: config-demo
      chart: openshift-sscsi-vault
      chartVersion: 0.0.*
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

Adjust `name`, `namespace`, `argoProject`, and override file paths to your pattern. The `ignoreDifferences` block matches the default CNO-injected trust `ConfigMap` when you use `injectTrustedCabundle`; drop or change it if your CA sync mode does not need Argo to ignore `/data`.

**2. Chart in its own Git repository (multi-source)**

```yaml
clusterGroup:
  applications:
    openshift-sscsi-vault:
      name: openshift-sscsi-vault-cluster
      namespace: config-demo
      argoProject: config-demo
      repoURL: https://github.com/yourorg/openshift-sscsi-vault-chart.git
      path: "."
      chartVersion: main
      extraValueFiles:
        - $patternref/overrides/values-openshift-sscsi-vault-cluster.yaml
```

Ensure target namespaces exist under `clusterGroup.namespaces` and the Argo `AppProject` is listed under `clusterGroup.argoProjects`.

### Named templates

- **`openshift_sscsi_vault.vaultTlsCaPemFromCluster`** — PEM for the synced bundle: **`syncProviderCaConfigMap.pemLiteral`** first (Argo CD / `helm template` safe), else optional **`useLookup: true`** cluster copy (ESO-style hub/spoke presets; hub ingress `router-ca` / `router-ca-certs` plus optional `kube-root-ca.crt` concat). Default **`useLookup: false`** because Argo renders manifests without a live API.
- **`openshift_sscsi_vault.syncVaultCsiTlsCaConfigMapYaml`** — ConfigMap manifest when sync is enabled, **`createConfigMap`** is true, and either PEM from **`vaultTlsCaPemFromCluster`** is non-empty **or** **`syncProviderCaConfigMap.injectTrustedCabundle`** is true (OpenShift `config.openshift.io/inject-trusted-cabundle` label; CNO fills **`trustedCabundleDataKey`**, default **`ca-bundle.crt`**).
- **`openshift_sscsi_vault.renderSyncCaConfigMap`** — ConfigMap + trailing `---` when non-empty (convenience).

Mount the synced (or pre-provisioned) ConfigMap on the **Vault CSI provider** DaemonSet at **`caProvider.syncProviderCaConfigMap.mountDir`** (HashiCorp Vault chart **`csi.volumes`** / **`csi.volumeMounts`**; Validated Patterns often use **`extraValueFiles`**).

### Namespaces

The synced TLS **`ConfigMap`** is created in **`caProvider.syncProviderCaConfigMap.targetNamespace`** (default **`vault`**), not in the Helm release namespace. Mount it on the **Vault CSI provider** pods there.

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

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
