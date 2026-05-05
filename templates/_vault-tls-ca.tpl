{{/*
Resolve PEM for Vault CSI TLS (ConfigMap data and/or vaultCACertPath).

Argo CD (and most `helm template` runs) use client-side rendering: helm lookup() returns nothing.
Use `caProvider.syncProviderCaConfigMap.pemLiteral` (SOPS, external values, or Argo parameters) for GitOps,
or set `createConfigMap: false` and provide the ConfigMap + mount out-of-band while still setting vaultCACertPath.

Optional: `useLookup: true` for cluster-side helm (install/upgrade or template --dry-run=server) to copy from
openshift-ingress / external-secrets objects (same presets as ESO).

Optional: `syncProviderCaConfigMap.injectTrustedCabundle: true` with `createConfigMap: true` emits an empty
ConfigMap labeled `config.openshift.io/inject-trusted-cabundle: "true"` so the Cluster Network Operator injects
the cluster merged CA bundle (`ca-bundle.crt` by default; see OpenShift "Certificate injection using Operators" / custom PKI docs).
Default annotation `argocd.argoproj.io/ignore-differences` is a small YAML document with **jsonPointers** (`/data`)
and **jqPathExpressions** (`.data`) so Argo / OpenShift GitOps ignores the whole injected trust bundle map that CNO owns.
Mount the bundle via projected volume `items` + `optional: true`
on the Vault CSI DaemonSet (see README).
*/}}
{{- define "openshift_sscsi_vault.argocdIgnoreInjectedTrustedDataYaml" -}}
jsonPointers:
- /data
jqPathExpressions:
- .data
{{- end }}
{{- define "openshift_sscsi_vault.vaultTlsCaPemFromCluster" -}}
{{- $cap := .Values.ocpSecretsStoreCsiVault.caProvider | default dict }}
{{- $sync := $cap.syncProviderCaConfigMap | default dict }}
{{- if not (default false $sync.enabled) -}}
{{- else }}
{{- $lit := $sync.pemLiteral | default "" | trim }}
{{- if ne $lit "" -}}
{{- $lit -}}
{{- else if default false $sync.useLookup }}
{{- $hashicorp_vault_found := false }}
{{- if and .Values.clusterGroup .Values.clusterGroup.applications }}
{{- range $_, $app := .Values.clusterGroup.applications }}
  {{- if $app }}
    {{- if eq $app.chart "hashicorp-vault" }}
      {{- $hashicorp_vault_found = true }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- $isHubStyleAuth := or (eq (include "openshift_sscsi_vault.ishubcluster" .) "true") $hashicorp_vault_found }}
{{- $preset := $sync.preset | default "auto" | trim | lower }}
{{- if eq $preset "auto" }}
  {{- if $isHubStyleAuth }}
    {{- $preset = "ingressrouterca" }}
  {{- else }}
    {{- $preset = "esospokehubca" }}
  {{- end }}
{{- end }}
{{- if eq $preset "ingressrouterca" }}
  {{- $ref := $sync.ingressRouterCa | default dict }}
  {{- $ns := $ref.namespace | default "openshift-ingress" }}
  {{- $name := $ref.name | default "router-ca" }}
  {{- $key := $ref.key | default "ca-bundle.crt" }}
  {{- $obj := lookup "v1" "ConfigMap" $ns $name }}
  {{- if not (and $obj (hasKey $obj.data $key)) }}
  {{- $obj = lookup "v1" "ConfigMap" $ns "router-ca-certs" }}
  {{- end }}
  {{- $routerPem := "" }}
  {{- if and $obj (hasKey $obj.data $key) }}
  {{- $routerPem = index $obj.data $key }}
  {{- end }}
  {{- $hc := $cap.hostCluster | default dict }}
  {{- $kns := $hc.namespace | default "external-secrets" }}
  {{- $kname := $hc.name | default "kube-root-ca.crt" }}
  {{- $kkey := $hc.key | default "ca.crt" }}
  {{- $kobj := lookup "v1" "ConfigMap" $kns $kname }}
  {{- $kubePem := "" }}
  {{- if and $kobj (hasKey $kobj.data $kkey) }}
  {{- $kubePem = index $kobj.data $kkey }}
  {{- end }}
  {{- if and (ne $routerPem "") (ne $kubePem "") }}
  {{- print $routerPem "\n" $kubePem }}
  {{- else if ne $routerPem "" }}
  {{- print $routerPem }}
  {{- else if ne $kubePem "" }}
  {{- print $kubePem }}
  {{- end }}
{{- else if eq $preset "esohubkuberootca" }}
  {{- $hc := $cap.hostCluster | default dict }}
  {{- $ns := $hc.namespace | default "external-secrets" }}
  {{- $name := $hc.name | default "kube-root-ca.crt" }}
  {{- $key := $hc.key | default "ca.crt" }}
  {{- $obj := lookup "v1" "ConfigMap" $ns $name }}
  {{- if and $obj (hasKey $obj.data $key) }}{{- index $obj.data $key -}}{{- end }}
{{- else if eq $preset "esospokehubca" }}
  {{- $cc := $cap.clientCluster | default dict }}
  {{- $ns := $cc.namespace | default "external-secrets" }}
  {{- $name := $cc.name | default "hub-ca" }}
  {{- $key := $cc.key | default "hub-kube-root-ca.crt" }}
  {{- $obj := lookup "v1" "Secret" $ns $name }}
  {{- if and $obj (hasKey $obj.data $key) }}{{- index $obj.data $key | b64dec -}}{{- end }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "openshift_sscsi_vault.syncVaultCsiTlsCaConfigMapYaml" -}}
{{- $cap := .Values.ocpSecretsStoreCsiVault.caProvider | default dict }}
{{- $sync := $cap.syncProviderCaConfigMap | default dict }}
{{- $createCM := true }}
{{- if hasKey $sync "createConfigMap" }}
{{- $createCM = $sync.createConfigMap }}
{{- end }}
{{- if and (default false $sync.enabled) $createCM }}
{{- $inject := true }}
{{- if and (hasKey $sync "injectTrustedCabundle") (kindIs "bool" $sync.injectTrustedCabundle) }}
{{- $inject = $sync.injectTrustedCabundle }}
{{- end }}
{{- if $inject }}
{{- $injectKey := $sync.trustedCabundleDataKey | default "ca-bundle.crt" | trim }}
{{- $ignoreArgocd := true }}
{{- if and (hasKey $sync "argocdIgnoreInjectedTrustedCabundleData") (kindIs "bool" $sync.argocdIgnoreInjectedTrustedCabundleData) }}
{{- $ignoreArgocd = $sync.argocdIgnoreInjectedTrustedCabundleData }}
{{- end }}
{{- $cmAnns := dict }}
{{- if $ignoreArgocd }}
{{- $_ := set $cmAnns "argocd.argoproj.io/ignore-differences" (include "openshift_sscsi_vault.argocdIgnoreInjectedTrustedDataYaml" .) }}
{{- end }}
{{- $cmAnns = mergeOverwrite $cmAnns ($sync.configMapAnnotations | default dict) }}
{{- $cmName := $sync.configMapName | default "" | trim }}
{{- if eq $cmName "" }}
{{- $cmName = "openshift-sscsi-vault-vault-tls-ca" }}
{{- end }}
{{- $targetNs := $sync.targetNamespace | default "vault" | trim }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $cmName | quote }}
  namespace: {{ $targetNs | quote }}
  labels:
    app.kubernetes.io/name: openshift-sscsi-vault
    app.kubernetes.io/component: vault-csi-tls-ca
    config.openshift.io/inject-trusted-cabundle: "true"
{{- if $cmAnns }}
  annotations:
{{- toYaml $cmAnns | nindent 4 }}
{{- end }}
data: {}
{{- else }}
{{- $pem := trim (include "openshift_sscsi_vault.vaultTlsCaPemFromCluster" .) }}
{{- if ne $pem "" }}
{{- $cmName := $sync.configMapName | default "" | trim }}
{{- if eq $cmName "" }}
{{- $cmName = "openshift-sscsi-vault-vault-tls-ca" }}
{{- end }}
{{- $targetNs := $sync.targetNamespace | default "vault" | trim }}
{{- $keyFile := $sync.keyInConfigMap | default "vault-tls-ca.pem" | trim }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ $cmName | quote }}
  namespace: {{ $targetNs | quote }}
  labels:
    app.kubernetes.io/name: openshift-sscsi-vault
    app.kubernetes.io/component: vault-csi-tls-ca
data:
  {{ $keyFile | quote }}: |
{{ $pem | nindent 4 }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Emit synced CA ConfigMap YAML plus a trailing document separator when non-empty.
Use before `openshift_sscsi_vault.secretproviderclass` from any parent chart (pass the same $vaultCtx).
*/}}
{{- define "openshift_sscsi_vault.renderSyncCaConfigMap" -}}
{{- $ca := include "openshift_sscsi_vault.syncVaultCsiTlsCaConfigMapYaml" . | trim }}
{{- if $ca }}
{{ $ca }}
---

{{- end }}
{{- end }}
