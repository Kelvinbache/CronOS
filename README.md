# 🚀 Sistema de Workers Dinámicos con Sidecar (K8s)

Esta documentación detalla la arquitectura de una solución basada en **Kubernetes** diseñada para la gestión eficiente de recursos, trazabilidad por usuario y escalado automático inteligente.

---

## 🏗️ 1. Arquitectura General del Sistema

El sistema opera dentro de un clúster de Kubernetes (Minikube), centralizando la lógica en un Pod principal que utiliza el patrón **Sidecar** para interactuar con la API de Kubernetes de forma segura.

```mermaid
graph TB
    subgraph "🌐 FUERA DEL CLÚSTER"
        USER[👤 Usuario\nX-User-ID: header]
        ADMIN[🖥️ Administrador]
    end

    subgraph "☸️ CLÚSTER KUBERNETES (minikube)"
        
        subgraph "📦 NAMESPACE: proof"
            
            subgraph "🎯 POD: mi-app-con-sidecar"
                APP[🐍 APP Python\n- Crea/elimina pods\n- Logs con IDs\n- Gestión de estados]
                SIDECAR[🔄 SIDECAR\n- kubectl proxy\n- Puerto 8001]
                NGINX[🌐 NGINX Gateway\n- Valida IDs\n- Rate limiting\n- Proxy a K8s\n- Puerto 80]
                
                APP <--> SIDECAR
                NGINX --> SIDECAR
            end
            
            subgraph "📊 WORKERS (Escalado automático)"
                W1[✅ Worker #1\nActivo]
                W2[❌ Worker #2\nEscalado a 0]
                W3[❌ Worker #3\nEscalado a 0]
                W4[⏳ Worker #N\nSegún demanda]
            end
            
            subgraph "🔧 RECURSOS"
                SA[ServiceAccount\ncreador-pods]
                ROLE[Role\ngestor-pods]
                RB[RoleBinding\nbinding]
            end
        end
        
        subgraph "🔌 SERVICIOS (NodePort)"
            SVC_NGINX[nginx-service\n30080 → 80]
            SVC_PROXY[proxy-service\n30081 → 8001]
            SVC_APP[app-service\n30082 → 5000]
        end
        
        subgraph "⚙️ AUTOESCALADO"
            HPA["HorizontalPodAutoscaler\nmin: 0 | max: 10"]
            METRICS["Metrics Server\nCPU | Requests"]
        end
    end

    subgraph "📈 MONITOREO"
        LOGS[📝 Loki/Promtail\nLogs con User-ID]
        METRIC[📊 Prometheus\nMétricas]
        DASH[📉 Grafana\nDashboards]
    end

    USER -->|HTTP POST/GET| SVC_NGINX
    ADMIN -->|kubectl| API_SERVER
    
    SVC_NGINX --> NGINX
    SVC_PROXY --> SIDECAR
    SVC_APP --> APP
    
    APP -->|Crea/elimina| W1
    APP -->|Crea/elimina| W2
    APP -->|Crea/elimina| W3
    APP -->|Crea/elimina| W4
    
    HPA -->|Escala| W1
    HPA -->|Escala| W2
    METRICS --> HPA
    
    LOGS -.->|Recolecta| APP
    LOGS -.->|Recolecta| NGINX
    METRIC -.->|Recolecta| METRICS

sequenceDiagram
    participant U as Usuario\n(X-User-ID: alice123)
    participant N as NGINX Gateway\n(Proxy)
    participant K as kubectl-proxy\n(Sidecar)
    participant API as K8s API Server
    participant A as App Python
    participant W as Worker Pod
    
    Note over U,W: 1. Crear worker con ID de usuario
    U->>N: POST /api/workers/create\nHeader: X-User-ID: alice123
    N->>N: Validar X-User-ID\nRate limiting
    N->>K: POST /api/v1/namespaces/proof/pods\n(forward)
    K->>API: Proxy con token SA
    API->>API: Validar RBAC\nCrear pod con label created-by=alice123
    API-->>K: 201 Created
    K-->>N: Respuesta
    N-->>U: {"status": "created", "worker": "worker-xxx"}
    
    Note over U,W: 2. App registra en logs con ID
    API->>A: Webhook/Event
    A->>A: logger.info(f"Worker creado por {user_id}")
    
    Note over U,W: 3. Listar workers (filtrados por usuario)
    U->>N: GET /api/workers/list\nHeader: X-User-ID: alice123
    N->>K: GET /api/v1/namespaces/proof/pods
    K->>API: Proxy
    API-->>K: Lista de pods
    K-->>N: Respuesta
    N->>N: Filtrar por label created-by=alice123
    N-->>U: {"workers": [{"name": "worker-xxx", "status": "Running"}]}

stateDiagram-v2
    [*] --> Inactivo: Estado inicial\n(replicas=0)
    
    state Inactivo {
        [*] --> SinPods
        SinPods --> EsperandoDemanda
    }
    
    Inactivo --> Activo: Petición con X-User-ID
    
    state Activo {
        [*] --> PodCreando
        PodCreando --> PodRunning
        PodRunning --> PodProcesando
        PodProcesando --> PodRunning
    }
    
    Activo --> Inactivo: Sin actividad (60s)


flowchart LR
    subgraph "🔐 SEGURIDAD"
        USER_HEADER[Header: X-User-ID] --> RL[Rate Limiting NGINX]
        RL --> SA[ServiceAccount]
        SA --> RB[RoleBinding]
        RB --> ROLE[Role: gestor-pods]
        ROLE --> API[K8s API Server]
    end
    
    DASH --> LOGS
    DASH --> METRIC
