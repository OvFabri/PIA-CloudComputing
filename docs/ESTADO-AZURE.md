# Estado verificado de Azure — MediSur

**Fecha de verificación:** 20 de noviembre de 2026, hora de Monterrey. Este archivo distingue recursos comprobados de configuraciones aún pendientes; no incluye credenciales.

## Recursos creados

| Recurso | Región | Tamaño desplegado | CPU / RAM | SO / disco | Estado |
|---|---|---|---:|---|---|
| `vm-tools` | Chile Central | `Standard_B4s_v2` | 4 / 16 GiB | Ubuntu 22.04, SSD estándar 64 GB | En ejecución |
| `vm-k8s` | Chile Central | `Standard_B2s_v2` | 2 / 8 GiB | Ubuntu 22.04, SSD estándar 64 GB | En ejecución |

Se eligieron los tamaños `B4s_v2` y `B2s_v2` porque Azure no permitió crear los SKUs `B4ms` y `B2ms` en las regiones probadas por disponibilidad/capacidad. Coinciden en vCPU y memoria con la consigna, pero no son los mismos SKU; el equipo debe confirmar con el profesor que acepta el equivalente.

## Servicios y evidencia comprobada

- Jenkins, Docker y Caddy están activos en `vm-tools`. Jenkins responde por HTTPS; se completó el asistente inicial y se ejecutaron builds multibranch. El build más reciente completó pruebas, análisis y construcción de imagen, pero GHCR rechazó el push por permisos `write_package` del paquete del repositorio original.
- SonarQube está activo y reporta estado `UP` en el puerto local 9000 de `vm-tools`.
- MicroK8s 1.36.2 está activo en `vm-k8s`; el nodo reporta `Ready` sobre Ubuntu 22.04.5.
- `node-exporter` está desplegado en ambas VMs y `kube-state-metrics` en el clúster.
- Prometheus, Grafana, Alertmanager y node-exporter de Tools están levantados en Docker Compose. Grafana y Prometheus solo escuchan en loopback.
- Los cuatro targets de Prometheus comprobados (`prometheus`, ambos `node-exporter` y `kube-state-metrics`) aparecen `UP`. Las tres reglas están cargadas y saludables; actualmente están `inactive` porque sus condiciones no se han producido.
- El namespace `medisur` y los roles de lectura de Prometheus y despliegue de Jenkins están preparados. El Deployment de la API todavía no existe en el clúster.
- Existe un presupuesto mensual de 50 USD llamado `medisur-alerta-50-usd`. Es una alerta de gasto, no un tope automático.

## Estado pendiente al 20 de noviembre

- Publicar la imagen en el GHCR del fork `OvFabri` con credencial `write:packages`, y crear el secreto `read:packages` para el clúster; la API aún no está desplegada.
- Cambiar el Multibranch Pipeline al fork `OvFabri/PIA-CloudComputing`, configurar el webhook y verificar que las credenciales GHCR y kubeconfig correspondan al destino nuevo.
- Configurar un receptor de notificaciones en Alertmanager (requiere elegir un correo y SMTP) y probar la entrega real de las alertas.
- Capturar evidencia visual del pipeline, Quality Gate rojo/verde, publicación GHCR, dos réplicas, auto-recuperación de Pod, ambos dashboards con métricas de MediSur y rollback.
- La función de apagado automático de Azure DevTest Labs no está disponible para la ubicación `chilecentral`; las VMs deben desasignarse manualmente con `az vm deallocate` al terminar. El presupuesto no impide superar el gasto.

## Cuidado de credenciales

La contraseña inicial de Jenkins, el token de scrape de Kubernetes, el kubeconfig para Jenkins y la contraseña de Grafana se guardan localmente bajo `~/.config/medisur-secrets/` con permisos restringidos. Los secretos de operación y el `.env` de Grafana/Alertmanager están excluidos de Git. No subir esos archivos ni copiar sus valores al informe.
