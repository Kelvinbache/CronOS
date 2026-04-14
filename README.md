# 🚀 Sistema de Workers con Sidecar - Documentación Completa

## 📋 Tabla de Contenidos
1. [Arquitectura General](#arquitectura-general)
2. [Componentes](#componentes)
3. [Flujo de Peticiones](#flujo-de-peticiones-con-id-de-usuario)
4. [Logs y Monitoreo](#logs-y-monitoreo-con-ids-de-usuario)
5. [Estados de Activación](#estados-de-activación-ahorro-de-recursos)
6. [Seguridad y RBAC](#seguridad-y-rbac)
7. [Instalación](#instalación)
8. [Configuración](#configuración)
9. [Uso](#uso)
10. [API Referencia](#api-referencia)
11. [Escalado Automático](#escalado-automático)
12. [Solución de Problemas](#solución-de-problemas)
13. [Contribución](#contribución)

---

## 🏗️ Arquitectura General

```mermaid
graph TB
    subgraph "FUERA DEL CLUSTER"
        USER[Usuario - X-User-ID header]
        ADMIN[Administrador]
    end

    subgraph "CLUSTER KUBERNETES minikube"
        
        subgraph "NAMESPACE proof"
            
            subgraph "POD mi-app-con-sidecar"
                APP[APP Python - Crea y elimina pods - Logs con IDs - Gestion de estados]
                SIDECAR[SIDECAR - kubectl proxy - Puerto 8001]
                NGINX[NGINX Gateway - Valida IDs - Rate limiting - Proxy a K8s - Puerto 80]
                
                APP <--> SIDECAR
                NGINX --> SIDECAR
            end
            
            subgraph "WORKERS Escalado automatico"
                W1[Worker 1 - Activo]
                W2[Worker 2 - Escalado a 0]
                W3[Worker 3 - Escalado a 0]
                W4[Worker N - Segun demanda]
            end
            
            subgraph "RECURSOS"
                SA[ServiceAccount - creador-pods]
                ROLE[Role - gestor-pods]
                RB[RoleBinding - binding]
            end
        end
        
        subgraph "SERVICIOS NodePort"
            SVC_NGINX[nginx-service - 30080 a 80]
            SVC_PROXY[proxy-service - 30081 a 8001]
            SVC_APP[app-service - 30082 a 5000]
        end
        
        subgraph "AUTOESCALADO"
            HPA[HorizontalPodAutoscaler - min 0 - max 10]
            METRICS[Metrics Server - CPU - Requests]
        end
    end

    subgraph "MONITOREO"
        LOGS[Loki - Promtail - Logs con User-ID]
        METRIC[Prometheus - Metricas]
        DASH[Grafana - Dashboards]
    end

    USER -->|HTTP POST - GET| SVC_NGINX
    ADMIN -->|kubectl| API_SERVER
    
    SVC_NGINX --> NGINX
    SVC_PROXY --> SIDECAR
    SVC_APP --> APP
    
    APP -->|Crea y elimina| W1
    APP -->|Crea y elimina| W2
    APP -->|Crea y elimina| W3
    APP -->|Crea y elimina| W4
    
    HPA -->|Escala| W1
    HPA -->|Escala| W2
    METRICS --> HPA
    
    LOGS -.->|Recolecta| APP
    LOGS -.->|Recolecta| NGINX
    METRIC -.->|Recolecta| METRICS
    
    DASH --> LOGS
    DASH --> METRIC
```
#
```mermaid
sequenceDiagram
    participant U as Usuario - X-User-ID alice123
    participant N as NGINX Gateway - Proxy
    participant K as kubectl-proxy - Sidecar
    participant API as K8s API Server
    participant A as App Python
    participant W as Worker Pod
    
    Note over U,W: 1. Crear worker con ID de usuario
    U->>N: POST - api - workers - create - Header X-User-ID alice123
    N->>N: Validar X-User-ID - Rate limiting
    N->>K: POST - api - v1 - namespaces - proof - pods - forward
    K->>API: Proxy con token SA
    API->>API: Validar RBAC - Crear pod con label created-by alice123
    API-->>K: 201 Created
    K-->>N: Respuesta
    N-->>U: status created - worker worker-xxx
    
    Note over U,W: 2. App registra en logs con ID
    API->>A: Webhook - Event
    A->>A: logger.info - Worker creado por user_id
    
    Note over U,W: 3. Listar workers - filtrados por usuario
    U->>N: GET - api - workers - list - Header X-User-ID alice123
    N->>K: GET - api - v1 - namespaces - proof - pods
    K->>API: Proxy
    API-->>K: Lista de pods
    K-->>N: Respuesta
    N->>N: Filtrar por label created-by alice123
    N-->>U: workers name worker-xxx - status Running
    
    Note over U,W: 4. Escalar a 0 - ahorro recursos
    U->>N: POST - api - workers - scale - active false
    N->>A: Forward a App
    A->>API: DELETE - pods - worker-xxx
    API-->>A: 200 OK
    A-->>N: status scaled - replicas 0
    N-->>U: Worker desactivado
```
#
```mermaid
flowchart LR
    subgraph "LOGS CON USER-ID"
        direction TB
        
        L1["2026-04-14 10:00:01 - USER alice123 - INFO - Intentando crear worker worker-1"]
        L2["2026-04-14 10:00:02 - USER alice123 - INFO - Worker worker-1 creado exitosamente"]
        L3["2026-04-14 10:00:05 - USER bob456 - INFO - Intentando crear worker worker-2"]
        L4["2026-04-14 10:00:06 - USER bob456 - WARNING - Worker worker-2 ya existe"]
        L5["2026-04-14 10:00:10 - USER alice123 - INFO - Listando workers - 3 encontrados"]
        L6["2026-04-14 10:00:15 - USER alice123 - INFO - Desactivando worker worker-1"]
        L7["2026-04-14 10:00:16 - USER alice123 - INFO - Worker worker-1 desactivado"]
        L8["2026-04-14 10:00:20 - USER autoscaler - INFO - Escalando workers - activos 2 - objetivo 5"]
    end
    
    subgraph "FILTROS"
        F1[Filtrar por alice123]
        F2[Filtrar por bob456]
        F3[Filtrar por autoscaler]
        F4[Rango de fechas]
    end
    
    L1 --> F1
    L2 --> F1
    L5 --> F1
    L6 --> F1
    L7 --> F1
    
    L3 --> F2
    L4 --> F2
    
    L8 --> F3

```
#
```mermaid
stateDiagram-v2
    [*] --> Inactivo: Estado inicial - escalado a 0
    
    state Inactivo {
        [*] --> SinPods
        SinPods --> EsperandoDemanda
        EsperandoDemanda --> SinPods: No hay peticiones
    }
    
    Inactivo --> Activo: Peticion con X-User-ID - rate limit OK
    
    state Activo {
        [*] --> PodCreando
        PodCreando --> PodRunning: Pod creado exitosamente
        PodRunning --> PodProcesando: Procesando requests
        PodProcesando --> PodRunning: Respuesta enviada
        PodRunning --> PodTerminando: Timeout o error
        PodTerminando --> [*]: Pod terminado
    }
    
    Activo --> Escalando: Alta demanda - CPU mayor a 50
    
    state Escalando {
        [*] --> CreandoWorker
        CreandoWorker --> WorkerListo: Worker creado
        WorkerListo --> Balanceando: Distribuir carga
        Balanceando --> CreandoWorker: Si sigue alta demanda
        Balanceando --> [*]: Demanda normalizada
    }
    
    Escalando --> Activo: Demanda normalizada
    
    Activo --> Inactivo: Sin actividad - por 60 segundos
    
    note right of Inactivo
        Ahorro de recursos
        minReplicas 0
        No consume CPU - memoria
    end note
    
    note right of Activo
        Worker activo
        Procesando peticiones
        Con logs de usuario
    end note
    
    note right of Escalando
        Autoescalado horizontal
        maxReplicas 10
        Basado en metricas
    end note
```
#
```mermaid
flowchart LR
    subgraph "SEGURIDAD"
        
        subgraph "Authentication"
            USER_HEADER[Header X-User-ID - Ej alice123]
            TOKEN[ServiceAccount Token - JWT]
        end
        
        subgraph "Authorization - RBAC"
            SA[ServiceAccount - creador-pods]
            
            ROLE[Role gestor-pods - get - list - create - delete - patch - pods - log]
            
            ROLE_AUDIT[Role auditor-pods - get pods - log]
            
            RB[RoleBinding - SA a gestor-pods]
            RB_AUDIT[RoleBinding - SA a auditor-pods]
        end
        
        subgraph "Rate Limiting"
            RL[NGINX limit_req - 10r - s por usuario - Burst 5]
        end
        
        subgraph "Audit Logs"
            LOGS[Logs con formato - USER alice123 - INFO - Accion realizada]
        end
    end
    
    USER_HEADER --> NGINX
    NGINX --> RL
    RL --> SA
    
    SA --> RB
    RB --> ROLE
    
    SA --> RB_AUDIT
    RB_AUDIT --> ROLE_AUDIT
    
    ROLE --> API[K8s API Server]
    ROLE_AUDIT --> API
    
    API --> LOGS
```
