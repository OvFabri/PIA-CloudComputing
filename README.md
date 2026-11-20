# PIA-CloudComputing
Piloto de entrega continua de MediSur. El [reparto](Repartición.md) y la [bitácora](AVANCES.md) describen el alcance de cada parte. El estado real de Azure está en [`docs/ESTADO-AZURE.md`](docs/ESTADO-AZURE.md); esa página prevalece sobre los pasos de preparación históricos de esta guía.

La infraestructura ya está desplegada parcialmente. Sigue el [guion actualizado de demostración en la nube](docs/DEMO-CLOUD.md) para completar credenciales, pipeline, aplicación, capturas y cierre de costos.

## Aplicación y pruebas

Desde la raíz, con Bun 1.4.3:

```bash
bun test
APP_HOST=127.0.0.1 APP_PORT=8080 \
APP_VERSION=1.0.0 APP_COMMIT_SHA="$(git rev-parse HEAD)" \
APP_BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" bun app/server.js
```

Las cinco variables son obligatorias. El servicio ofrece `GET /health`, `GET /ready`, `GET /version`, `GET /metrics`, `GET /api/items` y `POST /api/items`. Para crear un ítem, enviar JSON como `{"name":"vendas"}`. Los registros viven en la memoria de cada réplica.

`bun test` exige un mínimo de 60 % y genera `coverage/lcov.info`. Configurar SonarQube con `sonar.sources=app`, `sonar.tests=tests` y `sonar.javascript.lcov.reportPaths=coverage/lcov.info`. Las métricas se recogen por réplica en `/metrics`. El contador `http_requests_total` incluye `method`, `route`, `status` y `version`. El histograma `http_request_duration_seconds` mide latencia en segundos.

## Construir y verificar la imagen

El script empaqueta el commit actual de Git e inyecta su SHA completo y la fecha UTC. La etiqueta usa versión y los primeros siete caracteres del SHA. Ejecutarlo después de guardar el Dockerfile en un commit.

```bash
bash scripts/build-image.sh 1.0.0
imagen="ghcr.io/ovfabri/pia-cloudcomputing:1.0.0-$(git rev-parse HEAD | cut -c 1-7)"
docker image inspect "$imagen" --format '{{.Config.User}} {{index .Config.Labels "org.opencontainers.image.revision"}}'
docker run --rm --entrypoint /bin/sh "$imagen" -ec '
  test "$(id -u)" = 10001
  for tool in bun gcc cc make; do ! command -v "$tool" || exit 1; done
'
docker run --rm -p 127.0.0.1:8080:8080 "$imagen"
```

En otra terminal, confirmar `200` en ambas sondas y comparar el SHA de `/version` con `git rev-parse HEAD`.

```bash
curl -fsS http://127.0.0.1:8080/health
curl -fsS http://127.0.0.1:8080/ready
curl -fsS http://127.0.0.1:8080/version
```

## Publicación y ramas

La consigna pide proteger `main` y usar ramas de funcionalidad con PR. La protección que exige PR y revisión cambia cómo se integran los siguientes avances. Configurarla en GitHub cuando el equipo adopte ese flujo. Cuando Jenkins reporte estados, agregar su comprobación como requisito de fusión.

Para publicar la imagen inicial, autenticar Docker en GHCR con un token clásico con `write:packages`. En Jenkins, guardar la credencial en Jenkins Credentials y pasarla por entrada estándar a `docker login`. Publicar solo la etiqueta generada y comprobar que el paquete esté privado y vinculado al repositorio. Kubernetes necesitará una credencial de lectura para descargarlo.

```bash
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
docker push "$imagen"
docker buildx imagetools inspect "$imagen"
```

En el flujo final, Jenkins construye y publica después del Quality Gate. El Deployment debe usar la etiqueta exacta publicada y conservar los metadatos de la imagen.

## Jenkins y SonarQube · integración con el frente 3

El [Jenkinsfile](Jenkinsfile) usa un trabajo **Multibranch Pipeline**. Cada revisión descubierta ejecuta pruebas y archiva LCOV. `main` y `demo/quality-gate` analizan en proyectos SonarQube separados para usar Community Build. Solo `main` puede construir y publicar después de una puerta verde.

### Configuración en VM-TOOLS

1. Instalar los plugins Pipeline, GitHub Branch Source, Credentials Binding y SonarQube Scanner. Configurar un agente con etiqueta `medisur-ci`, Git, Bash, Bun 1.4.3 en el PATH del agente y acceso al daemon de Docker desde la cuenta que ejecuta el agente.
2. Crear un **Multibranch Pipeline** con GitHub como origen y `Jenkinsfile` como ruta. Darle acceso de lectura al repositorio con la credencial del origen. Descubrir ramas del repositorio del equipo y excluir forks. Las ramas que ejecutan código en ese agente deben pertenecer a colaboradores de confianza, porque el agente tiene acceso a Docker y el trabajo puede usar credenciales.
3. Conectar el webhook de GitHub a `https://<jenkins>/github-webhook/` para eventos de push. La URL debe ser alcanzable desde GitHub. Hacer una indexación inicial y después verificar que un push nuevo arranca una ejecución por sí solo.
4. Crear en SonarQube Community Build los proyectos locales `medisur` y `medisur-demo`. Asignar al principal una puerta que exija cobertura total de al menos 60 % y mantenga las comprobaciones de calidad y seguridad. En Jenkins, agregar el servidor con nombre `SonarQube` y una credencial Secret text con permiso de análisis de ambos proyectos. Agregar la herramienta CLI con nombre `SonarScanner`.
5. Configurar en SonarQube un webhook hacia `https://<jenkins>/sonarqube-webhook/`. Guardar el mismo secreto de ese webhook en Jenkins como Secret text con ID `sonar-webhook`. Verificar que SonarQube pueda alcanzar Jenkins.
6. Agregar en Jenkins una credencial de tipo Username with password con ID `ghcr-publisher`. Usar la cuenta autorizada para publicar y su token clásico con `write:packages`. La sesión temporal utilizada para publicar desde la laptop es independiente.

### Verificación para la entrega

1. Empujar una revisión de prueba en una rama interna y verificar el arranque por webhook, el SHA del checkout, las pruebas y el artefacto `coverage/lcov.info`.
2. Usar `demo/quality-gate` para un ensayo aislado. Ejecutar primero una línea base con la puerta normal. En `medisur-demo`, asociar temporalmente una puerta con un umbral de cobertura total superior a la cobertura observada. Empujar otro commit con pruebas verdes. Capturar el resultado rojo de SonarQube y el fallo de la etapa `Quality Gate`. Restaurar la puerta de demostración y repetir para confirmar que el gate cambia a verde.
3. En `main`, confirmar que Jenkins importa LCOV, la puerta pasa y se publica una etiqueta nueva `versión-SHA`. Para probar el bloqueo específico de publicación, capturar también una ejecución controlada de `main` con el gate rojo, verificando que los pasos de construcción y publicación queden omitidos por el fallo. Coordinar el cambio de umbral con el equipo y restaurarlo al terminar el ensayo.
4. Guardar evidencia del webhook y de las ejecuciones roja y verde. El frente de Kubernetes añadirá despliegue, smoke test y rollback después de la publicación.

[Pipeline declarativo de Jenkins](https://www.jenkins.io/doc/book/pipeline/syntax/) · [Puerta de calidad en Jenkins](https://docs.sonarsource.com/sonarqube-server/2026.1/analyzing-source-code/ci-integration/jenkins-integration/pipeline-pause)

## Kubernetes y entrega continua

La carpeta [`kubernetes/`](kubernetes/) contiene la base de despliegue: namespace, ConfigMap, Deployment con dos réplicas y sondas, Service ClusterIP, Ingress y PodDisruptionBudget. El destino GHCR es `ghcr.io/ovfabri/pia-cloudcomputing`. Jenkins cambia el Deployment a la etiqueta inmutable creada para cada commit, espera el rollout y ejecuta una prueba de humo contra `/health` y `/version`. Si la actualización o el smoke test fallan, el stage intenta `kubectl rollout undo` y termina en rojo.

La guía del trabajo requiere **dos VMs separadas** en Azure y Ubuntu Server 22.04 LTS: VM-TOOLS B4ms (4 vCPU, 16 GB RAM) y VM-K8S B2ms (2 vCPU, 8 GB RAM), cada una con SSD estándar de 64 GB. La VM anterior `kuber` (D2s_v4, Ubuntu 24.04) no sustituye por sí sola ninguna de las dos especificaciones.

### Revisión previa de Azure

Antes de aprovisionar, inicia sesión con Azure CLI y ejecuta este chequeo de solo lectura para la región elegida:

```bash
az login
bash scripts/cloud-preflight.sh westus
```

El par requiere 6 vCPU de la familia B y 6 vCPU regionales disponibles, además de una suscripción que permita escrituras. El script muestra las restricciones de región, tamaños, cuotas y VMs existentes; **no crea ni modifica recursos**. Que un SKU aparezca en la lista no garantiza capacidad física en ese momento. No continúes al aprovisionamiento hasta confirmar el crédito o presupuesto aprobado y que la suscripción no esté bloqueada para escrituras.

### Preparación de VM-K8S

1. Instala MicroK8s en la VM-K8S aprobada, activa su addon `ingress` (`microk8s enable ingress`) y confirma que el API de Kubernetes responde por la red privada de Azure en TCP 16443.
2. En el clúster, crea el namespace y un secreto local de lectura de GHCR. No guardes el token ni el Secret resultante en Git:

   ```bash
   kubectl apply -f kubernetes/namespace.yaml
   bash scripts/create-ghcr-pull-secret.sh medisur
   kubectl apply -k kubernetes/
   kubectl apply -f kubernetes/jenkins-rbac.yaml
   ```

   El token de GHCR debe tener solo lectura de paquetes para el clúster.
3. Para el primer despliegue, confirma que los dos Pods quedan listos y que el servicio responde en `http://<IP-pública-de-VM-K8S>/health`. Permite TCP 80 solo desde los rangos que vayan a usar la demo; configura TLS antes de habilitar tráfico público por 443.
4. Aplica [`monitoring/kubernetes/kube-state-metrics.yaml`](monitoring/kubernetes/kube-state-metrics.yaml), [`monitoring/kubernetes/node-exporter.yaml`](monitoring/kubernetes/node-exporter.yaml) y [`monitoring/kubernetes/prometheus-scraper-rbac.yaml`](monitoring/kubernetes/prometheus-scraper-rbac.yaml). kube-state-metrics expone 30081 y node_exporter escucha en 9100. Restringe 30081, 9100 y el API de Kubernetes (16443) en el NSG para que solo VM-TOOLS los alcance por la red privada.
5. En VM-K8S, confirma que el certificado del servidor de API incluye su IP privada en SAN. Genera credenciales de solo lectura para que Prometheus descubra y scrapee `/metrics` de cada Pod individualmente. Copia esos dos archivos mediante un canal seguro al directorio `monitoring/prometheus/secrets/` de VM-TOOLS; no los agregues a Git. Reemplaza las dos ocurrencias de `REEMPLAZAR_IP_PRIVADA_VM_K8S` en `prometheus.yml` por la IP privada real.

   ```bash
   bash scripts/create-prometheus-k8s-credentials.sh /tmp/medisur-prometheus-secrets
   ```

6. Genera un kubeconfig con permisos acotados para Jenkins y súbelo en **Manage Jenkins → Credentials** como credencial de tipo Secret file con ID `k8s-kubeconfig`:

   ```bash
   bash scripts/create-jenkins-kubeconfig.sh /tmp/medisur-jenkins-kubeconfig
   ```

   El script solicita 30 días al clúster e imprime la fecha de vencimiento que este realmente devuelve; rótalo y actualiza la credencial antes de esa fecha. No publiques el archivo ni lo copies al repo. El pipeline necesita `kubectl` en el agente `medisur-ci` y conectividad privada desde VM-TOOLS a VM-K8S. La cuenta solo puede leer Pods, ReplicaSets, Services y Nodes y actualizar el Deployment de MediSur.

El Ingress publica HTTP en el puerto 80 del nodo y enruta hacia el Service ClusterIP. Las métricas no se exponen por un NodePort: Prometheus las obtiene individualmente por el proxy autenticado del API de Kubernetes, evitando que el balanceo del Service mezcle las dos réplicas.

## Prometheus, Grafana y alertas

La carpeta [`monitoring/`](monitoring/) contiene Prometheus con retención de 15 días, Alertmanager, node_exporter, configuración de Grafana, dos tableros provisionados y tres reglas de alerta. Las versiones están fijadas en [`docker-compose.yml`](monitoring/docker-compose.yml). En VM-K8S se despliegan los exporters del clúster; en VM-TOOLS se ejecuta node_exporter junto a Prometheus y Grafana.

Antes de arrancar el stack:

1. En `monitoring/prometheus/targets/node-exporters.yml`, agrega las IP privadas reales de VM-TOOLS y VM-K8S con puerto `9100`.
2. En `monitoring/prometheus/targets/kubernetes.yml`, agrega la IP privada de VM-K8S con puerto `30081` para kube-state-metrics. La configuración de la API descubre cada Pod por separado.
3. Copia `.env.example` a `.env`, cambia la contraseña de Grafana y configura los datos de SMTP y el correo que recibirá alertas. Mantén `.env` fuera de Git.
4. Crea la contraseña SMTP fuera del repositorio y genera la configuración local de Alertmanager:

   ```bash
   cd monitoring
   cp .env.example .env
   # Editar .env y completar correo y servidor SMTP
   sudo apt-get install gettext-base
   bash scripts/configure-alertmanager.sh
   docker compose up -d
   ```

5. Los puertos 3000 y 9090 se enlazan a `127.0.0.1`. Desde la laptop, abre un túnel SSH a VM-TOOLS (`ssh -L 3000:127.0.0.1:3000 usuario@<IP-VM-TOOLS>`) y visita `http://localhost:3000`. No expongas Grafana ni Prometheus directamente a Internet.

Para que el tablero de aplicación muestre series durante la demo, genera tráfico sintético desde la laptop hacia VM-K8S. El script solo hace `GET`, tiene límites de duración y tasa, y consulta una ruta inexistente para producir respuestas 404; no crea datos ni requiere paquetes adicionales:

```bash
bun scripts/generate-demo-traffic.js http://<IP-pública-VM-K8S> 60 2
```

Después espera al menos un intervalo de scrape y abre Grafana por el túnel SSH. Esto produce tráfico para las métricas de MediSur; no simula alertas de disco ni reemplaza una prueba real de reinicio/indisponibilidad.

Las reglas incluidas alertan si el disco supera 80 % durante cinco minutos, si un contenedor de MediSur supera tres reinicios en diez minutos o si las réplicas disponibles quedan por debajo de las deseadas durante cinco minutos. El tablero de aplicación presenta las solicitudes y límites de CPU/memoria declarados en Kubernetes; no son consumo medido del contenedor. Si el equipo añade consumo real por Pod, debe documentar y habilitar una fuente compatible con cAdvisor/kubelet. Los tableros requieren tráfico y series scrapeadas; verifica que los targets aparezcan `UP` antes de capturar evidencia. La entrega y recepción de correo también requiere configurar un SMTP real y comprobar la notificación desde Alertmanager.

## Control de costos en Azure

- Configura una alerta de presupuesto de **50 USD** y apagado automático diario para las dos VMs. La alerta notifica el consumo, pero no detiene recursos.
- Al terminar una sesión, detén/desasigna cada VM desde el portal o ejecuta `az vm deallocate`; confirma `VM deallocated` en Azure antes de cerrar la sesión.
- Los discos, la IP pública y otros recursos asociados pueden seguir generando cargos mientras las VMs están desasignadas. Al acabar el PIA, revisa y elimina el grupo de recursos completo después de guardar la evidencia necesaria.
- Registra el consumo real del crédito y la fecha de cada evidencia para la sección de costos del documento Word.

### Ensayo del despliegue y reversión

Después de que el equipo de CI configure Jenkins, SonarQube y los webhooks, un push aprobado a `main` debe desplegar la imagen automáticamente. Para la demo de rollback, guarda la imagen en uso, despliega una versión anterior a propósito y ejecuta:

```bash
kubectl -n medisur rollout undo deployment/medisur-api
kubectl -n medisur rollout status deployment/medisur-api
kubectl -n medisur get pods -w
```

La prueba de humo automática está en [`scripts/smoke-test.js`](scripts/smoke-test.js); requiere Bun en el agente de Jenkins y valida tanto HTTP 200 como el SHA y la versión esperados.
