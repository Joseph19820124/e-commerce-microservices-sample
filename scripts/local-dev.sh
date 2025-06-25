#!/bin/bash

# Local Development Environment Setup Script
# Usage: ./scripts/local-dev.sh [action]
# Actions: start, stop, restart, status, logs, test

set -euo pipefail

# Configuration
CLUSTER_NAME="ecommerce-local"
NAMESPACE="default"
MONITORING_NAMESPACE="monitoring"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${BLUE}[$timestamp] INFO: $message${NC}" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp] WARN: $message${NC}" ;;
        "ERROR") echo -e "${RED}[$timestamp] ERROR: $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}[$timestamp] SUCCESS: $message${NC}" ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    local tools=("docker" "kubectl")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log "ERROR" "Missing required tools: ${missing_tools[*]}"
        echo "Please install the missing tools:"
        echo "  Docker: https://docs.docker.com/get-docker/"
        echo "  kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    
    # Check Docker is running
    if ! docker info &> /dev/null; then
        log "ERROR" "Docker is not running. Please start Docker Desktop."
        exit 1
    fi
    
    log "SUCCESS" "All prerequisites met"
}

# Setup Kubernetes cluster
setup_cluster() {
    log "INFO" "Setting up Kubernetes cluster..."
    
    # Check if we have a Kubernetes cluster
    if ! kubectl cluster-info &> /dev/null; then
        log "WARN" "No Kubernetes cluster found."
        
        # Try to use Kind if available
        if command -v kind &> /dev/null; then
            log "INFO" "Creating Kind cluster..."
            cat > /tmp/kind-config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
            kind create cluster --name "$CLUSTER_NAME" --config /tmp/kind-config.yaml
            kubectl cluster-info --context "kind-$CLUSTER_NAME"
        else
            log "INFO" "Please ensure you have a Kubernetes cluster running:"
            echo "  - Docker Desktop: Enable Kubernetes in settings"
            echo "  - Kind: brew install kind && kind create cluster"
            echo "  - Minikube: brew install minikube && minikube start"
            exit 1
        fi
    else
        log "SUCCESS" "Kubernetes cluster is ready: $(kubectl config current-context)"
    fi
}

# Build local images
build_images() {
    log "INFO" "Building local Docker images..."
    
    local services=("cart-cna-microservice:cart-service" "products-cna-microservice:product-service" "users-cna-microservice:user-service")
    
    for service_pair in "${services[@]}"; do
        IFS=':' read -r dir image <<< "$service_pair"
        
        if [ -d "$dir" ]; then
            log "INFO" "Building $image..."
            (cd "$dir" && docker build -t "$image:local" . -q)
            
            # Load image to Kind if using Kind
            if command -v kind &> /dev/null && kind get clusters | grep -q "$CLUSTER_NAME"; then
                kind load docker-image "$image:local" --name "$CLUSTER_NAME"
            fi
            
            log "SUCCESS" "$image built successfully"
        else
            log "WARN" "Directory $dir not found, skipping $image"
        fi
    done
}

# Deploy infrastructure
deploy_infrastructure() {
    log "INFO" "Deploying local infrastructure..."
    
    # Create namespace if it doesn't exist
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy PostgreSQL
    log "INFO" "Deploying PostgreSQL..."
    kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres-local
  namespace: default
  labels:
    app: postgres-local
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres-local
  template:
    metadata:
      labels:
        app: postgres-local
    spec:
      containers:
      - name: postgres
        image: postgres:15-alpine
        env:
        - name: POSTGRES_DB
          value: ecommerce
        - name: POSTGRES_USER
          value: postgres
        - name: POSTGRES_PASSWORD
          value: password
        - name: PGDATA
          value: /var/lib/postgresql/data/pgdata
        ports:
        - containerPort: 5432
        resources:
          requests:
            memory: 256Mi
            cpu: 100m
          limits:
            memory: 512Mi
            cpu: 500m
        volumeMounts:
        - name: postgres-storage
          mountPath: /var/lib/postgresql/data
        livenessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - pg_isready
            - -U
            - postgres
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: postgres-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: postgres-local
  namespace: default
spec:
  selector:
    app: postgres-local
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
EOF

    # Deploy Redis
    log "INFO" "Deploying Redis..."
    kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis-local
  namespace: default
  labels:
    app: redis-local
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis-local
  template:
    metadata:
      labels:
        app: redis-local
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        resources:
          requests:
            memory: 128Mi
            cpu: 50m
          limits:
            memory: 256Mi
            cpu: 200m
        command:
        - redis-server
        - --appendonly
        - "yes"
        volumeMounts:
        - name: redis-storage
          mountPath: /data
        livenessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - redis-cli
            - ping
          initialDelaySeconds: 5
          periodSeconds: 5
      volumes:
      - name: redis-storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: redis-local
  namespace: default
spec:
  selector:
    app: redis-local
  ports:
  - port: 6379
    targetPort: 6379
  type: ClusterIP
EOF

    log "SUCCESS" "Infrastructure deployed"
}

# Deploy microservices
deploy_services() {
    log "INFO" "Deploying microservices..."
    
    # Cart Service
    kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cart-service-local
  namespace: default
  labels:
    app: cart-service-local
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cart-service-local
  template:
    metadata:
      labels:
        app: cart-service-local
    spec:
      containers:
      - name: cart-service
        image: cart-service:local
        imagePullPolicy: Never
        ports:
        - containerPort: 8080
        env:
        - name: SPRING_PROFILES_ACTIVE
          value: "local"
        - name: DATABASE_URL
          value: "jdbc:postgresql://postgres-local:5432/ecommerce"
        - name: DATABASE_USERNAME
          value: "postgres"
        - name: DATABASE_PASSWORD
          value: "password"
        - name: REDIS_HOST
          value: "redis-local"
        - name: REDIS_PORT
          value: "6379"
        resources:
          requests:
            memory: 512Mi
            cpu: 200m
          limits:
            memory: 1Gi
            cpu: 1000m
        livenessProbe:
          httpGet:
            path: /actuator/health/liveness
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /actuator/health/readiness
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: cart-service-local
  namespace: default
spec:
  selector:
    app: cart-service-local
  ports:
  - port: 80
    targetPort: 8080
  type: ClusterIP
EOF

    # Product Service
    kubectl apply -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: product-service-local
  namespace: default
  labels:
    app: product-service-local
spec:
  replicas: 1
  selector:
    matchLabels:
      app: product-service-local
  template:
    metadata:
      labels:
        app: product-service-local
    spec:
      containers:
      - name: product-service
        image: product-service:local
        imagePullPolicy: Never
        ports:
        - containerPort: 3000
        env:
        - name: NODE_ENV
          value: "local"
        - name: DATABASE_URL
          value: "postgresql://postgres:password@postgres-local:5432/ecommerce"
        - name: REDIS_URL
          value: "redis://redis-local:6379"
        resources:
          requests:
            memory: 256Mi
            cpu: 100m
          limits:
            memory: 512Mi
            cpu: 500m
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 10
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: product-service-local
  namespace: default
spec:
  selector:
    app: product-service-local
  ports:
  - port: 80
    targetPort: 3000
  type: ClusterIP
EOF

    log "SUCCESS" "Microservices deployed"
}

# Deploy monitoring (lightweight)
deploy_monitoring() {
    log "INFO" "Deploying monitoring stack..."
    
    # Check if Helm is available
    if command -v helm &> /dev/null; then
        kubectl create namespace "$MONITORING_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
        
        # Add Prometheus Helm repo
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
        helm repo update >/dev/null 2>&1
        
        # Install lightweight monitoring stack
        if ! helm list -n "$MONITORING_NAMESPACE" | grep -q prometheus; then
            log "INFO" "Installing Prometheus and Grafana..."
            helm install prometheus prometheus-community/kube-prometheus-stack \
                --namespace "$MONITORING_NAMESPACE" \
                --set grafana.persistence.enabled=false \
                --set prometheus.prometheusSpec.retention=6h \
                --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
                --set prometheus.prometheusSpec.resources.limits.memory=512Mi \
                --set grafana.resources.requests.memory=128Mi \
                --set grafana.resources.limits.memory=256Mi \
                --wait >/dev/null
            log "SUCCESS" "Monitoring stack installed"
        else
            log "INFO" "Monitoring stack already installed"
        fi
    else
        log "WARN" "Helm not found, skipping monitoring deployment"
        log "INFO" "To install Helm: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
    fi
}

# Wait for services to be ready
wait_for_services() {
    log "INFO" "Waiting for services to be ready..."
    
    # Wait for infrastructure
    kubectl wait --for=condition=ready pod -l app=postgres-local --timeout=120s || {
        log "ERROR" "PostgreSQL not ready within timeout"
        return 1
    }
    
    kubectl wait --for=condition=ready pod -l app=redis-local --timeout=60s || {
        log "ERROR" "Redis not ready within timeout"
        return 1
    }
    
    # Wait for microservices
    if kubectl get deployment cart-service-local &>/dev/null; then
        kubectl wait --for=condition=ready pod -l app=cart-service-local --timeout=180s || {
            log "WARN" "Cart service not ready within timeout, check logs"
        }
    fi
    
    if kubectl get deployment product-service-local &>/dev/null; then
        kubectl wait --for=condition=ready pod -l app=product-service-local --timeout=120s || {
            log "WARN" "Product service not ready within timeout, check logs"
        }
    fi
    
    log "SUCCESS" "Services are ready!"
}

# Show status
show_status() {
    echo -e "\n${BLUE}=== Local Development Environment Status ===${NC}"
    
    # Cluster info
    echo -e "\n${YELLOW}Cluster:${NC}"
    kubectl config current-context 2>/dev/null || echo "No cluster context"
    
    # Pods status
    echo -e "\n${YELLOW}Pods:${NC}"
    kubectl get pods -o wide 2>/dev/null || echo "No pods found"
    
    # Services
    echo -e "\n${YELLOW}Services:${NC}"
    kubectl get svc 2>/dev/null || echo "No services found"
    
    # Quick health check
    echo -e "\n${YELLOW}Quick Health Check:${NC}"
    local healthy=0
    local total=0
    
    for app in postgres-local redis-local cart-service-local product-service-local; do
        total=$((total + 1))
        if kubectl get pods -l app="$app" 2>/dev/null | grep -q "Running"; then
            echo -e "  ✓ $app: ${GREEN}Running${NC}"
            healthy=$((healthy + 1))
        else
            echo -e "  ✗ $app: ${RED}Not Running${NC}"
        fi
    done
    
    echo -e "\nHealth: $healthy/$total services running"
    
    # Access information
    echo -e "\n${YELLOW}Access Information:${NC}"
    echo "  Cart Service: kubectl port-forward svc/cart-service-local 8080:80"
    echo "  Product Service: kubectl port-forward svc/product-service-local 3001:80"
    echo "  PostgreSQL: kubectl port-forward svc/postgres-local 5432:5432"
    echo "  Redis: kubectl port-forward svc/redis-local 6379:6379"
    
    if kubectl get svc prometheus-grafana -n "$MONITORING_NAMESPACE" &>/dev/null; then
        echo "  Grafana: kubectl port-forward svc/prometheus-grafana 3000:80 -n $MONITORING_NAMESPACE"
        echo "  Prometheus: kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n $MONITORING_NAMESPACE"
    fi
}

# Show logs
show_logs() {
    local service=${1:-"all"}
    
    if [ "$service" = "all" ]; then
        echo -e "${BLUE}=== All Service Logs ===${NC}"
        kubectl logs -l app=postgres-local --tail=20 2>/dev/null || true
        kubectl logs -l app=redis-local --tail=20 2>/dev/null || true
        kubectl logs -l app=cart-service-local --tail=20 2>/dev/null || true
        kubectl logs -l app=product-service-local --tail=20 2>/dev/null || true
    else
        echo -e "${BLUE}=== $service Logs ===${NC}"
        kubectl logs -l app="$service" --tail=50 -f
    fi
}

# Run tests
run_tests() {
    log "INFO" "Running local tests..."
    
    # Basic connectivity tests
    echo -e "\n${YELLOW}Testing service connectivity...${NC}"
    
    # Test PostgreSQL
    if kubectl run db-test --image=postgres:15-alpine --rm -i --restart=Never --quiet -- \
        psql -h postgres-local -U postgres -d ecommerce -c "SELECT 1;" &>/dev/null; then
        echo -e "  ✓ PostgreSQL: ${GREEN}Connected${NC}"
    else
        echo -e "  ✗ PostgreSQL: ${RED}Connection failed${NC}"
    fi
    
    # Test Redis
    if kubectl run redis-test --image=redis:7-alpine --rm -i --restart=Never --quiet -- \
        redis-cli -h redis-local ping &>/dev/null; then
        echo -e "  ✓ Redis: ${GREEN}Connected${NC}"
    else
        echo -e "  ✗ Redis: ${RED}Connection failed${NC}"
    fi
    
    # Test Cart Service API
    echo -e "\n${YELLOW}Testing APIs...${NC}"
    kubectl port-forward svc/cart-service-local 8080:80 >/dev/null 2>&1 &
    local pf_pid=$!
    sleep 3
    
    if curl -f -s --max-time 10 http://localhost:8080/actuator/health >/dev/null 2>&1; then
        echo -e "  ✓ Cart Service API: ${GREEN}Healthy${NC}"
        
        # Test cart functionality
        local response=$(curl -s -X POST http://localhost:8080/api/cart/items \
            -H "Content-Type: application/json" \
            -d '{"userId": 1, "productId": 1, "quantity": 2}' 2>/dev/null || echo "FAILED")
        
        if [[ "$response" != "FAILED" ]] && [[ "$response" != *"error"* ]]; then
            echo -e "  ✓ Cart API functionality: ${GREEN}Working${NC}"
        else
            echo -e "  ✗ Cart API functionality: ${RED}Failed${NC}"
        fi
    else
        echo -e "  ✗ Cart Service API: ${RED}Not responding${NC}"
    fi
    
    kill $pf_pid 2>/dev/null || true
    
    log "SUCCESS" "Tests completed"
}

# Stop environment
stop_environment() {
    log "INFO" "Stopping local development environment..."
    
    # Delete deployments
    kubectl delete deployment --all 2>/dev/null || true
    kubectl delete service --all 2>/dev/null || true
    kubectl delete configmap --all 2>/dev/null || true
    kubectl delete secret --all 2>/dev/null || true
    
    # Delete monitoring namespace
    kubectl delete namespace "$MONITORING_NAMESPACE" --ignore-not-found=true &
    
    # If using Kind, delete the cluster
    if command -v kind &> /dev/null && kind get clusters | grep -q "$CLUSTER_NAME"; then
        log "INFO" "Deleting Kind cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi
    
    log "SUCCESS" "Environment stopped"
}

# Main function
main() {
    local action=${1:-"start"}
    
    case $action in
        "start")
            check_prerequisites
            setup_cluster
            build_images
            deploy_infrastructure
            deploy_services
            deploy_monitoring
            wait_for_services
            show_status
            echo -e "\n${GREEN}🎉 Local development environment is ready!${NC}"
            echo -e "\n${BLUE}Next steps:${NC}"
            echo "  1. Access services using port-forward commands above"
            echo "  2. Run tests: ./scripts/local-dev.sh test"
            echo "  3. View logs: ./scripts/local-dev.sh logs"
            echo "  4. Check status: ./scripts/local-dev.sh status"
            ;;
        "stop")
            stop_environment
            ;;
        "restart")
            stop_environment
            sleep 2
            main start
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs "${2:-all}"
            ;;
        "test")
            run_tests
            ;;
        "build")
            build_images
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|status|logs|test|build}"
            echo ""
            echo "Actions:"
            echo "  start   - Start the complete local development environment"
            echo "  stop    - Stop and clean up the environment"
            echo "  restart - Stop and start the environment"
            echo "  status  - Show current status of all services"
            echo "  logs    - Show logs (optional: specify service name)"
            echo "  test    - Run basic connectivity and API tests"
            echo "  build   - Build Docker images only"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"