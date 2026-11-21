{{/* vim: set filetype=mustache: */}}

{{/*
Name of the application (defaults to the chart name).
*/}}
{{- define "application.name" -}}
{{- default .Chart.Name .Values.applicationName | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Application version, derived from the deployment image tag and sanitised so it
is a valid label value.
*/}}
{{- define "application.version" -}}
  {{- $version := default "" .Values.deployment.image.tag -}}
  {{- regexReplaceAll "[^a-zA-Z0-9_\\.\\-]" $version "-" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Renders a value that may contain templates.
Usage:
{{ include "application.tplvalues.render" ( dict "value" .Values.path.to.the.Value "context" $) }}
*/}}
{{- define "application.tplvalues.render" -}}
    {{- $value := .value -}}
    {{- if or (not $value) (kindIs "invalid" $value) -}}
        {{- "" -}}
    {{- else if typeIs "string" $value -}}
        {{- tpl $value .context -}}
    {{- else -}}
        {{- tpl ($value | toYaml) .context -}}
    {{- end -}}
{{- end -}}

{{/*
Chart name and version, as used by the helm.sh/chart label.
*/}}
{{- define "application.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Additional common labels (rendered through tpl).
*/}}
{{- define "application.additionalLabels" -}}
{{- with .Values.additionalLabels -}}
{{ include "application.tplvalues.render" ( dict "value" . "context" $ ) }}
{{- end -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "application.labels" -}}
app.kubernetes.io/name: {{ include "application.name" . }}
helm.sh/chart: {{ include "application.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- with include "application.version" . }}
app.kubernetes.io/version: {{ quote . }}
{{- end }}
{{- with .Values.componentOverride }}
app.kubernetes.io/component: {{ . }}
{{- end }}
{{- /* Falls back to the application name for backwards compatibility. */}}
app.kubernetes.io/part-of: {{ default (include "application.name" .) .Values.partOfOverride }}
{{- with include "application.additionalLabels" . }}
{{ . }}
{{- end }}
{{- end -}}

{{/*
Selector labels (immutable once a workload is created, keep them minimal)
*/}}
{{- define "application.selectorLabels" -}}
app.kubernetes.io/name: {{ include "application.name" . }}
application.stakater.com/workload-class: serving
{{- end -}}

{{/*
Namespace of the resources (the release namespace unless overridden)
*/}}
{{- define "application.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride -}}
{{- end -}}

{{/*
Name of the ServiceAccount used by the workloads
*/}}
{{- define "application.serviceAccountName" -}}
{{- default (include "application.name" .) .Values.rbac.serviceAccount.name -}}
{{- end -}}

{{/*
Standard `metadata` block: name, namespace, labels and (optional) annotations.
Resource specific labels override the common ones.
Usage:
metadata:
  {{- include "application.metadata" (dict "context" $ "name" (include "application.name" .) "labels" .Values.x.additionalLabels "annotations" .Values.x.annotations) | nindent 2 }}
Optional keys: "namespace" (defaults to application.namespace).
*/}}
{{- define "application.metadata" -}}
{{- $ctx := .context -}}
{{- $labels := merge (dict) (.labels | default dict) (include "application.labels" $ctx | fromYaml) -}}
{{- $meta := dict "name" .name "namespace" (default (include "application.namespace" $ctx) .namespace) "labels" $labels -}}
{{- with .annotations }}{{- $_ := set $meta "annotations" . }}{{- end -}}
{{- toYaml $meta -}}
{{- end -}}

{{/*
Pod template labels: common labels + workload class (+ extra labels).
The selector labels always win so they can not be overridden by accident.
Usage: include "application.podLabels" (dict "context" $ "class" "serving" "labels" .Values.x.podLabels)
*/}}
{{- define "application.podLabels" -}}
{{- $ctx := .context -}}
{{- $selector := dict "application.stakater.com/workload-class" .class -}}
{{- toYaml (merge (dict) $selector (.labels | default dict) (include "application.labels" $ctx | fromYaml)) -}}
{{- end -}}

{{/*
Container image reference: repository[:tag][@digest]. All three values are rendered through tpl.
Usage: include "application.image" (dict "image" .Values.deployment.image "context" $ "name" "container-name")
Optional key: "error" (custom message used when the repository is empty).
*/}}
{{- define "application.image" -}}
{{- $image := .image | default dict -}}
{{- $repo := include "application.tplvalues.render" (dict "value" $image.repository "context" .context) -}}
{{- $repo = required (default (printf "Undefined image repo for container '%s'" .name) .error) $repo -}}
{{- $tag := include "application.tplvalues.render" (dict "value" $image.tag "context" .context) -}}
{{- $digest := include "application.tplvalues.render" (dict "value" $image.digest "context" .context) -}}
{{- $ref := $repo -}}
{{- with $tag }}{{ $ref = print $ref ":" . }}{{ end -}}
{{- with $digest }}{{ $ref = print $ref "@" . }}{{ end -}}
{{- $ref -}}
{{- end -}}

{{/*
Probe definition: timing fields plus the first configured handler (exec, httpGet, tcpSocket, grpc).
Usage: include "application.probe" .Values.deployment.livenessProbe
*/}}
{{- define "application.probe" -}}
{{- $probe := pick . "initialDelaySeconds" "periodSeconds" "timeoutSeconds" "successThreshold" "failureThreshold" "terminationGracePeriodSeconds" -}}
{{- $found := false -}}
{{- range $handler := list "exec" "httpGet" "tcpSocket" "grpc" -}}
  {{- $value := index $ $handler -}}
  {{- if and $value (not $found) -}}
    {{- $_ := set $probe $handler $value -}}
    {{- $found = true -}}
  {{- end -}}
{{- end -}}
{{- toYaml $probe -}}
{{- end -}}

{{/*
Environment variables from a map of NAME -> (value | valueFrom) entries. Names and values are rendered through tpl.
Usage: include "application.env" (dict "env" .Values.deployment.env "context" $)
*/}}
{{- define "application.env" -}}
{{- $ctx := .context -}}
{{- $out := "" -}}
{{- range $name, $spec := .env -}}
  {{- $key := include "application.tplvalues.render" (dict "value" $name "context" $ctx) -}}
  {{- $body := include "application.tplvalues.render" (dict "value" $spec "context" $ctx) | indent 2 -}}
  {{- $out = printf "%s\n- name: %s\n%s" $out $key $body -}}
{{- end -}}
{{- trim $out -}}
{{- end -}}

{{/*
OpenShift: OAuthRedirectReference annotation payload for the ServiceAccount
*/}}
{{- define "application.sa.oauth-redirectreference" -}}
apiVersion: v1
kind: OAuthRedirectReference
reference:
  kind: Route
  name: {{ include "application.name" . }}
{{- end -}}
