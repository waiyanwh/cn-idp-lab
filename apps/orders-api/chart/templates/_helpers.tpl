{{- define "orders-api.name" -}}
orders-api
{{- end -}}

{{- define "orders-api.labels" -}}
app.kubernetes.io/name: {{ include "orders-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/part-of: internal-developer-platform
{{- end -}}

