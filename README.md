# application

A generic Helm chart for deploying applications (Java, Node.js, .NET, Go, …) on Kubernetes and OpenShift.
Deploy a workload, expose it, scale it, monitor it and back it up — all from a single `values.yaml`.
Every resource is optional and is switched on or off from the values file.

- [Quick start](#quick-start)
- [How to write your values file](#how-to-write-your-values-file)
- [Common recipes](#common-recipes)
- [Reference: what each section renders](#reference-what-each-section-renders)
- [Naming, labels and namespace](#naming-labels-and-namespace)
- [Templating inside values (`tpl`)](#templating-inside-values-tpl)
- [Install, upgrade and debug](#install-upgrade-and-debug)
- [Development and tests](#development-and-tests)

## Quick start

Create a file called `my-values.yaml`. This is the smallest useful configuration: a Deployment and a Service.

```yaml
applicationName: my-app

deployment:
  image:
    repository: registry.example.com/team/my-app
    tag: 1.4.2
  ports:
    - name: http
      containerPort: 8080
      protocol: TCP

service:
  ports:
    - name: http
      port: 8080
      targetPort: 8080
      protocol: TCP
```

Install it:

```bash
helm upgrade --install my-app . -n my-namespace --create-namespace -f my-values.yaml
```

Only `deployment.image.repository` is mandatory; the chart fails with
`Undefined image for application container` if it is empty.

## How to write your values file

### Rules of thumb

1. **Start from nothing.** Your values file only needs the keys you want to change. Everything else keeps
   the default from this chart's [`values.yaml`](values.yaml), which documents every key.
2. **Maps are merged, lists are replaced.** If you set `service.ports`, your list replaces the default list
   completely, so repeat every port you need.
3. **Switch features on with `enabled: true`.** Sections such as `ingress`, `autoscaling`, `pdb`,
   `serviceMonitor`, … are disabled by default. `deployment` and `service` are enabled by default.
4. **Resource specific labels and annotations** go in `additionalLabels` / `annotations` of that section.
   Labels for *every* resource go in the top-level `additionalLabels`.
5. **Keep one values file per environment**, for example `values-dev.yaml` and `values-prod.yaml`, and
   pass them in order — later files win:

   ```bash
   helm upgrade --install my-app . -f values-common.yaml -f values-prod.yaml
   ```
6. **Never put real secrets in a values file that is committed.** Use `externalSecret`, `sealedSecret` or
   `secretProviderClass` (see below), or pass them at deploy time with `--set-file` / `--set`.

### Top-level keys

| Key | Purpose |
| --- | --- |
| `applicationName` | Name used for all resources. Defaults to the chart name (`application`). Always set this. |
| `namespaceOverride` | Render resources into this namespace instead of the release namespace. |
| `componentOverride` | Sets the `app.kubernetes.io/component` label. |
| `partOfOverride` | Sets the `app.kubernetes.io/part-of` label (defaults to the application name). |
| `additionalLabels` | Extra labels added to **all** resources. Values are rendered with `tpl`. |

### Deployment

```yaml
deployment:
  enabled: true                 # set to false if you only need jobs / cronjobs
  replicas: 2                   # omit it when autoscaling is enabled
  revisionHistoryLimit: 2
  reloadOnChange: true          # roll pods when a referenced ConfigMap/Secret changes (needs Stakater Reloader)

  image:
    repository: registry.example.com/team/my-app
    tag: 1.4.2
    # digest: sha256:...        # if set, rendered as repository:tag@digest
    pullPolicy: IfNotPresent
  imagePullSecrets:
    - name: registry-credentials

  command: ["/app/server"]      # optional, list of strings
  args: ["--port=8080"]         # optional, list of strings

  ports:
    - name: http
      containerPort: 8080
      protocol: TCP

  resources:
    requests: { cpu: 100m, memory: 256Mi }
    limits:   { memory: 512Mi }

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
```

#### Environment variables

`env` is a **map**: the key is the variable name, the value is the Kubernetes `value` / `valueFrom` block.

```yaml
deployment:
  env:
    LOG_LEVEL:
      value: info
    DB_PASSWORD:
      valueFrom:
        secretKeyRef:
          name: my-app-db
          key: password
    POD_NAME:
      valueFrom:
        fieldRef:
          fieldPath: metadata.name
    # templates are allowed
    RELEASE:
      value: '{{ .Release.Name }}'
```

`envFrom` is a list. `type` is `configmap` or `secret`. Name the object with `name` (a full name),
`nameSuffix` (the application name + `-suffix`, which matches the files created by the `configMap` /
`secret` sections) or neither (the application name itself).

```yaml
deployment:
  envFrom:
    - type: configmap
      nameSuffix: config        # -> my-app-config
    - type: secret
      name: shared-credentials
      optional: true
```

#### Probes

Each of `startupProbe`, `livenessProbe` and `readinessProbe` has `enabled` plus the usual timing fields.
Configure **exactly one** handler: `httpGet`, `exec`, `tcpSocket` or `grpc` (the first one that is set wins).

```yaml
deployment:
  startupProbe:
    enabled: true
    failureThreshold: 30
    periodSeconds: 5
    httpGet: { path: /healthz, port: http }
  livenessProbe:
    enabled: true
    periodSeconds: 10
    httpGet: { path: /healthz, port: http }
  readinessProbe:
    enabled: true
    periodSeconds: 5
    httpGet: { path: /ready, port: http }
```

#### Volumes

`volumes` and `volumeMounts` are maps keyed by the volume name; the value is the rest of the Kubernetes spec.

```yaml
deployment:
  volumes:
    config:
      configMap:
        name: my-app-config
    tmp:
      emptyDir: {}
  volumeMounts:
    config:
      mountPath: /etc/my-app
      readOnly: true
    tmp:
      mountPath: /tmp
```

#### Security, scheduling and extras

```yaml
deployment:
  securityContext:              # pod level
    runAsUser: 10001
    fsGroup: 10001
  containerSecurityContext:     # container level (defaults: read-only root fs, runAsNonRoot)
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    capabilities: { drop: ["ALL"] }
  nodeSelector: { disktype: ssd }
  tolerations:
    - key: dedicated
      operator: Equal
      value: apps
      effect: NoSchedule
  affinity: {}
  topologySpreadConstraints: []
  priorityClassName: high-priority
  terminationGracePeriodSeconds: 30
  podLabels: { team: payments }
  additionalPodAnnotations: { prometheus.io/scrape: "true" }
  initContainers:               # map: key = container name
    wait-for-db:
      image: busybox:1.36
      command: ["sh", "-c", "until nc -z db 5432; do sleep 2; done"]
  additionalContainers:         # list of extra sidecar containers
    - name: sidecar
      image: example/sidecar:1.0
```

### Service

```yaml
service:
  enabled: true
  type: ClusterIP               # ClusterIP | NodePort | LoadBalancer
  ports:
    - name: http
      port: 80
      targetPort: 8080
      protocol: TCP
  annotations: {}
```

The ServiceMonitor, Ingress and Route refer to the port **name**, so keep the port named `http` or
adjust them accordingly.

### Persistence

```yaml
persistence:
  enabled: true                 # create the PVC
  mountPVC: true                # mount it into the application container
  mountPath: /data
  storageSize: 10Gi
  accessMode: ReadWriteOnce
  storageClass: fast-ssd        # "-" disables dynamic provisioning
  annotations:
    helm.sh/resource-policy: keep   # keep the data when the release is uninstalled
```

The PVC is named `<applicationName>-data` unless you set `persistence.name`.

### Exposing the application

Pick one of `ingress`, `httpRoute` (Gateway API) or `route` (OpenShift).

```yaml
ingress:
  enabled: true
  ingressClassName: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
  hosts:
    - host: my-app.example.com          # rendered with tpl
      paths:
        - path: /
          pathType: Prefix
          # servicePort: http           # port name (string) or number
  tls:
    - secretName: my-app-tls
      hosts:
        - my-app.example.com
```

```yaml
httpRoute:                              # needs the Gateway API CRDs
  enabled: true
  parentRefs:
    - name: public-gateway
      namespace: gateways
  hostnames:
    - my-app.example.com
  # `rules` defaults to routing "/" to this application's Service
```

```yaml
route:                                  # OpenShift only
  enabled: true
  host: my-app.apps.example.com
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
```

### ConfigMaps and Secrets

`files` is a map: the key becomes the name suffix (`<applicationName>-<key>`).

```yaml
configMap:
  enabled: true
  files:
    config:                     # -> ConfigMap my-app-config
      application.yaml: |
        server:
          port: 8080
      LOG_LEVEL: info

secret:                         # plain Secrets (avoid committing real values)
  enabled: true
  files:
    credentials:                # -> Secret my-app-credentials
      type: Opaque              # optional
      stringData:               # sent as-is
        API_KEY: change-me
      data:                     # plain text, the chart base64 encodes it
        username: admin
      encodedData:              # already base64 encoded
        token: dG9rZW4=
```

Secrets managed outside Helm (preferred):

```yaml
externalSecret:                 # External Secrets Operator
  enabled: true
  refreshInterval: 1h
  secretStore:
    name: vault
    kind: ClusterSecretStore
  files:
    db:                         # -> ExternalSecret and Secret my-app-db
      data:
        password:
          remoteRef:
            key: apps/my-app/db
            property: password
      # or fetch everything under a key:
      # dataFrom:
      #   key: apps/my-app/db

sealedSecret:                   # Bitnami Sealed Secrets
  enabled: true
  files:
    tls:
      type: kubernetes.io/tls
      clusterWide: false
      encryptedData:
        tls.crt: AgB...          # output of kubeseal
```

`secretProviderClass` configures the Secrets Store CSI driver (`provider`, `vaultAddress`, `roleName`,
`objects` as a string or a list, `secretObjects`).

### Autoscaling and availability

```yaml
autoscaling:                    # HorizontalPodAutoscaler (leave deployment.replicas unset)
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 70 }

pdb:                            # minAvailable wins when both are set
  enabled: true
  minAvailable: 1
  # maxUnavailable: 1

vpa:                            # needs the VPA CRDs, otherwise the render fails on purpose
  enabled: false
  updatePolicy:
    updateMode: "Off"
```

### Network policy

```yaml
networkPolicy:
  enabled: true
  ingress:
    - from:
        - namespaceSelector:
            matchLabels: { kubernetes.io/metadata.name: ingress-nginx }
      ports:
        - { protocol: TCP, port: 8080 }
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - { protocol: TCP, port: 5432 }
```

The policy selects the pods of this application (selector labels plus `deployment.podLabels`).

### RBAC and ServiceAccount

```yaml
rbac:
  enabled: true
  serviceAccount:
    enabled: true               # create a ServiceAccount and use it in the pods
    # name: custom-name         # default: the application name
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/my-app
  roles:                        # each entry creates a Role and a RoleBinding
    - name: reader              # -> my-app-role-reader / my-app-rolebinding-reader
      rules:
        - apiGroups: [""]
          resources: ["configmaps"]
          verbs: ["get", "list", "watch"]
```

### Jobs and CronJobs

Both use a map: the key is the Job / CronJob name.

```yaml
cronJob:
  enabled: true
  jobs:
    cleanup:
      schedule: "0 2 * * *"
      timeZone: Europe/Berlin           # Kubernetes 1.27+
      concurrencyPolicy: Forbid
      successfulJobsHistoryLimit: 3
      failedJobsHistoryLimit: 1
      image:
        repository: registry.example.com/team/my-app
        tag: 1.4.2
      command: ["/app/cleanup"]
      args: ["--older-than=30d"]
      env:
        LOG_LEVEL: { value: debug }
      resources:
        requests: { cpu: 50m, memory: 64Mi }
      restartPolicy: OnFailure          # default

job:
  enabled: true
  jobs:
    db-migration:                       # tip: run it as a Helm hook via `annotations`
      annotations:
        helm.sh/hook: pre-upgrade,pre-install
        helm.sh/hook-delete-policy: before-hook-creation
      image:
        repository: registry.example.com/team/my-app
        tag: 1.4.2
      command: ["/app/migrate"]
      backoffLimit: 2
```

### Monitoring and operations

```yaml
serviceMonitor:                 # Prometheus Operator
  enabled: true
  endpoints:
    - port: http
      path: /metrics
      interval: 30s

prometheusRule:
  enabled: true
  groups:
    - name: my-app
      rules:
        - alert: MyAppDown
          expr: up{job="my-app"} == 0
          for: 5m
          labels: { severity: critical }

grafanaDashboard:               # Grafana Operator
  enabled: true
  contents:
    my-app-dashboard:
      url: https://example.com/dashboard.json
      instanceSelector:
        matchLabels: { dashboards: grafana }

certificate:                    # cert-manager
  enabled: true
  secretName: my-app-cert
  commonName: my-app.example.com
  dnsNames: [my-app.example.com]
  issuerRef: { name: letsencrypt, kind: ClusterIssuer, group: cert-manager.io }

backup:                         # Velero
  enabled: true
  namespace: velero
  storageLocation: default
  ttl: 72h0m0s
```

`alertmanagerConfig`, `forecastle` (Stakater Forecastle dashboard entry) and `endpointMonitor`
(Stakater IngressMonitorController) work the same way: set `enabled: true` and fill in the documented keys.

### Extra objects

Anything the chart does not cover can be added with `extraObjects`. Entries may be YAML objects or
multi-line strings (several `---` separated documents are allowed), are rendered with `tpl`, and receive
the common labels automatically.

```yaml
extraObjects:
  - apiVersion: v1
    kind: ConfigMap
    metadata:
      name: '{{ include "application.name" . }}-extra'
    data:
      release: '{{ .Release.Name }}'
```

## Common recipes

**Web service behind an Ingress with health checks, autoscaling and a PodDisruptionBudget**

```yaml
applicationName: shop-api

deployment:
  image: { repository: registry.example.com/shop/api, tag: 2.3.0 }
  ports: [{ name: http, containerPort: 8080, protocol: TCP }]
  resources:
    requests: { cpu: 200m, memory: 256Mi }
    limits: { memory: 512Mi }
  readinessProbe: { enabled: true, httpGet: { path: /ready, port: http } }
  livenessProbe:  { enabled: true, httpGet: { path: /healthz, port: http } }

service:
  ports: [{ name: http, port: 80, targetPort: http, protocol: TCP }]

ingress:
  enabled: true
  ingressClassName: nginx
  hosts:
    - host: shop.example.com
      paths: [{ path: /, pathType: Prefix, servicePort: http }]

autoscaling: { enabled: true, minReplicas: 2, maxReplicas: 8 }
pdb: { enabled: true, minAvailable: 1 }
```

**Worker without HTTP** — disable the Service:

```yaml
applicationName: queue-worker
deployment:
  image: { repository: registry.example.com/shop/worker, tag: 2.3.0 }
service:
  enabled: false
```

**Only a scheduled task** — disable the Deployment and the Service:

```yaml
applicationName: nightly-report
deployment: { enabled: false }
service: { enabled: false }
cronJob:
  enabled: true
  jobs:
    report:
      schedule: "0 1 * * *"
      image: { repository: registry.example.com/shop/report, tag: 1.0.0 }
```


## Reference: what each section renders

| Values key | Rendered resource | Requires |
| --- | --- | --- |
| `deployment` | Deployment | |
| `service` | Service | |
| `ingress` | Ingress | |
| `httpRoute` | HTTPRoute | Gateway API CRDs (fails if missing) |
| `route` | OpenShift Route | `route.openshift.io/v1` |
| `persistence` | PersistentVolumeClaim | |
| `configMap` | ConfigMap per `files` entry | |
| `secret` | Secret per `files` entry | |
| `externalSecret` | ExternalSecret per `files` entry | External Secrets Operator |
| `sealedSecret` | SealedSecret per `files` entry | `bitnami.com/v1alpha1` |
| `secretProviderClass` | SecretProviderClass | Secrets Store CSI driver |
| `rbac` | ServiceAccount, Role, RoleBinding | |
| `cronJob` / `job` | CronJob / Job per `jobs` entry | |
| `autoscaling` | HorizontalPodAutoscaler | |
| `vpa` | VerticalPodAutoscaler | VPA CRDs (fails if missing) |
| `pdb` | PodDisruptionBudget | |
| `networkPolicy` | NetworkPolicy | |
| `serviceMonitor` | ServiceMonitor | Prometheus Operator |
| `prometheusRule` | PrometheusRule | Prometheus Operator |
| `alertmanagerConfig` | AlertmanagerConfig | Prometheus Operator |
| `grafanaDashboard` | GrafanaDashboard per `contents` entry | Grafana Operator |
| `certificate` | Certificate | cert-manager |
| `backup` | Backup | Velero |
| `forecastle` / `endpointMonitor` | ForecastleApp / EndpointMonitor | Stakater operators |
| `extraObjects` | Anything you provide | |

CRD based resources are silently skipped when the cluster does not advertise the CRD (during
`helm template` pass `--api-versions` to render them, see [Install, upgrade and debug](#install-upgrade-and-debug)).
`vpa` and `httpRoute` fail loudly instead.

## Naming, labels and namespace

- All resources are named after `applicationName`; helper resources add a suffix
  (`-data`, `-svc-monitor`, `-certificate`, `-backup`, `-role-<name>`, …). Job and CronJob names are the map keys.
- Every resource gets the standard labels: `app.kubernetes.io/name`, `app.kubernetes.io/instance`,
  `app.kubernetes.io/version` (from `deployment.image.tag`), `app.kubernetes.io/managed-by`,
  `app.kubernetes.io/part-of`, optionally `app.kubernetes.io/component`, and `helm.sh/chart`.
- Pods and the Service selector use only `app.kubernetes.io/name` and
  `application.stakater.com/workload-class`. Selector labels are immutable, so do not change `applicationName`
  on a running release.
- Resources are created in the release namespace (`-n`), unless `namespaceOverride` is set.

## Templating inside values (`tpl`)

Values documented as `tpl` in [`values.yaml`](values.yaml) are rendered by Helm, so they may contain
Go-template expressions. Always quote them in YAML:

```yaml
deployment:
  image:
    repository: '{{ .Values.global.registry }}/my-app'   # your own values are reachable too
ingress:
  hosts:
    - host: '{{ .Release.Name }}.{{ .Release.Namespace }}.example.com'
```

Available helpers: `{{ include "application.name" . }}` and `{{ include "application.namespace" . }}`.
Inside `range` blocks use `$` instead of `.` (for example `$.Values`).

## Install, upgrade and debug

```bash
# render locally and inspect the output
helm template my-app . -f my-values.yaml

# CRD based resources are only rendered when the API is known: advertise it explicitly
helm template my-app . -f my-values.yaml \
  --api-versions monitoring.coreos.com/v1 \
  --api-versions cert-manager.io/v1

# validate and dry-run against a cluster
helm lint . -f my-values.yaml
helm upgrade --install my-app . -n my-namespace -f my-values.yaml --dry-run --debug

# install / upgrade / roll back / remove
helm upgrade --install my-app . -n my-namespace -f my-values.yaml
helm rollback my-app 1 -n my-namespace
helm uninstall my-app -n my-namespace
```

Common errors:

| Message | Cause |
| --- | --- |
| `Undefined image for application container` | `deployment.image.repository` is empty. |
| `Undefined image repo for container '<name>'` | A Job / CronJob entry has no `image.repository`. |
| `Specify paths for ingress host, check values.yaml` | An `ingress.hosts` entry has no `paths`. |
| `Data or dataFrom not specified for ExternalSecret …` | An `externalSecret.files` entry has neither `data` nor `dataFrom`. |
| `There is no VerticalPodAutoscaler resource definition…` | `vpa.enabled` is true but the CRD is not installed / advertised. |
| A CRD resource is missing from the output | The cluster (or `--api-versions`) does not advertise that API. |

## Development and tests

```
Chart.yaml        chart metadata
values.yaml       all values with documentation
values-test.yaml  example values that enable (almost) everything
templates/        manifests and helpers (_helpers.tpl, _jobpod.tpl)
tests/            helm-unittest suites
```

```bash
helm lint .
helm plugin install https://github.com/helm-unittest/helm-unittest
helm unittest .
helm template my-app . -f values-test.yaml
```

When adding a template, reuse the helpers instead of copying boilerplate:

- `application.metadata` – name, namespace, merged labels and annotations
- `application.podLabels`, `application.selectorLabels`
- `application.image` – `repository[:tag][@digest]`
- `application.probe`, `application.env`
- `application.tplvalues.render` – render a string or object through `tpl`

and add a suite under `tests/` for every new behaviour.
