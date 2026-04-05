{{/*
Expand name: api, ollama, etc. or release-name-api when nameOverride set.
*/}}
{{- define "sre-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "sre-agent.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{- define "sre-agent.namespace" -}}
{{- .Release.Namespace | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "sre-agent.labels" -}}
app.kubernetes.io/name: {{ include "sre-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: rag-k8s-llm
{{- end }}

{{- define "sre-agent.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
imagePullSecrets for private registries (GHCR, ECR, Docker Hub pro, etc.)
Values: imagePullSecrets: [ { name: regcred } ]
*/}}
{{- define "sre-agent.imagePullSecrets" -}}
{{- if .Values.imagePullSecrets }}
imagePullSecrets:
{{- range .Values.imagePullSecrets }}
  - name: {{ .name }}
{{- end }}
{{- end }}
{{- end }}

