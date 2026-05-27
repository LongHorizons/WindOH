# Deployment

## Environment Separation

| Environment | Purpose | Configuration |
|---|---|---|
| **Development** | Local development and testing | Docker Compose, single-node services |
| **Staging** | Pre-production validation | Docker Compose with production-like configs, separate ES cluster |
| **Production** | Live deployment | Docker Compose (single-host) or Kubernetes (multi-node) |

## Docker Compose (Development / Single-Host Production)

```yaml
# docker-compose.yml
version: '3.8'

services:
  # ── WindOH Application ──
  app:
    build:
      context: ./windoh
      dockerfile: Dockerfile
    ports:
      - "3000:3000"
    environment:
      - NODE_ENV=production
      - MONGODB_URI=mongodb://${MONGODB_USER}:${MONGODB_PASSWORD}@mongo:27017/windoh
      - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379
      - ES_ENDPOINT=https://${ES_HOST}:9200
      - ES_API_KEY=${ES_API_KEY}
      - LLM_ENDPOINT=${LLM_ENDPOINT}
      - LLM_MODEL_NAME=${LLM_MODEL_NAME}
    depends_on:
      mongo:
        condition: service_healthy
      redis:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/health"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  # ── Enrichment Workers ──
  enrichment-worker:
    build:
      context: ./windoh
      dockerfile: Dockerfile.worker
    environment:
      - NODE_ENV=production
      - MONGODB_URI=mongodb://${MONGODB_USER}:${MONGODB_PASSWORD}@mongo:27017/windoh
      - REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379
      - LLM_ENDPOINT=${LLM_ENDPOINT}
      - LLM_MODEL_NAME=${LLM_MODEL_NAME}
      - LLM_TIMEOUT_MS=60000
      - CONCURRENCY=4
    depends_on:
      mongo:
        condition: service_healthy
      redis:
        condition: service_healthy
    deploy:
      replicas: 2
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  # ── MongoDB ──
  mongo:
    image: mongo:7
    environment:
      - MONGO_INITDB_ROOT_USERNAME=${MONGODB_USER}
      - MONGO_INITDB_ROOT_PASSWORD=${MONGODB_PASSWORD}
      - MONGO_INITDB_DATABASE=windoh
    volumes:
      - mongo_data:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--eval", "db.adminCommand('ping')"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

  # ── Redis ──
  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes --requirepass ${REDIS_PASSWORD}
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
    restart: unless-stopped

  # ── SearXNG (optional) ──
  searxng:
    image: searxng/searxng:latest
    ports:
      - "8080:8080"
    environment:
      - SEARXNG_BASE_URL=http://localhost:8080
    volumes:
      - searxng_data:/etc/searxng
    restart: unless-stopped
    profiles:
      - full

volumes:
  mongo_data:
  redis_data:
  searxng_data:
```

## Environment Variables

```bash
# .env (not committed to version control)

# ── MongoDB ──
MONGODB_USER=windoh
MONGODB_PASSWORD=<generate-secure-password>

# ── Redis ──
REDIS_PASSWORD=<generate-secure-password>

# ── Elasticsearch ──
ES_HOST=es.internal
ES_API_KEY=<elasticsearch-api-key>

# ── LLM ──
LLM_ENDPOINT=http://192.168.0.133:31337/v1
LLM_MODEL_NAME=llama-3-8b-instruct

# ── Application ──
NEXT_PUBLIC_APP_URL=http://localhost:3000
```

## Kubernetes (Multi-Node Production)

### Namespace

```yaml
# k8s/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: windoh
```

### MongoDB StatefulSet

```yaml
# k8s/mongodb-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mongodb
  namespace: windoh
spec:
  serviceName: mongodb
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
      - name: mongodb
        image: mongo:7
        env:
        - name: MONGO_INITDB_ROOT_USERNAME
          valueFrom:
            secretKeyRef:
              name: windoh-secrets
              key: mongodb-user
        - name: MONGO_INITDB_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: windoh-secrets
              key: mongodb-password
        volumeMounts:
        - name: mongodb-data
          mountPath: /data/db
        resources:
          requests:
            memory: "2Gi"
            cpu: "500m"
          limits:
            memory: "4Gi"
            cpu: "2000m"
  volumeClaimTemplates:
  - metadata:
      name: mongodb-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 100Gi
```

### Application Deployment

```yaml
# k8s/app-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: windoh-app
  namespace: windoh
spec:
  replicas: 2
  selector:
    matchLabels:
      app: windoh-app
  template:
    metadata:
      labels:
        app: windoh-app
    spec:
      containers:
      - name: app
        image: registry.internal/windoh-app:latest
        ports:
        - containerPort: 3000
        env:
        - name: MONGODB_URI
          valueFrom:
            secretKeyRef:
              name: windoh-secrets
              key: mongodb-uri
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: windoh-secrets
              key: redis-url
        - name: ES_ENDPOINT
          valueFrom:
            configMapKeyRef:
              name: windoh-config
              key: es-endpoint
        - name: LLM_ENDPOINT
          valueFrom:
            configMapKeyRef:
              name: windoh-config
              key: llm-endpoint
        livenessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /api/health
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 10
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: windoh-app
  namespace: windoh
spec:
  selector:
    app: windoh-app
  ports:
  - port: 3000
    targetPort: 3000
  type: ClusterIP
```

## Infrastructure as Code (Terraform)

A minimal Terraform module for provisioning the required infrastructure:

```hcl
# terraform/main.tf (outline)
resource "aws_elasticsearch_domain" "windoh" {
  domain_name           = "windoh-events"
  elasticsearch_version = "8.x"
  
  cluster_config {
    instance_type  = "r6g.large.search"
    instance_count = 3
  }
  
  ebs_options {
    ebs_enabled = true
    volume_size = 100
  }
  
  encrypt_at_rest {
    enabled = true
  }
  
  node_to_node_encryption {
    enabled = true
  }
}

resource "mongodbatlas_cluster" "windoh" {
  # Or: self-hosted MongoDB on EC2
}

resource "aws_ecs_service" "windoh_app" {
  # ECS Fargate for containerized WindOH application
}
```

## Deployment Checklist

- [ ] Generate strong passwords for MongoDB and Redis
- [ ] Create Elasticsearch API key with minimal privileges
- [ ] Configure LLM endpoint (verify health check returns 200)
- [ ] Apply Elasticsearch index templates from [ES-INDEX-TEMPLATES.md](../../LongHorizons/ES-INDEX-TEMPLATES.md)
- [ ] Deploy Docker Compose stack or Kubernetes manifests
- [ ] Verify `/api/health` returns all dependencies healthy
- [ ] Deploy LongHorizons agent to test endpoint
- [ ] Verify events flowing: Agent → ES → WindOH → MongoDB
- [ ] Verify enrichment: new token → queued → LLM → stored
- [ ] Configure backup schedules
- [ ] Configure monitoring alerts on health endpoint
