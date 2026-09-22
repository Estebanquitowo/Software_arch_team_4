# Assignment 4 — Edge & Scale

> **Grupo:** 4
> **Reverse Proxy asignado:** HAProxy
> **Objetivo:** Llevar la aplicación del Assignment 3 desde una instancia única a una arquitectura con reverse proxy, TLS, static assets, cache, search engine y escalamiento horizontal.

---

## 0. Contexto y requisitos principales

El Assignment 4 requiere implementar distintas configuraciones de deployment:

* [ ] Application + Database
* [ ] Application + Database + Reverse Proxy
* [ ] Application + Database + Reverse Proxy + Cache + Search Engine
* [ ] Application x3 + Database + Reverse Proxy como Load Balancer + Cache + Search Engine

Además:

* [ ] Kubernetes con 3 replicas de Application.
* [ ] Load testing de single-instance vs x3.
* [ ] Reporte de máximo 15 páginas.
* [ ] Presentación sobre HAProxy y resultados del load test.

**Reverse Proxy asignado: HAProxy.**


# Phase 2 — Modify the Application

## 2.1 Book cover images

Modificar la aplicación para permitir:

* [x] Upload de portada de libro.
* [x] Guardar referencia de la imagen.
* [x] Actualizar modelo.
* [x] Crear/update migration.
* [x] Actualizar API.
* [x] Actualizar frontend si corresponde.
* [x] Mostrar la portada.

---

## 2.2 Author images

Modificar la aplicación para permitir:

* [x] Upload de imagen de autor.
* [x] Guardar referencia de la imagen.
* [x] Actualizar modelo.
* [x] Crear/update migration.
* [x] Actualizar API.
* [x] Actualizar frontend si corresponde.
* [x] Mostrar imagen del autor.

---

## 2.3 Configurable image storage

La ubicación de las imágenes debe ser configurable.

* [x] No hardcodear la ruta.
* [x] Utilizar environment variable/configuración.
* [x] Documentar la variable.
* [x] Verificar que cambiar la ruta no requiera modificar código.

Ejemplo conceptual:

```env
IMAGE_STORAGE_PATH=/data/images
```

El nombre definitivo debe adaptarse al proyecto existente.

---

# Phase 3 — Static Assets

La aplicación debe funcionar en dos modos.

## 3.1 Sin HAProxy

Cuando HAProxy no está presente:

* [x] Application sirve static assets.
* [x] Las imágenes son accesibles.
* [x] Verificar uploads.
* [x] Verificar que las páginas puedan cargar las imágenes.

---

## 3.2 Con HAProxy

Cuando HAProxy está presente:

* [ ] HAProxy recibe la request.
* [ ] HAProxy sirve los static assets.
* [ ] Application NO sirve esos static assets.
* [ ] HAProxy cachea los static assets.
* [ ] Dynamic requests son enviadas a Application.

Implementar una configuración mediante environment variable/flag si es necesario:

```env
SERVE_STATIC=true
```

o equivalente.

* [x] Flag `SERVE_STATIC` implementado (default `true`); con `false` la app desactiva `public_file_server` y deja los static assets al proxy (pendiente: configuración de HAProxy en Fases 4–6).

---

# Phase 4 — HAProxy

> **IMPORTANTE: el reverse proxy asignado al Grupo 4 es HAProxy.**

El Assignment requiere implementar el reverse proxy asignado y utilizarlo como punto de entrada de la aplicación.

---

## 4.1 Basic HAProxy configuration

* [ ] Crear configuración de HAProxy.
* [ ] Crear container HAProxy.
* [ ] Configurar frontend.
* [ ] Configurar backend.
* [ ] HAProxy debe recibir requests externas.
* [ ] HAProxy debe reenviar requests a Application.
* [ ] Application no debe quedar expuesta directamente cuando HAProxy está activo.

Arquitectura:

```text
Client
   |
   v
HAProxy
   |
   v
Application
   |
   v
Database
```

---

## 4.2 Custom local domain

Configurar un dominio local.

Ejemplo:

```text
app.localhost
```

* [ ] Resolver correctamente el dominio.
* [ ] HAProxy debe responder al dominio.
* [ ] Verificar acceso desde browser/curl.

---

# Phase 5 — TLS / HTTPS

TLS debe terminar en HAProxy.

El Assignment permite utilizar un certificado self-signed.

* [ ] Generar certificado self-signed.
* [ ] Configurar certificado en HAProxy.
* [ ] Configurar HTTPS.
* [ ] HAProxy termina TLS.
* [ ] Application puede utilizar HTTP internamente.
* [ ] Verificar HTTPS.
* [ ] Verificar comportamiento del certificado.
* [ ] Documentar cómo generar/configurar el certificado.

Arquitectura:

```text
Client
   |
 HTTPS
   |
   v
HAProxy
 TLS termination
   |
 HTTP
   |
   v
Application
```

---

# Phase 6 — HAProxy Static Asset Serving

Configurar HAProxy para manejar los static assets en el edge.

* [ ] Determinar path de static assets.
* [ ] Configurar HAProxy para servirlos.
* [ ] Evitar enviar static asset requests a Application.
* [ ] Configurar caching.
* [ ] Configurar headers apropiados para caching.
* [ ] Verificar que las imágenes funcionen.
* [ ] Verificar que Application no recibe las requests de static assets.

Arquitectura:

```text
Client
   |
   v
HAProxy
   |
   +----> Static Asset
   |
   +----> Application
```

---

# Phase 7 — Stateless Application

> **Esta fase es crítica para poder ejecutar 3 instancias.**

El Assignment exige que cualquier instancia pueda responder cualquier request y que no existan sesiones o uploads dependientes del filesystem/memoria local de una instancia.

---

## 7.1 Sessions

* [ ] Identificar dónde se almacenan actualmente las sesiones.
* [ ] Eliminar session state local.
* [ ] Mover sessions a shared storage.
* [ ] Utilizar el cache de Assignment 3 cuando sea apropiado.
* [ ] Verificar que una sesión pueda ser utilizada desde otra instancia.

Test:

```text
Request → Application 1
          ↓
       Create session

Request → Application 2
          ↓
       Session still exists
```

---

## 7.2 Uploaded images

* [ ] Identificar dónde se almacenan actualmente las imágenes.
* [ ] Evitar storage exclusivo del container.
* [ ] Crear shared storage.
* [ ] Configurar todas las instancias para utilizar el mismo storage.
* [ ] Verificar que Application 1 pueda crear una imagen.
* [ ] Verificar que Application 2 pueda leerla.
* [ ] Verificar que Application 3 pueda leerla.

---

# Phase 8 — Docker Compose Deployment 1

## Application + Database

Implementar:

```text
Application
     |
     v
 Database
```

* [ ] Application x1.
* [ ] Database.
* [ ] Sin HAProxy.
* [ ] Application sirve static assets.
* [ ] Image uploads funcionan.
* [ ] Database funciona.
* [ ] Application funciona de extremo a extremo.

---

# Phase 9 — Docker Compose Deployment 2

## Application + Database + HAProxy

Implementar:

```text
Client
  |
  v
HAProxy
  |
  v
Application
  |
  v
Database
```

* [ ] Application x1.
* [ ] Database.
* [ ] HAProxy.
* [ ] HTTPS.
* [ ] Custom local domain.
* [ ] Static assets desde HAProxy.
* [ ] Static asset caching.
* [ ] Dynamic requests → Application.
* [ ] Application no sirve static assets en este deployment.

---

# Phase 10 — Docker Compose Deployment 3

## Application + Database + HAProxy + Cache + Search Engine

Implementar:

```text
                  ┌──> Database
                  |
Client → HAProxy → Application
                  |
                  ├──> Cache
                  |
                  └──> Search Engine
```

* [ ] Application.
* [ ] Database.
* [ ] HAProxy.
* [ ] Cache de Assignment 3.
* [ ] Search Engine de Assignment 3.
* [ ] HTTPS.
* [ ] Static assets.
* [ ] Static asset caching.
* [ ] Cache funcionando.
* [ ] Search funcionando.
* [ ] Full application funcionando.

---

# Phase 11 — Docker Compose Deployment 4

## Application x3 + Database + HAProxy Load Balancer + Cache + Search Engine

Este es el deployment principal de escalamiento horizontal.

El Assignment requiere al menos 3 instancias de Application detrás del reverse proxy/load balancer.

Arquitectura:

```text
                         ┌── Application 1 ──┐
                         │                   │
Client → HAProxy ────────┼── Application 2 ──┼──> Database
          Load Balancer  │                   │
                         └── Application 3 ──┘
                                  |
                              Cache / Search
```

---

## 11.1 Three application instances

* [ ] Application 1.
* [ ] Application 2.
* [ ] Application 3.
* [ ] Las tres usan la misma imagen/configuración.
* [ ] Las tres tienen acceso a Database.
* [ ] Las tres tienen acceso a Cache.
* [ ] Las tres tienen acceso a Search Engine.
* [ ] Las tres tienen acceso al shared storage.

---

## 11.2 HAProxy Load Balancing

Configurar HAProxy como load balancer.

* [ ] Backend con 3 servers.
* [ ] Application 1.
* [ ] Application 2.
* [ ] Application 3.
* [ ] Configurar health checks.
* [ ] Verificar distribución de requests.
* [ ] Verificar comportamiento cuando una instancia falla.

Conceptualmente:

```text
backend application
    server app1 ...
    server app2 ...
    server app3 ...
```

La configuración exacta debe adaptarse a Docker Compose y al proyecto.

---

# Phase 12 — Identify Application Instances

Para poder demostrar el load balancing:

* [ ] Agregar temporalmente un identificador de instancia.
* [ ] Puede utilizar hostname/container ID/environment variable.
* [ ] Mostrar qué instancia respondió.
* [ ] Utilizarlo para pruebas.
* [ ] No romper la arquitectura stateless.

Ejemplo:

```text
Response served by: app-1
Response served by: app-2
Response served by: app-3
```

---

# Phase 13 — HAProxy Health Checks

Configurar health checks.

* [ ] Crear/usar endpoint health check.
* [ ] HAProxy debe comprobar Application.
* [ ] Application healthy → recibe tráfico.
* [ ] Application unhealthy → deja de recibir tráfico.

Test:

```text
app1 UP
app2 UP
app3 UP
```

Luego:

```text
app1 DOWN
app2 UP
app3 UP
```

* [ ] HAProxy deja de enviar tráfico a app1.
* [ ] app2 y app3 continúan atendiendo requests.

---

# Phase 14 — Failure Test

El Assignment exige verificar que detener una instancia no rompa la aplicación.

## Test

* [ ] Levantar Application x3.
* [ ] Confirmar que las 3 están healthy.
* [ ] Enviar requests.
* [ ] Confirmar distribución.
* [ ] Detener Application 1.
* [ ] Verificar HAProxy health check.
* [ ] Enviar requests nuevamente.
* [ ] Confirmar que Application 2 y 3 siguen funcionando.
* [ ] Confirmar que no aparecen errores relacionados con Application 1.
* [ ] Reiniciar Application 1.
* [ ] Confirmar que vuelve al pool.

---

# Phase 15 — Kubernetes

Mantener el deployment Kubernetes existente de Assignment 3 y extenderlo.

El Assignment requiere ejecutar la configuración completa en un cluster local como minikube/k3d.

---

## 15.1 Application Deployment

* [ ] Cambiar Application Deployment a 3 replicas.

```yaml
replicas: 3
```

* [ ] Verificar 3 pods.
* [ ] Verificar que los 3 pods estén Ready.

---

## 15.2 Kubernetes Service

* [ ] Crear/mantener Service para Application.
* [ ] Service apunta a las 3 replicas.
* [ ] Verificar que el Service distribuya requests.

Arquitectura:

```text
HAProxy / Ingress
       |
       v
    Service
       |
   ┌───┼───┐
   v   v   v
  Pod Pod Pod
   1   2   3
```

---

# Phase 16 — Kubernetes Reverse Proxy / Edge

Mantener HAProxy en el edge según corresponda a la arquitectura del proyecto.

* [ ] HAProxy / Ingress configurado.
* [ ] TLS termination.
* [ ] Static assets servidos en edge.
* [ ] Edge → Kubernetes Service.
* [ ] Service → Application x3.

El Assignment especifica que el reverse proxy debe mantenerse delante del Service.

---

# Phase 17 — Kubernetes Statelessness

* [ ] Sessions no dependen de un pod.
* [ ] Uploaded images no dependen de un pod.
* [ ] Database compartida.
* [ ] Cache compartido.
* [ ] Search Engine compartido.
* [ ] Cualquier pod puede procesar cualquier request.

Test:

```text
Request → Pod 1
Request → Pod 2
Request → Pod 3
```

Los resultados deben ser funcionalmente equivalentes.

---

# Phase 18 — Load Testing

Comparar:

```text
Deployment A
Application x1
```

vs.

```text
Deployment B
Application x3
HAProxy Load Balancer
```

El Assignment requiere:

* 1 request
* 10 requests
* 100 requests
* 1000 requests
* 5000 requests

en 5 minutos.

---

# Phase 19 — Load Test Tool

Elegir:

* [ ] Gatling
* [ ] JMeter
* [ ] Otra herramienta conocida.

Documentar:

* [ ] Cómo instalarla.
* [ ] Cómo ejecutar las pruebas.
* [ ] Cómo repetirlas.
* [ ] Cómo guardar resultados.

---

# Phase 20 — Load Test Metrics

Para cada prueba registrar:

## Application containers

* [ ] CPU usage (%).
* [ ] Memory usage.
* [ ] Number of threads.

## Requests

* [ ] Response time.
* [ ] Status codes.

Las métricas deben capturarse por container/instancia cuando sea posible.

---

# Phase 21 — Load Test Endpoint 1

## Static Asset

Utilizar:

* [ ] Book cover
  o
* [ ] Author image.

Objetivo:

```text
Client
 ↓
HAProxy / Edge
 ↓
Static Asset
```

Evaluar:

* [ ] Reverse proxy.
* [ ] Caching.
* [ ] Edge performance.

---

# Phase 22 — Load Test Endpoint 2

## Expensive Aggregation

Elegir un endpoint existente:

* [ ] Top 50 selling.
* [ ] Authors overview.

Objetivo:

* [ ] Application CPU.
* [ ] Database.
* [ ] Cache.

---

# Phase 23 — Load Test Endpoint 3

## Search Window

Utilizar el endpoint de búsqueda existente.

Objetivo:

* [ ] Search Engine.

---

# Phase 24 — Load Test Endpoint 4

## Cheap Dynamic Read

Utilizar:

* [ ] Book detail page.

Objetivo:

* [ ] Application.
* [ ] Database baseline.

El Assignment exige reportar los cuatro endpoints por separado.

---

# Phase 25 — Load Test Results

Crear resultados separados para:

1. Static asset.
2. Expensive aggregation.
3. Search.
4. Cheap dynamic read.

Y para cada uno:

* [ ] x1.
* [ ] x3.
* [ ] 1 request.
* [ ] 10 requests.
* [ ] 100 requests.
* [ ] 1000 requests.
* [ ] 5000 requests.

---

# Phase 26 — Bottleneck Analysis

Analizar los resultados reales.

Para cada endpoint:

* [ ] Identificar bottleneck.
* [ ] Determinar si está en:

  * [ ] HAProxy.
  * [ ] Application.
  * [ ] Database.
  * [ ] Cache.
  * [ ] Search Engine.
  * [ ] Storage.
* [ ] Comparar x1 vs x3.
* [ ] Determinar si las 3 instancias cambiaron el comportamiento.
* [ ] Explicar por qué.

**No asumir que todos los endpoints mejorarán con 3 replicas. Las conclusiones deben basarse en los resultados obtenidos.**

---

# Phase 27 — Architecture Documentation

Crear diagramas/documentación para:

## Deployment 1

```text
Client → Application → Database
```

## Deployment 2

```text
Client → HAProxy → Application → Database
```

## Deployment 3

```text
Client → HAProxy → Application → Database
                    ↓
                  Cache
                    ↓
               Search Engine
```

## Deployment 4

```text
                    ┌→ Application 1 ─┐
                    ├→ Application 2 ─┼→ Database
Client → HAProxy ───┤                 ├→ Cache
                    └→ Application 3 ─┴→ Search
```

## Kubernetes

```text
Client
  |
 HTTPS
  |
HAProxy / Ingress
  |
Service
  |
┌─┴─────────────┐
│ Application x3│
└───────────────┘
```

---

# Phase 28 — HAProxy Documentation

Documentar específicamente HAProxy.

## Explicar

* [ ] Qué es HAProxy.
* [ ] Para qué sirve.
* [ ] Cómo funciona el frontend.
* [ ] Cómo funciona el backend.
* [ ] Cómo realiza load balancing.
* [ ] Health checks.
* [ ] TLS termination.
* [ ] Static assets.
* [ ] Caching.
* [ ] Cómo se integra con Docker.
* [ ] Cómo se integra con Kubernetes.

## Strengths

Documentar fortalezas de HAProxy basadas en sus características reales y en la experiencia de implementación.

## Weaknesses

Documentar limitaciones/desventajas relevantes para este proyecto.

---


# Phase 29 — README

Actualizar README.

Debe incluir:

## Requirements

* [ ] Docker.
* [ ] Docker Compose.
* [ ] Kubernetes.
* [ ] minikube/k3d.
* [ ] Load testing tool.

## Compose deployments

* [ ] Cómo levantar Application + Database.
* [ ] Cómo levantar HAProxy.
* [ ] Cómo levantar full stack.
* [ ] Cómo levantar x3.

## HTTPS

* [ ] Cómo generar certificado.
* [ ] Cómo configurar HAProxy.
* [ ] Cómo acceder al dominio local.

## Kubernetes

* [ ] Cómo iniciar cluster.
* [ ] Cómo aplicar manifests.
* [ ] Cómo verificar pods.
* [ ] Cómo verificar Service.
* [ ] Cómo acceder al sistema.

## Load testing

* [ ] Cómo ejecutar cada prueba.
* [ ] Cómo obtener métricas.
* [ ] Dónde se guardan los resultados.

---

# Phase 32 — Final Functional Testing

## Deployment 1

* [ ] Build.
* [ ] Start.
* [ ] Database.
* [ ] Application.
* [ ] CRUD.
* [ ] Book images.
* [ ] Author images.
* [ ] Static assets.

## Deployment 2

* [ ] Build.
* [ ] Start.
* [ ] HAProxy.
* [ ] HTTPS.
* [ ] Domain.
* [ ] Dynamic requests.
* [ ] Static assets.
* [ ] Cache.

## Deployment 3

* [ ] Application.
* [ ] Database.
* [ ] HAProxy.
* [ ] Cache.
* [ ] Search.
* [ ] Images.
* [ ] HTTPS.
* [ ] Search functionality.

## Deployment 4

* [ ] Application 1.
* [ ] Application 2.
* [ ] Application 3.
* [ ] HAProxy.
* [ ] Load balancing.
* [ ] Health checks.
* [ ] Database.
* [ ] Cache.
* [ ] Search.
* [ ] Shared storage.
* [ ] Shared sessions.
* [ ] Failure test.

## Kubernetes

* [ ] Cluster starts.
* [ ] 3 Application replicas.
* [ ] Pods Ready.
* [ ] Service works.
* [ ] HAProxy/Ingress works.
* [ ] TLS works.
* [ ] Static assets work.
* [ ] Database works.
* [ ] Cache works.
* [ ] Search works.
* [ ] Statelessness verified.

---

# Phase 33 — Final Assignment Checklist

## Application

* [ ] Book cover upload.
* [ ] Author image upload.
* [ ] Configurable image storage.
* [ ] Static assets supported.
* [ ] Application can serve static assets without proxy.
* [ ] HAProxy serves static assets with proxy.
* [ ] HAProxy caches static assets.
* [ ] Application stateless.
* [ ] Shared sessions.
* [ ] Shared image storage.

## HAProxy

* [ ] HAProxy configured.
* [ ] Custom local domain.
* [ ] HTTPS.
* [ ] TLS termination.
* [ ] Reverse proxy.
* [ ] Static assets.
* [ ] Caching.
* [ ] Load balancing.
* [ ] Health checks.
* [ ] Failure handling.

## Docker Compose

* [ ] Application + Database.
* [ ] Application + Database + HAProxy.
* [ ] Application + Database + HAProxy + Cache + Search.
* [ ] Application x3 + Database + HAProxy + Cache + Search.

## Kubernetes

* [ ] 3 Application replicas.
* [ ] Service.
* [ ] HAProxy/Ingress at edge.
* [ ] TLS.
* [ ] Static assets.
* [ ] Stateless application.
* [ ] Cache.
* [ ] Search Engine.

## Load Testing

* [ ] Single instance.
* [ ] x3 instances.
* [ ] 1 request.
* [ ] 10 requests.
* [ ] 100 requests.
* [ ] 1000 requests.
* [ ] 5000 requests.
* [ ] CPU.
* [ ] Memory.
* [ ] Threads.
* [ ] Response times.
* [ ] Status codes.
* [ ] Static asset.
* [ ] Expensive aggregation.
* [ ] Search.
* [ ] Cheap dynamic read.
* [ ] Results separated by endpoint.
* [ ] Bottleneck analysis.

## Deliverables

* [ ] Working Docker Compose configurations.
* [ ] Working Kubernetes deployment.
* [ ] Load test results.
* [ ] README.
* [ ] Report ≤15 pages.
* [ ] Presentation material.

---

# Agent Workflow

## IMPORTANT

Trabaja en este orden:

```text
Phase 1
Understand
   ↓
Phase 2
Application changes
   ↓
Phase 3
Static assets
   ↓
Phase 4
HAProxy
   ↓
Phase 5
TLS
   ↓
Phase 6
HAProxy static assets
   ↓
Phase 7
Statelessness
   ↓
Phase 8-11
Docker Compose
   ↓
Phase 12-14
Load balancing + failure
   ↓
Phase 15-17
Kubernetes
   ↓
Phase 18-26
Load testing
   ↓
Phase 27-31
Documentation
   ↓
Phase 32
Final testing
   ↓
Phase 33
Final checklist
```

### Rules for the coding agent

1. **Primero inspecciona el repositorio.**
2. No hagas cambios antes de entender la arquitectura.
3. No reemplaces componentes existentes sin justificarlo.
4. No elimines funcionalidades del Assignment 3.
5. Mantén el cache de Assignment 3.
6. Mantén el Search Engine de Assignment 3.
7. No inventes endpoints: reutiliza los existentes.
8. No marques tareas como completadas sin probarlas.
9. Después de cada cambio importante ejecuta tests.
10. Si un cambio rompe funcionalidad existente, arreglarlo antes de continuar.
11. Mantener los deployments reproducibles.
12. Preferir configuraciones mediante environment variables.
13. No hardcodear paths.
14. Documentar comandos utilizados para probar cada fase.
15. Mostrar qué archivos fueron modificados.
16. Explicar cualquier decisión arquitectónica importante.
17. Si existe una decisión del Assignment 3 que dificulta el escalamiento, identificarla explícitamente.
18. No escribir el reporte académico final.
19. No inventar resultados de load testing: ejecutar las pruebas y utilizar resultados reales.
20. No avanzar automáticamente cuando exista un error crítico.

---

# FIRST TASK

**Comienza únicamente con Phase 1 — Understand.**

No modifiques ningún archivo todavía.

Inspecciona el repositorio y entrega:

1. Arquitectura actual.
2. Stack tecnológico.
3. Docker/Compose actual.
4. Kubernetes actual.
5. Cache de Assignment 3.
6. Search Engine de Assignment 3.
7. Cómo funcionan actualmente las sesiones.
8. Cómo funcionan actualmente los uploads.
9. Cómo se sirven actualmente los static assets.
10. Problemas que impedirían ejecutar 3 instancias.
11. Lista de archivos que probablemente deberán modificarse.
12. Plan de implementación específico para este repositorio.

Después de presentar ese análisis, **espera antes de comenzar Phase 2**.
