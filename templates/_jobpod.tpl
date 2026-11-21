{{/*
Pod template (metadata + spec) shared by Job and CronJob.
Usage:
  include "application.jobPodTemplate" (dict "context" $ "name" $name "job" $job "class" "batch" "legacySecurityContext" "pod")

  - class:                workload class label ("batch" for Job, "scheduled" for CronJob)
  - legacySecurityContext: where the legacy `securityContext` key of a job is applied:
                          "pod" (Job) or "container" (CronJob). `podSecurityContext` and
                          `containerSecurityContext` can be used to set either level explicitly.
*/}}
{{- define "application.jobPodTemplate" -}}
{{- $ctx := .context -}}
{{- $name := .name -}}
{{- $job := .job -}}
{{- $podSecurityContext := $job.podSecurityContext -}}
{{- $containerSecurityContext := $job.containerSecurityContext -}}
{{- if eq .legacySecurityContext "pod" -}}
  {{- $podSecurityContext = default $job.securityContext $podSecurityContext -}}
{{- else -}}
  {{- $containerSecurityContext = default $job.securityContext $containerSecurityContext -}}
{{- end -}}
metadata:
  labels:
    {{- include "application.podLabels" (dict "context" $ctx "class" .class "labels" $job.additionalPodLabels) | nindent 4 }}
  {{- with $job.additionalPodAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  automountServiceAccountToken: {{ ternary true $job.automountServiceAccountToken (kindIs "invalid" $job.automountServiceAccountToken) }}
  {{- if $ctx.Values.rbac.enabled }}
  serviceAccountName: {{ include "application.serviceAccountName" $ctx }}
  {{- end }}
  restartPolicy: {{ default "OnFailure" $job.restartPolicy }}
  {{- if not (kindIs "invalid" $job.enableServiceLinks) }}
  enableServiceLinks: {{ $job.enableServiceLinks }}
  {{- end }}
  {{- with $job.hostAliases }}
  hostAliases:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $job.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $job.priorityClassName }}
  priorityClassName: {{ . }}
  {{- end }}
  {{- with $podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $job.dnsPolicy }}
  dnsPolicy: {{ . }}
  {{- end }}
  {{- with $job.dnsConfig }}
  dnsConfig:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $job.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $job.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $job.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $job.topologySpreadConstraints }}
  topologySpreadConstraints:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $job.initContainers }}
  initContainers:
    {{- range $key, $value := . }}
    - name: {{ $key }}
      {{- include "application.tplvalues.render" (dict "value" (omit $value "name") "context" $ctx) | nindent 6 }}
    {{- end }}
  {{- end }}
  containers:
    - name: {{ $name }}
      image: {{ include "application.image" (dict "image" $job.image "context" $ctx "name" $name) | quote }}
      {{- with $job.image.imagePullPolicy }}
      imagePullPolicy: {{ . }}
      {{- end }}
      {{- with $job.command }}
      command:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $job.args }}
      args:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $job.env }}
      env:
        {{- include "application.env" (dict "env" . "context" $ctx) | nindent 8 }}
      {{- end }}
      {{- with $job.envFrom }}
      envFrom:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $job.resources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $job.volumeMounts }}
      volumeMounts:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with $containerSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  {{- with $job.volumes }}
  volumes:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
