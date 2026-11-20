# Guion de demostración en la nube · MediSur

Este guion separa lo que ya fue verificado en Azure de la demostración final que depende de credenciales de GitHub, configuración web de Jenkins y acceso SMTP. El [estado verificado](ESTADO-AZURE.md) es la fuente para el avance actual. No muestres contraseñas, PAT, kubeconfig ni saldos personales durante la presentación.

## Infraestructura actual

Antes de ejecutar los ejemplos, sustituye `JENKINS_HOST`, `K8S_PUBLIC_IP` y `TOOLS_PUBLIC_IP` por los valores vigentes de tu despliegue; no publiques direcciones ni credenciales personales.

- Tools: `vm-tools`, Ubuntu 22.04, `Standard_B4s_v2` (4 vCPU, 16 GiB), 64 GB Standard SSD; Jenkins con HTTPS en `https://JENKINS_HOST`, SonarQube, Docker, Prometheus, Grafana, Alertmanager y node-exporter.
- Kubernetes: `vm-k8s`, Ubuntu 22.04, `Standard_B2s_v2` (2 vCPU, 8 GiB), 64 GB Standard SSD; MicroK8s 1.36.2, Ingress, node-exporter y kube-state-metrics.
- El presupuesto de 50 USD es solo notificación. No hay apagado automático compatible con esta región; desasigna ambas VMs al terminar una sesión.
- Los SKU `B4s_v2`/`B2s_v2` coinciden en CPU y memoria con la especificación, pero no son `B4ms`/`B2ms`. Explica que fueron una sustitución por capacidad y confirma que el docente acepta la equivalencia.

## Configuración pendiente antes de presentar

1. Completa el asistente de Jenkins, instala plugins sugeridos y crea la cuenta administradora.
2. Crea dos proyectos SonarQube (`medisur` y `medisur-demo`), configura el Quality Gate de 60 %, genera el token de análisis y configura el webhook hacia Jenkins.
3. Crea en GitHub un PAT clásico con `read:packages` y `write:packages`, pero no lo compartas por chat. Ejecuta desde la raíz del repo `bash scripts/deploy-to-azure.sh`; el comando oculta el token y crea el secreto de lectura de Kubernetes. El paquete debe ser accesible a la identidad del token.
4. Crea las credenciales Jenkins `ghcr-publisher` (usuario/token), `k8s-kubeconfig` (Secret file local `~/.config/medisur-secrets/jenkins-kubeconfig`), y `sonar-webhook` (Secret text). Configura el servidor SonarQube con el nombre `SonarQube` y SonarScanner con el nombre `SonarScanner`.
5. Crea un Multibranch Pipeline apuntando al repositorio `OvFabri/PIA-CloudComputing`. Configura el webhook de GitHub para `https://JENKINS_HOST/github-webhook/`. Descubre ramas confiables y no ejecutes código de forks no confiables en el agente que tiene acceso a Docker y a las credenciales.
6. En Jenkins, verifica la etiqueta `k8s-kubeconfig` y que el token expire según la fecha indicada al crearlo. Rótalo antes de su vencimiento.
7. Para recibir alertas por correo, proporciona credenciales SMTP fuera de Git, configura `monitoring/alertmanager/alertmanager.yml` localmente y confirma recepción. Alertmanager está activo, pero no tiene integración de entrega configurada.

## Secuencia de presentación

### 1. Estado inicial

```bash
curl -fsS http://K8S_PUBLIC_IP/health
curl -fsS http://K8S_PUBLIC_IP/ready
curl -fsS http://K8S_PUBLIC_IP/version
ssh azureuser@K8S_PUBLIC_IP 'microk8s kubectl -n medisur get deployment,pods,service,ingress'
```

Debe mostrar dos réplicas listas, la versión y el SHA de la imagen publicada.

### 2. Quality Gate rojo y verde

Usa `demo/quality-gate` y el proyecto SonarQube `medisur-demo`. Confirma una ejecución de referencia; cambia temporalmente el umbral por encima de la cobertura medida para que el gate falle antes de construir/publicar; guarda captura. Restaura el umbral acordado (mínimo 60 %), vuelve a ejecutar y guarda captura del gate verde. No cambies el gate del proyecto de `main` para simular el fallo.

### 3. Pipeline y publicación

Haz push de un commit aprobado a `main`. Muestra que el webhook inicia el pipeline, pasan `bun test` y SonarQube, GHCR recibe una imagen etiquetada con versión y SHA, y el Deployment actualiza dos Pods.

```bash
ssh azureuser@K8S_PUBLIC_IP 'microk8s kubectl -n medisur rollout status deployment/medisur-api'
curl -fsS http://K8S_PUBLIC_IP/version
```

Guarda URL/número de build, SHA, etiqueta/digest y salida de las sondas.

### 4. Auto-recuperación y rollback

Elimina un Pod y muestra que el Deployment crea el reemplazo:

```bash
ssh azureuser@K8S_PUBLIC_IP 'pod=$(microk8s kubectl -n medisur get pods -l app.kubernetes.io/name=medisur-api -o jsonpath="{.items[0].metadata.name}"); microk8s kubectl -n medisur delete pod "$pod"; microk8s kubectl -n medisur get pods -w'
```

Detén el seguimiento con `Ctrl+C` después de ver los dos Pods listos. Después demuestra reversión y comprueba `/version`:

```bash
ssh azureuser@K8S_PUBLIC_IP 'microk8s kubectl -n medisur rollout undo deployment/medisur-api && microk8s kubectl -n medisur rollout status deployment/medisur-api'
curl -fsS http://K8S_PUBLIC_IP/version
```

### 5. Métricas y alertas

Desde una terminal local crea un túnel SSH para Grafana, Prometheus y SonarQube:

```bash
ssh -N -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 9000:127.0.0.1:9000 azureuser@TOOLS_PUBLIC_IP
```

Abre `http://localhost:3000`, `http://localhost:9090/targets` y `http://localhost:9000`. La contraseña de Grafana se encuentra localmente en `~/.config/medisur-secrets/grafana-admin-password`; nunca la incluyas en capturas.

Cuando la API esté en ejecución, genera tráfico sintético, de tasa limitada:

```bash
bun scripts/generate-demo-traffic.js http://K8S_PUBLIC_IP 60 2
```

Presenta los dashboards “MediSur · Aplicación” y “MediSur · Infraestructura”. Explica cada alerta y solo afirma recepción de correo si se configuró SMTP y se probó. Captura el estado `UP` de todos los targets y las alertas disparadas durante pruebas controladas.

## Control de costos al cerrar

Guarda evidencia primero; luego desasigna las VMs desde la terminal y confirma el estado:

```bash
az vm deallocate -g rg-pia-cloud-demo-cl -n vm-tools
az vm deallocate -g rg-pia-cloud-demo-cl -n vm-k8s
az vm list -d -g rg-pia-cloud-demo-cl --query '[].{name:name,state:powerState}' -o table
```

Discos y otros recursos podrían seguir facturándose aunque la VM esté desasignada. Revisa el costo del crédito y el presupuesto en Azure; el presupuesto solo avisa, no bloquea cargos.
