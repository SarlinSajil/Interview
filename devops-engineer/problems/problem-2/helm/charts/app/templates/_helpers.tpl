{{/*
Expand the name of the chart.
*/}}
{{- define "devops-demo-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "devops-demo-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "devops-demo-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "devops-demo-app.labels" -}}
helm.sh/chart: {{ include "devops-demo-app.chart" . }}
{{ include "devops-demo-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/environment: {{ .Values.environment }}
{{- if .Values.blueGreen.enabled }}
app.kubernetes.io/color: {{ .Values.blueGreen.color }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "devops-demo-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "devops-demo-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Values.blueGreen.enabled }}
app.kubernetes.io/color: {{ .Values.blueGreen.color }}
{{- end }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "devops-demo-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "devops-demo-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Create image name with tag
*/}}
{{- define "devops-demo-app.image" -}}
{{- printf "%s:%s" .Values.image.repository .Values.image.tag }}
{{- end }}

{{/*
Create environment variables
*/}}
{{- define "devops-demo-app.envVars" -}}
- name: ENVIRONMENT
  value: {{ .Values.environment | quote }}
- name: REDIS_HOST
  value: {{ .Values.cache.redis.host | quote }}
- name: REDIS_PORT
  value: {{ .Values.cache.redis.port | quote }}
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.cache.redis.existingSecret }}
      key: {{ .Values.cache.redis.passwordKey }}
- name: POSTGRES_HOST
  value: {{ .Values.database.postgres.host | quote }}
- name: POSTGRES_PORT
  value: {{ .Values.database.postgres.port | quote }}
- name: POSTGRES_DB
  value: {{ .Values.database.postgres.database | quote }}
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.postgres.existingSecret }}
      key: {{ .Values.database.postgres.userKey }}
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.database.postgres.existingSecret }}
      key: {{ .Values.database.postgres.passwordKey }}
{{- range .Values.extraEnvVars }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}
{{- end }}