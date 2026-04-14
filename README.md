# 🚀 Sistema de Workers con Sidecar - Documentación Completa

## 📋 Tabla de Contenidos
1. [Arquitectura General](#-arquitectura-general)
2. [Componentes](#-componentes)
3. [Flujo de Peticiones](#-flujo-de-peticiones-con-id-de-usuario)
4. [Logs y Monitoreo](#-logs-y-monitoreo-con-ids-de-usuario)
5. [Estados de Activación](#-estados-de-activación-ahorro-de-recursos)
6. [Seguridad y RBAC](#-seguridad-y-rbac)
7. [Instalación](#-instalación)
8. [Configuración](#-configuración)
9. [Uso](#-uso)
10. [API Referencia](#-api-referencia)
11. [Escalado Automático](#-escalado-automático)
12. [Solución de Problemas](#-solución-de-problemas)
13. [Contribución](#-contribución)

---

## 🏗️ Arquitectura General

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
            HPA[HorizontalPodAutoscaler\nmin: 0 | max: 10]
            METRICS[Metrics Server\nCPU | Requests]
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
    
    DASH --> LOGS
    DASH --> METRIC
