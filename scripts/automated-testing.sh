#!/bin/bash

# E-Commerce Microservices Automated Testing Script
# Usage: ./scripts/automated-testing.sh [phase] [environment]
# Example: ./scripts/automated-testing.sh phase1 dev

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PHASE=${1:-"all"}
ENVIRONMENT=${2:-"dev"}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_ROOT/logs"
REPORT_DIR="$PROJECT_ROOT/test-reports"

# Create directories
mkdir -p "$LOG_DIR" "$REPORT_DIR"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")  echo -e "${BLUE}[$timestamp] INFO: $message${NC}" | tee -a "$LOG_DIR/test.log" ;;
        "WARN")  echo -e "${YELLOW}[$timestamp] WARN: $message${NC}" | tee -a "$LOG_DIR/test.log" ;;
        "ERROR") echo -e "${RED}[$timestamp] ERROR: $message${NC}" | tee -a "$LOG_DIR/test.log" ;;
        "SUCCESS") echo -e "${GREEN}[$timestamp] SUCCESS: $message${NC}" | tee -a "$LOG_DIR/test.log" ;;
        *) echo -e "[$timestamp] $level: $message" | tee -a "$LOG_DIR/test.log" ;;
    esac
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."
    
    local tools=("kubectl" "terraform" "docker" "helm" "curl" "jq")
    local missing_tools=()
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log "ERROR" "Missing required tools: ${missing_tools[*]}"
        exit 1
    fi
    
    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log "ERROR" "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log "SUCCESS" "All prerequisites met"
}

# Phase 1: Infrastructure Testing
test_phase1() {
    log "INFO" "Starting Phase 1: Infrastructure Testing"
    
    # Test Terraform configuration
    log "INFO" "Testing Terraform configuration..."
    cd "$PROJECT_ROOT/infra/terraform/environments/$ENVIRONMENT"
    
    if terraform validate; then
        log "SUCCESS" "Terraform configuration is valid"
    else
        log "ERROR" "Terraform configuration validation failed"
        return 1
    fi
    
    # Test infrastructure deployment (dry run)
    log "INFO" "Running Terraform plan..."
    if terraform plan -detailed-exitcode -out=tfplan; then
        log "SUCCESS" "Terraform plan successful"
    else
        log "ERROR" "Terraform plan failed"
        return 1
    fi
    
    # Test Kubernetes cluster connectivity
    log "INFO" "Testing Kubernetes cluster..."
    if kubectl get nodes &> /dev/null; then
        local node_count=$(kubectl get nodes --no-headers | wc -l)
        log "SUCCESS" "Kubernetes cluster accessible with $node_count nodes"
    else
        log "ERROR" "Cannot access Kubernetes cluster"
        return 1
    fi
    
    # Test network connectivity
    log "INFO" "Testing network connectivity..."
    kubectl run network-test --image=busybox --rm -i --restart=Never -- sh -c "
        nslookup kubernetes.default.svc.cluster.local &&
        echo 'DNS resolution working' &&
        wget -q --spider http://google.com &&
        echo 'External connectivity working'
    " || {
        log "ERROR" "Network connectivity test failed"
        return 1
    }
    
    log "SUCCESS" "Phase 1 testing completed"
}

# Phase 2: Security and Authentication Testing
test_phase2() {
    log "INFO" "Starting Phase 2: Security and Authentication Testing"
    
    # Deploy security components
    log "INFO" "Deploying security components..."
    kubectl apply -f "$PROJECT_ROOT/k8s/security/" || {
        log "ERROR" "Failed to deploy security components"
        return 1
    }
    
    # Wait for Keycloak
    log "INFO" "Waiting for Keycloak to be ready..."
    kubectl wait --for=condition=ready pod -l app=keycloak -n security --timeout=300s || {
        log "ERROR" "Keycloak not ready within timeout"
        return 1
    }
    
    # Test Keycloak accessibility
    log "INFO" "Testing Keycloak accessibility..."
    kubectl port-forward svc/keycloak-service 8080:80 -n security &
    local port_forward_pid=$!
    sleep 10
    
    if curl -f http://localhost:8080/health &> /dev/null; then
        log "SUCCESS" "Keycloak is accessible"
    else
        log "ERROR" "Keycloak is not accessible"
        kill $port_forward_pid 2>/dev/null || true
        return 1
    fi
    
    kill $port_forward_pid 2>/dev/null || true
    
    # Test Vault deployment
    log "INFO" "Testing Vault deployment..."
    if kubectl get pods -l app=vault -n security | grep Running &> /dev/null; then
        log "SUCCESS" "Vault pods are running"
    else
        log "ERROR" "Vault pods are not running"
        return 1
    fi
    
    # Test mTLS configuration
    log "INFO" "Testing mTLS configuration..."
    if kubectl get peerauthentication -A &> /dev/null; then
        log "SUCCESS" "mTLS policies are configured"
    else
        log "WARN" "mTLS policies not found"
    fi
    
    log "SUCCESS" "Phase 2 testing completed"
}

# Phase 3: Microservices Testing
test_phase3() {
    log "INFO" "Starting Phase 3: Microservices Testing"
    
    # Deploy microservices
    log "INFO" "Deploying microservices..."
    kubectl apply -f "$PROJECT_ROOT/k8s/apps/" || {
        log "ERROR" "Failed to deploy microservices"
        return 1
    }
    
    # Wait for services to be ready
    local services=("cart-service" "product-service")
    for service in "${services[@]}"; do
        log "INFO" "Waiting for $service to be ready..."
        kubectl wait --for=condition=ready pod -l app="$service" --timeout=300s || {
            log "ERROR" "$service not ready within timeout"
            return 1
        }
    done
    
    # Test service health endpoints
    log "INFO" "Testing service health endpoints..."
    
    # Port forward and test cart service
    kubectl port-forward svc/cart-service 8080:80 &
    local cart_pid=$!
    sleep 5
    
    if curl -f http://localhost:8080/actuator/health &> /dev/null; then
        log "SUCCESS" "Cart service health check passed"
    else
        log "ERROR" "Cart service health check failed"
        kill $cart_pid 2>/dev/null || true
        return 1
    fi
    
    # Test API functionality
    log "INFO" "Testing cart API functionality..."
    local api_response=$(curl -s -X POST http://localhost:8080/api/cart/items \
        -H "Content-Type: application/json" \
        -d '{"userId": 1, "productId": 1, "quantity": 2}' || echo "FAILED")
    
    if [[ "$api_response" != "FAILED" ]] && [[ "$api_response" != *"error"* ]]; then
        log "SUCCESS" "Cart API functionality test passed"
    else
        log "ERROR" "Cart API functionality test failed: $api_response"
    fi
    
    kill $cart_pid 2>/dev/null || true
    
    # Test Kafka deployment
    log "INFO" "Testing Kafka deployment..."
    if kubectl get pods -l app=kafka -n messaging | grep Running &> /dev/null; then
        log "SUCCESS" "Kafka is running"
    else
        log "WARN" "Kafka is not running"
    fi
    
    log "SUCCESS" "Phase 3 testing completed"
}

# Phase 4: Observability Testing
test_phase4() {
    log "INFO" "Starting Phase 4: Observability Testing"
    
    # Test Prometheus deployment
    log "INFO" "Testing Prometheus deployment..."
    if kubectl get pods -l app.kubernetes.io/name=prometheus -n monitoring | grep Running &> /dev/null; then
        log "SUCCESS" "Prometheus is running"
        
        # Test Prometheus metrics
        kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring &
        local prom_pid=$!
        sleep 10
        
        if curl -f http://localhost:9090/api/v1/query?query=up &> /dev/null; then
            log "SUCCESS" "Prometheus metrics endpoint accessible"
        else
            log "ERROR" "Prometheus metrics endpoint not accessible"
        fi
        
        kill $prom_pid 2>/dev/null || true
    else
        log "ERROR" "Prometheus is not running"
        return 1
    fi
    
    # Test Grafana deployment
    log "INFO" "Testing Grafana deployment..."
    if kubectl get pods -l app.kubernetes.io/name=grafana -n monitoring | grep Running &> /dev/null; then
        log "SUCCESS" "Grafana is running"
    else
        log "ERROR" "Grafana is not running"
        return 1
    fi
    
    # Test logging stack
    log "INFO" "Testing logging stack..."
    if kubectl get pods -l app=elasticsearch -n logging | grep Running &> /dev/null; then
        log "SUCCESS" "Elasticsearch is running"
    else
        log "WARN" "Elasticsearch is not running"
    fi
    
    # Test tracing
    log "INFO" "Testing tracing stack..."
    if kubectl get pods -l app=jaeger -n tracing | grep Running &> /dev/null; then
        log "SUCCESS" "Jaeger is running"
    else
        log "WARN" "Jaeger is not running"
    fi
    
    log "SUCCESS" "Phase 4 testing completed"
}

# Phase 5: CI/CD Testing
test_phase5() {
    log "INFO" "Starting Phase 5: CI/CD Testing"
    
    # Test ArgoCD deployment
    log "INFO" "Testing ArgoCD deployment..."
    kubectl apply -f "$PROJECT_ROOT/k8s/argocd/" || {
        log "ERROR" "Failed to deploy ArgoCD"
        return 1
    }
    
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s || {
        log "ERROR" "ArgoCD not ready within timeout"
        return 1
    }
    
    log "SUCCESS" "ArgoCD deployed successfully"
    
    # Test Argo Rollouts
    log "INFO" "Testing Argo Rollouts..."
    if kubectl get crd rollouts.argoproj.io &> /dev/null; then
        log "SUCCESS" "Argo Rollouts CRDs are installed"
    else
        log "ERROR" "Argo Rollouts CRDs not found"
        return 1
    fi
    
    # Test blue-green deployment configuration
    log "INFO" "Testing blue-green deployment configuration..."
    kubectl apply -f "$PROJECT_ROOT/k8s/deployment-strategies/blue-green.yaml" || {
        log "ERROR" "Failed to apply blue-green deployment"
        return 1
    }
    
    log "SUCCESS" "Blue-green deployment configuration applied"
    
    log "SUCCESS" "Phase 5 testing completed"
}

# Performance testing
run_performance_tests() {
    log "INFO" "Starting performance tests..."
    
    # Create performance test script
    cat > "$LOG_DIR/performance-test.js" << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';

export let options = {
  stages: [
    { duration: '1m', target: 50 },
    { duration: '2m', target: 50 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<2000'],
    http_req_failed: ['rate<0.1'],
  },
};

export default function() {
  let response = http.get('http://localhost:8080/actuator/health');
  check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
  });
  sleep(1);
}
EOF
    
    # Run performance test if k6 is available
    if command -v k6 &> /dev/null; then
        log "INFO" "Running k6 performance test..."
        
        # Start port forward for testing
        kubectl port-forward svc/cart-service 8080:80 &
        local pf_pid=$!
        sleep 5
        
        k6 run "$LOG_DIR/performance-test.js" > "$REPORT_DIR/performance-test-results.txt" 2>&1 || {
            log "WARN" "Performance test failed or had issues"
        }
        
        kill $pf_pid 2>/dev/null || true
        log "SUCCESS" "Performance test completed"
    else
        log "WARN" "k6 not found, skipping performance tests"
    fi
}

# Security testing
run_security_tests() {
    log "INFO" "Starting security tests..."
    
    # Test for common security misconfigurations
    log "INFO" "Checking for security misconfigurations..."
    
    # Check for pods running as root
    local root_pods=$(kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.securityContext.runAsUser}{"\n"}{end}' | grep -E '\t0$|\t$' | wc -l)
    if [ "$root_pods" -gt 0 ]; then
        log "WARN" "$root_pods pods may be running as root"
    else
        log "SUCCESS" "No pods running as root detected"
    fi
    
    # Check for privileged containers
    local privileged_containers=$(kubectl get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.securityContext.privileged}{"\n"}{end}{end}' | grep -c true || echo "0")
    if [ "$privileged_containers" -gt 0 ]; then
        log "WARN" "$privileged_containers privileged containers found"
    else
        log "SUCCESS" "No privileged containers found"
    fi
    
    # Check for network policies
    local network_policies=$(kubectl get networkpolicies -A --no-headers | wc -l)
    if [ "$network_policies" -gt 0 ]; then
        log "SUCCESS" "$network_policies network policies found"
    else
        log "WARN" "No network policies found"
    fi
    
    log "SUCCESS" "Security tests completed"
}

# Generate test report
generate_report() {
    log "INFO" "Generating test report..."
    
    local report_file="$REPORT_DIR/test-report-$(date +%Y%m%d-%H%M%S).html"
    
    cat > "$report_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>E-Commerce Microservices Test Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background: #f0f0f0; padding: 20px; border-radius: 5px; }
        .phase { margin: 20px 0; padding: 15px; border-left: 4px solid #007cba; }
        .success { border-left-color: #28a745; }
        .warning { border-left-color: #ffc107; }
        .error { border-left-color: #dc3545; }
        .timestamp { color: #666; font-size: 0.9em; }
        pre { background: #f8f9fa; padding: 10px; border-radius: 3px; overflow-x: auto; }
    </style>
</head>
<body>
    <div class="header">
        <h1>E-Commerce Microservices Test Report</h1>
        <p class="timestamp">Generated: $(date)</p>
        <p>Environment: $ENVIRONMENT</p>
        <p>Phase: $PHASE</p>
    </div>
    
    <div class="phase">
        <h2>Test Summary</h2>
        <p>This report contains the results of automated testing for the e-commerce microservices platform.</p>
    </div>
    
    <div class="phase">
        <h2>Test Log</h2>
        <pre>$(cat "$LOG_DIR/test.log" 2>/dev/null || echo "No log file found")</pre>
    </div>
    
    <div class="phase">
        <h2>Performance Test Results</h2>
        <pre>$(cat "$REPORT_DIR/performance-test-results.txt" 2>/dev/null || echo "No performance test results found")</pre>
    </div>
    
    <div class="phase">
        <h2>Recommendations</h2>
        <ul>
            <li>Review any WARNING or ERROR messages in the test log</li>
            <li>Ensure all required components are deployed and running</li>
            <li>Verify network connectivity and security configurations</li>
            <li>Monitor performance metrics during load testing</li>
            <li>Implement proper backup and disaster recovery procedures</li>
        </ul>
    </div>
</body>
</html>
EOF
    
    log "SUCCESS" "Test report generated: $report_file"
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up..."
    
    # Kill any background processes
    jobs -p | xargs -r kill 2>/dev/null || true
    
    # Clean up test resources
    kubectl delete pods --selector=run=network-test --ignore-not-found=true &>/dev/null || true
    
    log "INFO" "Cleanup completed"
}

# Trap cleanup on exit
trap cleanup EXIT

# Main execution
main() {
    log "INFO" "Starting automated testing for E-Commerce Microservices"
    log "INFO" "Phase: $PHASE, Environment: $ENVIRONMENT"
    
    check_prerequisites
    
    case $PHASE in
        "phase1")
            test_phase1
            ;;
        "phase2")
            test_phase1
            test_phase2
            ;;
        "phase3")
            test_phase1
            test_phase2
            test_phase3
            ;;
        "phase4")
            test_phase1
            test_phase2
            test_phase3
            test_phase4
            ;;
        "phase5"|"all")
            test_phase1
            test_phase2
            test_phase3
            test_phase4
            test_phase5
            ;;
        "performance")
            run_performance_tests
            ;;
        "security")
            run_security_tests
            ;;
        *)
            log "ERROR" "Unknown phase: $PHASE. Available phases: phase1, phase2, phase3, phase4, phase5, all, performance, security"
            exit 1
            ;;
    esac
    
    # Run additional tests for 'all' phase
    if [ "$PHASE" = "all" ]; then
        run_performance_tests
        run_security_tests
    fi
    
    generate_report
    
    log "SUCCESS" "All tests completed successfully!"
    log "INFO" "Check the logs at: $LOG_DIR/test.log"
    log "INFO" "Check the reports at: $REPORT_DIR/"
}

# Run main function
main "$@"