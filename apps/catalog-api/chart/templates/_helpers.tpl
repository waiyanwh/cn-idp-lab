{{- define "catalog-api.name" -}}
catalog-api
{{- end -}}

{{- define "catalog-api.labels" -}}
app.kubernetes.io/name: {{ include "catalog-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: internal-developer-platform
{{- end -}}

