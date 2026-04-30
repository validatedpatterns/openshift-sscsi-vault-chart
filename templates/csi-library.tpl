{{/*
Expand the name of the chart.
*/}}
{{- define "openshift_sscsi_vault.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Stable unique name for cluster-scoped resources when this chart is used as a library dependency.
(When included from a parent chart, .Chart.Name would be the parent's name — do not use it here.)
*/}}
{{- define "openshift_sscsi_vault.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else if .Values.nameOverride }}
{{- printf "%s-%s" .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-openshift-sscsi-vault" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Determines if the current cluster is a hub cluster (same logic as openshift-external-secrets).
Usage: {{ include "openshift_sscsi_vault.ishubcluster" . }}
Returns: "true" or "false" as a string
*/}}
{{- define "openshift_sscsi_vault.ishubcluster" -}}
{{- if and (hasKey .Values.clusterGroup "isHubCluster") (not (kindIs "invalid" .Values.clusterGroup.isHubCluster)) -}}
  {{- .Values.clusterGroup.isHubCluster | toString -}}
{{- else if $.Values.global.hubClusterDomain -}}
  {{- $localDomain := coalesce $.Values.global.localClusterDomain $.Values.global.hubClusterDomain -}}
  {{- if eq $localDomain $.Values.global.hubClusterDomain -}}
true
  {{- else -}}
false
  {{- end -}}
{{- else -}}
false
{{- end -}}
{{- end }}

{{/*
SecretProviderClass for Vault CSI provider (namespaced).
Expects standard Helm root context with .Values.ocpSecretsStoreCsiVault, .Values.clusterGroup, .Values.global.
*/}}
{{- define "openshift_sscsi_vault.secretproviderclass" -}}
{{- if .Values.ocpSecretsStoreCsiVault.secretProviderClass.enabled }}
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
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: {{ .Values.ocpSecretsStoreCsiVault.secretProviderClass.name }}
  namespace: {{ .Values.ocpSecretsStoreCsiVault.rbac.serviceAccount.namespace }}
spec:
  provider: vault
{{- with .Values.ocpSecretsStoreCsiVault.secretObjects }}
  secretObjects:
{{- toYaml . | nindent 4 }}
{{- end }}
  parameters:
{{- $extVault := .Values.ocpSecretsStoreCsiVault.vault.externalAddress | default "" | trim }}
{{- if ne $extVault "" }}
    vaultAddress: {{ $extVault | quote }}
{{- else }}
    vaultAddress: "https://vault-vault.{{ .Values.global.hubClusterDomain }}"
{{- end }}
{{- $vaultTlsSkip := .Values.ocpSecretsStoreCsiVault.tls.vaultSkipTLSVerify | toString | trim | lower }}
{{- if eq $vaultTlsSkip "true" }}
{{- $vaultTlsSkip = "true" }}
{{- else if eq $vaultTlsSkip "false" }}
{{- $vaultTlsSkip = "false" }}
{{- else if eq $vaultTlsSkip "1" }}
{{- $vaultTlsSkip = "true" }}
{{- else if eq $vaultTlsSkip "0" }}
{{- $vaultTlsSkip = "false" }}
{{- else }}
{{- $vaultTlsSkip = "false" }}
{{- end }}
    vaultSkipTLSVerify: {{ $vaultTlsSkip | quote }}
{{- $tls := .Values.ocpSecretsStoreCsiVault.tls }}
{{- $explicitCACert := $tls.vaultCACertPath | default "" | trim }}
{{- $cap := .Values.ocpSecretsStoreCsiVault.caProvider | default dict }}
{{- $capEnabled := true }}
{{- if and $cap (hasKey $cap "enabled") }}
{{- $capEnabled = $cap.enabled }}
{{- end }}
{{- $sync := $cap.syncProviderCaConfigMap | default dict }}
{{- $effCACert := $explicitCACert }}
{{- if ne $vaultTlsSkip "true" }}
{{- if and (eq $effCACert "") (default false $sync.enabled) }}
{{- $mountDir := $sync.mountDir | default "/etc/pki/vault-ca" | trim }}
{{- $keyFile := $sync.keyInConfigMap | default "vault-tls-ca.pem" | trim }}
{{- $pem := trim (include "openshift_sscsi_vault.vaultTlsCaPemFromCluster" .) }}
{{- $createCM := true }}
{{- if hasKey $sync "createConfigMap" }}
{{- $createCM = $sync.createConfigMap }}
{{- end }}
{{- if ne $pem "" }}
{{- $effCACert = printf "%s/%s" $mountDir $keyFile }}
{{- else if not $createCM }}
{{- $effCACert = printf "%s/%s" $mountDir $keyFile }}
{{- end }}
{{- end }}
{{- if and (eq $effCACert "") $capEnabled (not (default false $sync.enabled)) }}
{{- $hc := $cap.hostCluster | default dict }}
{{- $cc := $cap.clientCluster | default dict }}
{{- $effCACert = ternary (($hc.defaultVaultCACertPath | default "/etc/pki/vault-ca/kube-root-ca.crt") | trim) (($cc.defaultVaultCACertPath | default "/etc/pki/vault-ca/hub-kube-root-ca.crt") | trim) $isHubStyleAuth }}
{{- end }}
{{- if ne $effCACert "" }}
    vaultCACertPath: {{ $effCACert | quote }}
{{- end }}
{{- end }}
{{- if .Values.ocpSecretsStoreCsiVault.tls.vaultTLSServerName }}
    vaultTLSServerName: {{ .Values.ocpSecretsStoreCsiVault.tls.vaultTLSServerName | quote }}
{{- end }}
{{- if $isHubStyleAuth }}
    vaultKubernetesMountPath: {{ .Values.ocpSecretsStoreCsiVault.vault.hubMountPath | quote }}
    roleName: {{ .Values.ocpSecretsStoreCsiVault.rbac.rolename | quote }}
{{- else }}
    vaultKubernetesMountPath: {{ $.Values.global.clusterDomain | quote }}
    roleName: {{ printf "%s-role" $.Values.global.clusterDomain | quote }}
{{- end }}
    objects: |
{{- range .Values.ocpSecretsStoreCsiVault.objects }}
      - objectName: {{ .objectName | quote }}
        secretPath: {{ .secretPath | quote }}
        secretKey: {{ .secretKey | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
RBAC for workloads authenticating to Vault via Kubernetes auth (token review delegation).
When rbac.serviceAccount.create is false, only ClusterRoleBinding is rendered (use existing SA).
*/}}
{{- define "openshift_sscsi_vault.workload_rbac" -}}
{{- if .Values.ocpSecretsStoreCsiVault.secretProviderClass.enabled }}
{{- $sa := .Values.ocpSecretsStoreCsiVault.rbac.serviceAccount }}
{{- $skipSa := and (hasKey $sa "create") (eq $sa.create false) }}
{{- if not $skipSa }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.ocpSecretsStoreCsiVault.rbac.serviceAccount.name }}
  namespace: {{ .Values.ocpSecretsStoreCsiVault.rbac.serviceAccount.namespace }}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Values.ocpSecretsStoreCsiVault.rbac.serviceAccount.name }}
  namespace: {{ .Values.ocpSecretsStoreCsiVault.rbac.serviceAccount.namespace }}
  annotations:
    kubernetes.io/service-account.name: {{ .Values.ocpSecretsStoreCsiVault.rbac.serviceAccount.name }}
type: kubernetes.io/service-account-token
---
{{- end }}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ include "openshift_sscsi_vault.fullname" . }}-tokenreview
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: {{ .Values.ocpSecretsStoreCsiVault.rbac.serviceAccount.name }}
    namespace: {{ .Values.ocpSecretsStoreCsiVault.rbac.serviceAccount.namespace }}
{{- end }}
{{- end }}
