#!/bin/bash

# Comprehensive Health Check Script for E-Commerce Microservices
# Usage: ./scripts/health-check.sh [environment]

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ENVIRONMENT=${1:-"dev"}
NAMESPACE_PREFIX=""

if [ "$ENVIRONMENT" = "production" ]; then
    NAMESPACE_PREFIX="production"
elif [ "$ENVIRONMENT" = "staging" ]; then
    NAMESPACE_PREFIX="staging"
else
    NAMESPACE_PREFIX="default"
fi

# Health check functions
check_status() {
    local component=$1
    local status=$2
    local details=$3
    
    printf "%-30s" "$component:"
    if [ "$status" = "OK" ]; then
        echo -e "${GREEN}✓ OK${NC} $details"
        return 0
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠ WARNING${NC} $details"
        return 1
    else
        echo -e "${RED}✗ FAILED${NC} $details"
        return 2
    fi
}

# Check Kubernetes cluster
check_cluster() {
    echo -e "\n${BLUE}=== Kubernetes Cluster Health ===${NC}"
    
    # Cluster connectivity
    if kubectl cluster-info &>/dev/null; then
        check_status "Cluster Connectivity" "OK" "$(kubectl config current-context)"
    else
        check_status "Cluster Connectivity" "FAILED" "Cannot connect to cluster"
        return 1
    fi
    
    # Node status
    local ready_nodes=$(kubectl get nodes --no-headers | grep " Ready " | wc -l)
    local total_nodes=$(kubectl get nodes --no-headers | wc -l)
    
    if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$ready_nodes" -gt 0 ]; then
        check_status "Node Status" "OK" "$ready_nodes/$total_nodes nodes ready"
    else
        check_status "Node Status" "FAILED" "$ready_nodes/$total_nodes nodes ready"
    fi
    
    # System pods
    local system_pods_not_ready=$(kubectl get pods -n kube-system --no-headers | grep -v "Running\|Completed" | wc -l)
    if [ "$system_pods_not_ready" -eq 0 ]; then
        check_status "System Pods" "OK" "All system pods running"
    else
        check_status "System Pods" "WARN" "$system_pods_not_ready system pods not ready"
    fi
}

# Check infrastructure components
check_infrastructure() {
    echo -e "\n${BLUE}=== Infrastructure Components ===${NC}"
    
    # Check persistent volumes
    local pv_available=$(kubectl get pv --no-headers 2>/dev/null | grep "Available\|Bound" | wc -l)
    local pv_total=$(kubectl get pv --no-headers 2>/dev/null | wc -l)
    
    if [ "$pv_total" -gt 0 ]; then
        check_status "Persistent Volumes" "OK" "$pv_available/$pv_total volumes available/bound"
    else
        check_status "Persistent Volumes" "WARN" "No persistent volumes found"
    fi
    
    # Check storage classes
    local storage_classes=$(kubectl get storageclass --no-headers | wc -l)
    if [ "$storage_classes" -gt 0 ]; then
        check_status "Storage Classes" "OK" "$storage_classes storage classes available"
    else
        check_status "Storage Classes" "WARN" "No storage classes found"
    fi
}

# Check microservices
check_microservices() {
    echo -e "\n${BLUE}=== Microservices Health ===${NC}"
    
    local services=("cart-service" "product-service" "user-service" "store-ui")
    
    for service in "${services[@]}"; do
        local ready_pods=$(kubectl get pods -l app="$service" -n "$NAMESPACE_PREFIX" --no-headers 2>/dev/null | grep "Running" | wc -l)
        local total_pods=$(kubectl get pods -l app="$service" -n "$NAMESPACE_PREFIX" --no-headers 2>/dev/null | wc -l)
        
        if [ "$total_pods" -gt 0 ]; then
            if [ "$ready_pods" -eq "$total_pods" ]; then
                check_status "$service" "OK" "$ready_pods/$total_pods pods running"
                
                # Check service endpoint if pods are running
                if [ "$ready_pods" -gt 0 ]; then
                    local svc_endpoint=$(kubectl get svc "$service" -n "$NAMESPACE_PREFIX" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "none")
                    if [ "$svc_endpoint" != "none" ] && [ "$svc_endpoint" != "" ]; then
                        check_status "$service endpoint" "OK" "$svc_endpoint"
                    else
                        check_status "$service endpoint" "WARN" "No service endpoint found"
                    fi
                fi
            else
                check_status "$service" "WARN" "$ready_pods/$total_pods pods running"
            fi
        else
            check_status "$service" "WARN" "Service not deployed"
        fi
    done
}

# Check security components
check_security() {
    echo -e "\n${BLUE}=== Security Components ===${NC}"
    
    # Keycloak
    local keycloak_pods=$(kubectl get pods -l app=keycloak -n security --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$keycloak_pods" -gt 0 ]; then
        check_status "Keycloak" "OK" "$keycloak_pods pods running"
    else
        check_status "Keycloak" "WARN" "Not deployed or not running"
    fi
    
    # Vault
    local vault_pods=$(kubectl get pods -l app=vault -n security --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$vault_pods" -gt 0 ]; then
        check_status "HashiCorp Vault" "OK" "$vault_pods pods running"
    else
        check_status "HashiCorp Vault" "WARN" "Not deployed or not running"
    fi
    
    # Istio
    local istio_pods=$(kubectl get pods -n istio-system --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$istio_pods" -gt 0 ]; then
        check_status "Istio Service Mesh" "OK" "$istio_pods pods running"
    else
        check_status "Istio Service Mesh" "WARN" "Not deployed or not running"
    fi
    
    # OPA Gatekeeper
    local opa_pods=$(kubectl get pods -l gatekeeper.sh/system=yes -A --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$opa_pods" -gt 0 ]; then
        check_status "OPA Gatekeeper" "OK" "$opa_pods pods running"
    else
        check_status "OPA Gatekeeper" "WARN" "Not deployed or not running"
    fi
    
    # Check security policies
    local network_policies=$(kubectl get networkpolicies -A --no-headers 2>/dev/null | wc -l)
    if [ "$network_policies" -gt 0 ]; then
        check_status "Network Policies" "OK" "$network_policies policies found"
    else
        check_status "Network Policies" "WARN" "No network policies found"
    fi
}

# Check observability stack
check_observability() {
    echo -e "\n${BLUE}=== Observability Stack ===${NC}"
    
    # Prometheus
    local prometheus_pods=$(kubectl get pods -l app.kubernetes.io/name=prometheus -n monitoring --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$prometheus_pods" -gt 0 ]; then
        check_status "Prometheus" "OK" "$prometheus_pods pods running"
    else
        check_status "Prometheus" "WARN" "Not deployed or not running"
    fi
    
    # Grafana
    local grafana_pods=$(kubectl get pods -l app.kubernetes.io/name=grafana -n monitoring --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$grafana_pods" -gt 0 ]; then
        check_status "Grafana" "OK" "$grafana_pods pods running"
    else
        check_status "Grafana" "WARN" "Not deployed or not running"
    fi
    
    # Elasticsearch
    local elasticsearch_pods=$(kubectl get pods -l app=elasticsearch -n logging --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$elasticsearch_pods" -gt 0 ]; then
        check_status "Elasticsearch" "OK" "$elasticsearch_pods pods running"
    else
        check_status "Elasticsearch" "WARN" "Not deployed or not running"
    fi
    
    # Jaeger
    local jaeger_pods=$(kubectl get pods -l app=jaeger -n tracing --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$jaeger_pods" -gt 0 ]; then
        check_status "Jaeger" "OK" "$jaeger_pods pods running"
    else
        check_status "Jaeger" "WARN" "Not deployed or not running"
    fi
    
    # Fluentd/Fluent-bit
    local fluentd_pods=$(kubectl get pods -l app=fluentd -n logging --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$fluentd_pods" -gt 0 ]; then
        check_status "Fluentd" "OK" "$fluentd_pods pods running"
    else
        check_status "Fluentd" "WARN" "Not deployed or not running"
    fi
}

# Check databases and cache
check_data_layer() {
    echo -e "\n${BLUE}=== Data Layer ===${NC}"
    
    # PostgreSQL
    local postgres_pods=$(kubectl get pods -l app=postgres -n "$NAMESPACE_PREFIX" --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$postgres_pods" -gt 0 ]; then
        check_status "PostgreSQL" "OK" "$postgres_pods pods running"
    else
        check_status "PostgreSQL" "WARN" "Not deployed or not running"
    fi
    
    # Redis
    local redis_pods=$(kubectl get pods -l app=redis -n "$NAMESPACE_PREFIX" --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$redis_pods" -gt 0 ]; then
        check_status "Redis Cache" "OK" "$redis_pods pods running"
    else
        check_status "Redis Cache" "WARN" "Not deployed or not running"
    fi
    
    # Kafka
    local kafka_pods=$(kubectl get pods -l app=kafka -n messaging --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$kafka_pods" -gt 0 ]; then
        check_status "Apache Kafka" "OK" "$kafka_pods pods running"
    else
        check_status "Apache Kafka" "WARN" "Not deployed or not running"
    fi
}

# Check CI/CD components
check_cicd() {
    echo -e "\n${BLUE}=== CI/CD Components ===${NC}"
    
    # ArgoCD
    local argocd_pods=$(kubectl get pods -l app.kubernetes.io/name=argocd-server -n argocd --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$argocd_pods" -gt 0 ]; then
        check_status "ArgoCD" "OK" "$argocd_pods pods running"
    else
        check_status "ArgoCD" "WARN" "Not deployed or not running"
    fi
    
    # Argo Rollouts
    local rollouts_controller=$(kubectl get pods -l app.kubernetes.io/name=argo-rollouts -n argo-rollouts --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$rollouts_controller" -gt 0 ]; then
        check_status "Argo Rollouts" "OK" "$rollouts_controller controllers running"
    else
        check_status "Argo Rollouts" "WARN" "Not deployed or not running"
    fi
    
    # Harbor (if deployed)
    local harbor_pods=$(kubectl get pods -l app=harbor -n harbor --no-headers 2>/dev/null | grep "Running" | wc -l)
    if [ "$harbor_pods" -gt 0 ]; then
        check_status "Harbor Registry" "OK" "$harbor_pods pods running"
    else
        check_status "Harbor Registry" "WARN" "Not deployed or not running"
    fi
}

# Check resource usage
check_resources() {
    echo -e "\n${BLUE}=== Resource Usage ===${NC}"
    
    # Node resource usage
    local node_cpu_usage=$(kubectl top nodes 2>/dev/null | tail -n +2 | awk '{sum+=$3} END {print int(sum/NR)}' || echo "N/A")
    local node_memory_usage=$(kubectl top nodes 2>/dev/null | tail -n +2 | awk '{sum+=$5} END {print int(sum/NR)}' || echo "N/A")
    
    if [ "$node_cpu_usage" != "N/A" ]; then
        if [ "$node_cpu_usage" -lt 80 ]; then
            check_status "Node CPU Usage" "OK" "Average: ${node_cpu_usage}%"
        else
            check_status "Node CPU Usage" "WARN" "Average: ${node_cpu_usage}%"
        fi
    else
        check_status "Node CPU Usage" "WARN" "Metrics not available"
    fi
    
    if [ "$node_memory_usage" != "N/A" ]; then
        if [ "$node_memory_usage" -lt 80 ]; then
            check_status "Node Memory Usage" "OK" "Average: ${node_memory_usage}%"
        else
            check_status "Node Memory Usage" "WARN" "Average: ${node_memory_usage}%"
        fi
    else
        check_status "Node Memory Usage" "WARN" "Metrics not available"
    fi
    
    # PVC usage
    local pvcs_total=$(kubectl get pvc -A --no-headers 2>/dev/null | wc -l)
    local pvcs_bound=$(kubectl get pvc -A --no-headers 2>/dev/null | grep "Bound" | wc -l)
    
    if [ "$pvcs_total" -gt 0 ]; then
        if [ "$pvcs_bound" -eq "$pvcs_total" ]; then
            check_status "Persistent Volume Claims" "OK" "$pvcs_bound/$pvcs_total bound"
        else
            check_status "Persistent Volume Claims" "WARN" "$pvcs_bound/$pvcs_total bound"
        fi
    else
        check_status "Persistent Volume Claims" "OK" "No PVCs found"
    fi
}

# Check network connectivity
check_network() {
    echo -e "\n${BLUE}=== Network Connectivity ===${NC}"
    
    # DNS resolution
    kubectl run dns-test --image=busybox --rm -i --restart=Never --quiet -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        check_status "Internal DNS" "OK" "kubernetes.default.svc.cluster.local resolves"
    else
        check_status "Internal DNS" "FAILED" "Cannot resolve internal DNS"
    fi
    
    # External connectivity
    kubectl run external-test --image=busybox --rm -i --restart=Never --quiet -- wget -q --spider --timeout=10 http://google.com >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        check_status "External Connectivity" "OK" "Can reach external endpoints"
    else
        check_status "External Connectivity" "WARN" "Cannot reach external endpoints"
    fi
    
    # Service mesh (if Istio is installed)
    local istio_gateways=$(kubectl get gateways -A --no-headers 2>/dev/null | wc -l)
    if [ "$istio_gateways" -gt 0 ]; then
        check_status "Istio Gateways" "OK" "$istio_gateways gateways configured"
    else
        check_status "Istio Gateways" "WARN" "No Istio gateways found"
    fi
}

# Check API endpoints
check_api_endpoints() {
    echo -e "\n${BLUE}=== API Endpoint Health ===${NC}"
    
    local services=("cart-service" "product-service" "user-service")
    
    for service in "${services[@]}"; do
        # Check if service exists
        if kubectl get svc "$service" -n "$NAMESPACE_PREFIX" >/dev/null 2>&1; then
            # Try to check health endpoint via port-forward
            kubectl port-forward svc/"$service" 8080:80 -n "$NAMESPACE_PREFIX" >/dev/null 2>&1 &
            local pf_pid=$!
            sleep 2
            
            # Test health endpoint
            if curl -f -s --max-time 5 http://localhost:8080/actuator/health >/dev/null 2>&1 || \
               curl -f -s --max-time 5 http://localhost:8080/health >/dev/null 2>&1; then
                check_status "$service API" "OK" "Health endpoint responding"
            else
                check_status "$service API" "WARN" "Health endpoint not responding"
            fi
            
            # Clean up port-forward
            kill $pf_pid 2>/dev/null || true
            sleep 1
        else
            check_status "$service API" "WARN" "Service not found"
        fi
    done
}

# Main execution
main() {
    echo -e "${GREEN}E-Commerce Microservices Health Check${NC}"
    echo -e "Environment: ${BLUE}$ENVIRONMENT${NC}"
    echo -e "Timestamp: $(date)"
    echo "=================================================="
    
    # Run all health checks
    check_cluster
    check_infrastructure
    check_microservices
    check_security
    check_observability
    check_data_layer
    check_cicd
    check_resources
    check_network
    check_api_endpoints
    
    echo -e "\n${GREEN}Health check completed!${NC}"
    echo -e "\n${YELLOW}Legend:${NC}"
    echo -e "${GREEN}✓ OK${NC}      - Component is healthy"
    echo -e "${YELLOW}⚠ WARNING${NC} - Component has issues but is functional"
    echo -e "${RED}✗ FAILED${NC}  - Component is not working"
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo "1. Investigate any FAILED components"
    echo "2. Monitor WARNING components closely"
    echo "3. Check logs for more details: kubectl logs <pod-name> -n <namespace>"
    echo "4. For detailed troubleshooting, see: docs/PRODUCTION_TESTING_PLAN.md"
}

# Run health check
main "$@"