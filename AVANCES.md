# Avances del PIA · MediSur

> **Actualización (20 nov 2026):** consulta [`docs/ESTADO-AZURE.md`](docs/ESTADO-AZURE.md) para el estado comprobado. El asistente y el pipeline multibranch de Jenkins ya están configurados. El build #5 ejecutó pruebas, análisis y construcción de imagen, pero GHCR rechazó el push al paquete del repositorio original por permisos `write_package`. Se creó el fork [`OvFabri/PIA-CloudComputing`](https://github.com/OvFabri/PIA-CloudComputing); queda configurar Jenkins y GHCR para ese destino, publicar la imagen y completar el despliegue. Las primeras secciones conservan el historial anterior.

## Parte 1 · Aplicación

**Aplicación piloto · API, variables de entorno, versión, métricas y pruebas**

### Avances de la aplicación

1. Revisé la consigna y el reparto del equipo. Definí los contratos que la aplicación entrega a quienes preparan la imagen, el pipeline, Kubernetes y el monitoreo.
2. Implementé la API en JavaScript con Bun 1.4.3. La consigna deja libre el lenguaje. El plan inicial planteaba Python, pero el entorno bloqueó la descarga de sus dependencias y Bun permitió completar el servicio y su verificación sin paquetes externos.
3. Agregué `GET /health` y `GET /ready` para vitalidad y disponibilidad. Agregué `GET /api/items` para listar e `POST /api/items` para crear un registro y validar su nombre. Los datos de ejemplo viven en memoria, separados por réplica, y se pierden al reiniciar.
4. Configuré el host y el puerto mediante `APP_HOST` y `APP_PORT`. `GET /version` devuelve la versión, el SHA y la fecha de construcción que recibe por `APP_VERSION`, `APP_COMMIT_SHA` y `APP_BUILD_DATE`.
5. Implementé `GET /metrics` con un contador por ruta y código de respuesta y un histograma de duración en segundos. Las series incluyen un identificador de versión para relacionarlas con los despliegues.
6. Ejecuté `bun test` en esta carpeta y en una copia limpia. Pasaron 13 pruebas, incluidas seis unitarias. Bun mostró 93.94 % de cobertura de líneas y 100 % de funciones en su resumen, por encima del mínimo de 60 %. El comando regenera `coverage/lcov.info`.
7. Comprobé las seis rutas mediante peticiones directas al manejador. El entorno bloqueó la escucha en un puerto, por lo que la verificación por red con `curl` queda pendiente. Guardé las [respuestas](evidencias/respuestas.txt) y la [salida de las pruebas](evidencias/pruebas.txt).

### Cierre del plan de Aplicación

| Paso del plan | Resultado verificado |
| --- | --- |
| 1. Contrato | Seis rutas, cinco variables de entorno, puerto y formato de métricas documentados. |
| 2. Arranque local | Bun 1.4.3, sin dependencias externas. Arranque y validación del puerto verificados. |
| 3. Sondas e ítems | Vitalidad y disponibilidad verificadas. Creación, listado y rechazo de entradas inválidas cubiertos por pruebas. |
| 4. Identidad del build | `/version` devuelve versión, SHA y fecha inyectados, comprobados por HTTP en el contenedor. |
| 5. Métricas | Contador por ruta y estado, histograma de latencia y etiqueta de versión. Series comprobadas tras generar tráfico. |
| 6. Pruebas y cobertura | 13 pruebas aprobadas, incluidas seis unitarias. Bun reportó 93.94 % de líneas, por encima del 60 % requerido. `bun test` regenera `coverage/lcov.info`. |
| 7. Evidencias y entrega | Código de aplicación publicado en el repo. [README](README.md), [resultado de pruebas](evidencias/pruebas.txt) y [evidencia HTTP en Docker](evidencias/docker-local.txt) disponibles para el equipo. |

La aplicación está lista para integrar. Las verificaciones en Jenkins, Kubernetes y Grafana corresponden a los responsables de esos frentes.

### Archivos para continuar

| Archivo | Contenido |
| --- | --- |
| [app/api.js](app/api.js) | Rutas, validación y lectura de configuración. |
| [app/server.js](app/server.js) | Arranque y cierre del servicio HTTP. |
| [app/metrics.js](app/metrics.js) | Contador e histograma en formato Prometheus. |
| [tests/app.test.js](tests/app.test.js) y [bunfig.toml](bunfig.toml) | Pruebas, umbral y configuración del reporte LCOV. |
| [README.md](README.md) | Comandos de arranque y prueba, contrato de integración y aporte al Word con declaración de IA. |

### Entrega a los demás frentes

| Frente | Siguiente paso con la aplicación |
| --- | --- |
| **2. Repositorio e imagen** | Empaquetar con Bun 1.4.3 y arrancar con `bun app/server.js`. Inyectar versión, SHA y fecha al construir la imagen. |
| **3. CI y calidad** | Ejecutar `bun test` desde la raíz y comprobar que SonarQube importa `coverage/lcov.info` con `sonar.javascript.lcov.reportPaths`. El reporte se genera en cada ejecución. |
| **4. Kubernetes y entrega** | Configurar las sondas en `/health` y `/ready` y comprobar que `/version` cambia tras el despliegue y recupera el SHA anterior tras el rollback. |
| **5. Infraestructura y monitoreo** | Recoger `/metrics` de ambas réplicas y conectar el contador y el histograma con los paneles de Grafana. |

## Parte 2 · Repositorio e imagen

**Repositorio e imagen · ramas, Docker y GHCR**

1. El trabajo de repositorio e imagen se subió a `main` en el commit `8248ffb`.
2. Agregué un [Dockerfile multietapa](Dockerfile). La etapa de build compila el servicio con Bun 1.4.3. La etapa final copia el ejecutable a Debian slim y configura el usuario `10001:10001`, el puerto 8080 y los metadatos de construcción. El [filtro del contexto](.dockerignore) permite el Dockerfile y el código necesario para compilar.
3. Agregué [el comando de construcción](scripts/build-image.sh). Empaqueta el árbol del commit exacto, genera la fecha UTC y etiqueta para GHCR con versión y SHA corto. Rechaza `latest` como versión. Verifiqué con un Docker simulado los argumentos y que el contexto excluye los cambios locales. Jenkins podrá invocarlo al pasar la puerta de calidad.
4. Compilé el ejecutable en el host y verifiqué las seis rutas por HTTP con `curl`, además de la coincidencia del SHA y el cierre con `SIGTERM`. Guardé la [salida de la prueba](evidencias/binario-http.txt). Esa prueba cubrió el ejecutable compilado. La imagen completa requiere acceso al daemon de Docker.
5. Dejé en el [README](README.md) los pasos de verificación del usuario del contenedor, metadatos, publicación privada y protección de `main`.

**Uso de IA.** Codex preparó la receta de empaquetado, el script y la documentación. Se usó para reducir pasos manuales y probar que los metadatos coinciden con el commit. Se ajustó la verificación para ejecutar el binario por HTTP cuando Docker no estuvo accesible.

**Verificación posterior en Docker.** Construí `medisur:prueba-local` con el Dockerfile multietapa y ejecuté la imagen. Comprobé que corre con UID y GID 10001 y que la etapa final carece de `bun`, `gcc`, `cc` y `make`. Validé las seis rutas por HTTP, incluidos los tres metadatos de build y las métricas después de crear un ítem. La [evidencia de Docker](evidencias/docker-local.txt) corresponde a una etiqueta de prueba local. Después se construyó y publicó la imagen desde el commit `8248ffb`.

**Publicación en GHCR.** Se publicó `ghcr.io/distortr/pia-cloudcomputing:1.0.0-8248ffb`. La descarga autenticada devolvió el mismo digest que la publicación, `sha256:cd61a4566c64313abcd6f659e829eae812e544c6d5a4988ca963f2981f6fabc0`. El titular de la cuenta confirmó que el paquete aparece como privado en GitHub. Usar la etiqueta `1.0.0-8248ffb` en el despliegue.

**Pendiente.** Configurar la protección de `main` y el flujo de PR con el equipo.

## Parte 3 · CI y calidad

1. Agregué el [Jenkinsfile](Jenkinsfile) con checkout del commit, pruebas Bun, archivo de cobertura, análisis SonarQube y Quality Gate bloqueante con tiempo límite. Después de una puerta verde, el pipeline de `main` construye y publica en GHCR con una credencial de Jenkins.
2. Configuré [SonarQube](sonar-project.properties) para medir el código de `app/` e importar `coverage/lcov.info`. La rama de ensayo `demo/quality-gate` usa un proyecto SonarQube separado para preservar la línea base de `main`.
3. Ejecuté el bloque de pruebas del Jenkinsfile en una copia limpia. Pasaron 13 pruebas y Bun reportó 93.94 % de cobertura de líneas. Inyecté una prueba fallida en una copia temporal y confirmé que el bloque terminó con código distinto de cero. Revisé la sintaxis de los bloques shell, el orden de las etapas y la condición de publicación. El validador declarativo de un Jenkins temporal confirmó `Jenkinsfile successfully validated.`
4. Probé SonarQube Community Build en local con el reporte LCOV real. SonarQube midió 97.0 % y devolvió puerta roja con un umbral de 100 %, luego puerta verde con 60 %. Guardé la [evidencia local](evidencias/sonarqube-local.txt).
5. La ejecución integrada requiere configurar Jenkins, SonarQube y ambos webhooks en VM-TOOLS. Allí se deben capturar el disparo automático, la importación de cobertura, el gate rojo y el build verde publicado por Jenkins. El [README](README.md) registra la configuración y el procedimiento de prueba.

**Uso de IA.** Codex elaboró el pipeline y la documentación de integración. Los proyectos SonarQube separados mantienen el análisis de demostración aislado en Community Build. La verificación local incluyó un fallo controlado de pruebas. La respuesta real de SonarQube se verificará en VM-TOOLS.

### VM-TOOLS y control de costos

Los intentos anteriores usaron B4as v2 en México Central y West US 2 y Azure rechazó la asignación por capacidad. En North Central US, Azure CLI falló durante la creación y no mostró el motivo de fondo. La consigna pide B4ms para VM-TOOLS; la asignación de ese SKU aún debe resolverse y confirmarse en una región permitida antes de instalar Jenkins y SonarQube. Azure confirmó que los grupos temporales de los intentos fallidos se eliminaron. Los webhooks y la demostración del Quality Gate con publicación desde Jenkins siguen pendientes.

Instrucciones para el equipo y sus asistentes:

- Revisar el estado antes de iniciar una VM. Encenderla solo para instalación, pruebas, ensayos o exposición que se harán en ese momento. Coordinar con el equipo quién la está usando.
- Configurar apagado automático diario y una alerta de presupuesto de 50 USD en ambas VMs o a nivel de suscripción. La alerta informa; no desasigna ni elimina recursos.
- Desasignarla desde Azure al terminar cada sesión. En el portal, usar **Detener** y confirmar **Detenida (desasignada)**. Por CLI, usar `az vm deallocate -g <grupo> -n <vm>` y verificar el estado con `az vm show -d -g <grupo> -n <vm> --query powerState -o tsv`. Apagar desde Ubuntu por sí solo puede dejar el cómputo asignado.
- Mantener habilitado el límite de gasto de Azure for Students. El disco y la IP reservada pueden seguir consumiendo crédito con la VM desasignada. Revisar ambos recursos al calcular el costo y coordinar su eliminación al terminar el PIA.
- Una alerta de presupuesto avisa sobre el consumo. El apagado y la verificación siguen siendo responsabilidad de quien inicia la VM.

## Parte 4 · Kubernetes y entrega

**Estado: manifiestos y conexión con Jenkins preparados; falta desplegar en una VM-K8S que cumpla el tamaño y el sistema operativo solicitados, y capturar la ejecución real.**

1. Agregué `kubernetes/` con namespace, ConfigMap, Deployment de dos réplicas, Service ClusterIP, Ingress, PodDisruptionBudget y permisos limitados para Jenkins. El Deployment usa la imagen GHCR publicada `1.0.0-8248ffb`, sondas de vitalidad/disponibilidad, usuario sin privilegios, filesystem de solo lectura y actualización gradual con `maxUnavailable: 0`.
2. MicroK8s publica la aplicación por Ingress en TCP 80, limitado al rango de la demo. Las métricas se scrapean por Pod a través del API server autenticado; no se expone otro NodePort de métricas.
3. Agregué kube-state-metrics con RBAC acotado y node_exporter como DaemonSet en VM-K8S. `scripts/create-ghcr-pull-secret.sh` pide el usuario y token al operador y crea `ghcr-pull` sin incluir el secreto en el repositorio ni mostrarlo como argumento del comando.
4. Añadí un ServiceAccount de solo lectura para Prometheus y `scripts/create-prometheus-k8s-credentials.sh`, que genera un token y el certificado CA para discovery y scrape por API proxy. Los archivos se copian a VM-TOOLS sin agregarlos a Git.
5. Añadí `scripts/create-jenkins-kubeconfig.sh`, que crea un kubeconfig de 30 días solicitado al clúster para un ServiceAccount con permiso de actualizar el Deployment de MediSur y leer los objetos que necesita para verificarlo. Jenkins debe guardar el archivo como credencial Secret file `k8s-kubeconfig`; el token se debe rotar antes de su vencimiento efectivo.
6. Añadí el stage de entrega a `Jenkinsfile`: actualizar la imagen con su etiqueta SHA, esperar el rollout, llamar `/health` y `/version` y comprobar versión/SHA. Si falla el rollout o la prueba de humo, intenta hacer `rollout undo` y marca el pipeline en rojo. El chequeo está en `scripts/smoke-test.js`.

**Pendiente de evidencia real:** la VM-K8S adecuada no se ha aprovisionado, por lo que aún no se ha aplicado el manifiesto ni ejecutado el nuevo stage de Jenkins. La VM existente `kuber` está desasignada y usa `Standard_D2s_v4` y Ubuntu 24.04; la guía del trabajo final pide B2ms y Ubuntu 22.04. No la presentamos como entorno conforme.

## Parte 5 · Infraestructura y monitoreo

**Estado: configuraciones reproducibles preparadas; falta desplegar los recursos y registrar métricas/capturas reales.**

1. Agregué `monitoring/docker-compose.yml` con Prometheus 3.14.0, Grafana 13.3.0, Alertmanager 0.35.0 y node_exporter 1.12.1. Prometheus conserva 15 días; Grafana y Prometheus se enlazan solo a localhost para entrar por túnel SSH. La contraseña de Grafana y la contraseña SMTP quedan fuera de Git.
2. Añadí targets file-based para node_exporter en ambas VMs y kube-state-metrics; la aplicación se descubre y scrapea por Pod mediante el API server. Se deben completar con las IP privadas definitivas cuando ambas VMs estén creadas.
3. Añadí dos dashboards provisionados: infraestructura (CPU, memoria, disco y red de ambas VMs) y aplicación (peticiones/respuestas, 5xx, latencia, réplicas, reinicios, versiones y solicitudes/límites de CPU y memoria por Pod). Estas últimas son métricas de configuración, no consumo medido del contenedor.
4. Añadí reglas para disco >80 %, más de tres reinicios en diez minutos y réplicas disponibles por debajo de las deseadas durante cinco minutos, junto con una plantilla privada de correo para Alertmanager.
5. Falta elegir/configurar el SMTP y correo real de notificación, levantar la VM-TOOLS, comprobar targets `UP`, generar tráfico y capturar ambos dashboards y alertas disparadas. El diseño de infraestructura no se ha aplicado a Azure y no hay evidencia de consumo final de crédito todavía.

6. Añadí `scripts/cloud-preflight.sh`, un chequeo de solo lectura para inspeccionar la región permitida, disponibilidad publicada de los SKUs, cuotas de vCPU y VMs existentes antes de aprovisionar. No solicita cuotas ni despliega recursos. La demostración en la nube queda pendiente hasta contar con una suscripción habilitada y crédito/presupuesto aprobado.
7. Añadí `scripts/generate-demo-traffic.js` para producir peticiones HTTP sintéticas y acotadas desde la laptop durante la demostración. Solo usa `GET`, no requiere credenciales y no modifica datos de la aplicación.
8. Añadí [`docs/DEMO-CLOUD.md`](docs/DEMO-CLOUD.md) con la secuencia de demo para gate rojo/verde, despliegue, recuperación, monitoreo, rollback y evidencia pendiente. Distingue expresamente entre configuraciones preparadas y pasos que requieren ejecución real en Azure.

**Uso de IA en estas partes.** Codex ayudó a preparar los manifiestos, RBAC, configuración de Prometheus/Alertmanager/Grafana, dashboards y la etapa CD del Jenkinsfile. El equipo debe revisar cada permiso, métrica, regla y comando; los recursos no se describen como desplegados hasta verificarlo en Azure y Kubernetes.

## Actualización de integración en Azure · 19 nov 2026

Esta sección reemplaza el estado “pendiente de desplegar VM” que aparece en la bitácora histórica anterior.

1. Creé en `chilecentral` `vm-tools` (`Standard_B4s_v2`, 4 vCPU/16 GiB) y `vm-k8s` (`Standard_B2s_v2`, 2 vCPU/8 GiB), con Ubuntu 22.04 y discos `StandardSSD_LRS` de 64 GB. Azure no aceptó los SKU `B4ms`/`B2ms` en las ubicaciones intentadas; la equivalencia de recursos no garantiza aprobación del docente.
2. En Tools instalé Docker, Jenkins, Bun, SonarQube y Caddy. Caddy obtuvo certificado TLS de Let's Encrypt y Jenkins responde HTTP 200 en `https://JENKINS_HOST/login`. El asistente inicial de Jenkins todavía debe completarse en el navegador.
3. En K8s instalé MicroK8s 1.36.2, activé Ingress y confirmé el nodo `Ready`. Desplegué `node-exporter` y `kube-state-metrics`; preparé el namespace `medisur` y permisos acotados para Prometheus y Jenkins.
4. En Tools desplegué Prometheus, Grafana, Alertmanager y node-exporter con Docker Compose. Prometheus retiene 15 días y los endpoints web de Grafana/Prometheus permanecen locales. Verifiqué cuatro targets `UP` (Prometheus, node-exporter de ambas VMs y kube-state-metrics) y tres reglas de alertas cargadas y saludables. Ninguna regla está activa porque su condición no se ha provocado.
5. Grafana está configurado con dos tableros, pero el tablero de aplicación aún no tiene series porque la API no está desplegada. Alertmanager está ejecutándose sin receptor SMTP real; la notificación de correo no se ha demostrado.
6. Existe el presupuesto mensual `medisur-alerta-50-usd` por 50 USD. Azure DevTest Labs no ofrece apagado automático en `chilecentral`; hay que desasignar las VMs manualmente al terminar. El presupuesto solo notifica y no bloquea cargos.
7. El package `ghcr.io/distortr/pia-cloudcomputing` es privado. El despliegue inicial de la API y el flujo de Jenkins quedan pendientes de que el propietario cree un PAT clásico con `read:packages` (y `write:packages` para publicar desde Jenkins). El script `scripts/deploy-to-azure.sh` solicita el secreto sin eco y no lo registra en Git.
8. El kubeconfig de despliegue de Jenkins se generó localmente en `~/.config/medisur-secrets/jenkins-kubeconfig`; su token vence el 20 dic 2026 UTC. Debe cargarse en Jenkins como Secret file y rotarse antes del vencimiento.
9. No se han capturado aún las evidencias visuales requeridas del pipeline, gates rojo/verde, imagen GHCR vinculada al build, dos réplicas, recuperación del Pod, dashboards de MediSur, alertas activas, rollback ni video final. La [guía de demo](docs/DEMO-CLOUD.md) da la secuencia restante.
