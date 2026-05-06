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
Filesystem path to the Vault TLS CA file on the CSI provider pod when using **openshift-sscsi-vault** projected trust.
Matches `caProvider.syncProviderCaConfigMap`: CNO proxy bundle key (`injectTrustedCabundle`) vs PEM key (`keyInConfigMap`).
Usage: {{ include "openshift_sscsi_vault.syncProviderVaultCACertPath" . }}
*/}}
{{- define "openshift_sscsi_vault.syncProviderVaultCACertPath" -}}
{{- $cap := .Values.ocpSecretsStoreCsiVault.caProvider | default dict }}
{{- $sync := $cap.syncProviderCaConfigMap | default dict }}
{{- $mount := $sync.mountDir | default "/etc/pki/vault-ca" | trim | trimSuffix "/" }}
{{- $inject := true }}
{{- if and (hasKey $sync "injectTrustedCabundle") (kindIs "bool" $sync.injectTrustedCabundle) }}
{{- $inject = $sync.injectTrustedCabundle }}
{{- end }}
{{- if $inject }}
{{- $key := $sync.trustedCabundleDataKey | default "ca-bundle.crt" | trim }}
{{- printf "%s/%s" $mount $key }}
{{- else }}
{{- $key := $sync.keyInConfigMap | default "vault-tls-ca.pem" | trim }}
{{- printf "%s/%s" $mount $key }}
{{- end }}
{{- end }}
