#!/bin/bash

# Quick Test Script for Local Development
# Usage: ./scripts/quick-test.sh [service]

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SERVICE=${1:-"all"}
TIMEOUT=10

# Test functions
test_postgres() {
    echo -e "${BLUE}Testing PostgreSQL...${NC}"
    
    if kubectl run pg-test --image=postgres:15-alpine --rm -i --restart=Never --quiet -- \
        psql -h postgres-local -U postgres -d ecommerce -c "SELECT version();" 2>/dev/null; then
        echo -e "  ✓ PostgreSQL: ${GREEN}Connected${NC}"
        return 0
    else
        echo -e "  ✗ PostgreSQL: ${RED}Connection failed${NC}"
        return 1
    fi
}

test_redis() {
    echo -e "${BLUE}Testing Redis...${NC}"
    
    if kubectl run redis-test --image=redis:7-alpine --rm -i --restart=Never --quiet -- \
        redis-cli -h redis-local ping 2>/dev/null | grep -q "PONG"; then
        echo -e "  ✓ Redis: ${GREEN}Connected${NC}"
        return 0
    else
        echo -e "  ✗ Redis: ${RED}Connection failed${NC}"
        return 1
    fi
}

test_cart_service() {
    echo -e "${BLUE}Testing Cart Service...${NC}"
    
    # Start port forward in background
    kubectl port-forward svc/cart-service-local 8080:80 >/dev/null 2>&1 &
    local pf_pid=$!
    sleep 3
    
    local success=0
    
    # Test health endpoint
    if curl -f -s --max-time $TIMEOUT http://localhost:8080/actuator/health >/dev/null 2>&1; then
        echo -e "  ✓ Cart Service Health: ${GREEN}OK${NC}"
        
        # Test cart functionality
        local response=$(curl -s --max-time $TIMEOUT -X POST http://localhost:8080/api/cart/items \
            -H "Content-Type: application/json" \
            -d '{"userId": 1, "productId": 1, "quantity": 2}' 2>/dev/null)
        
        if [[ $? -eq 0 ]] && [[ "$response" != *"error"* ]] && [[ "$response" != "" ]]; then
            echo -e "  ✓ Cart API: ${GREEN}Functional${NC}"
            success=1
        else
            echo -e "  ✗ Cart API: ${RED}Not functional${NC}"
            echo -e "    Response: $response"
        fi
        
        # Test metrics endpoint
        if curl -f -s --max-time $TIMEOUT http://localhost:8080/actuator/prometheus >/dev/null 2>&1; then
            echo -e "  ✓ Cart Metrics: ${GREEN}Available${NC}"
        else
            echo -e "  ⚠ Cart Metrics: ${YELLOW}Not available${NC}"
        fi
        
    else
        echo -e "  ✗ Cart Service Health: ${RED}Failed${NC}"
    fi
    
    # Clean up port forward
    kill $pf_pid 2>/dev/null || true
    return $success
}

test_product_service() {
    echo -e "${BLUE}Testing Product Service...${NC}"
    
    # Start port forward in background
    kubectl port-forward svc/product-service-local 3001:80 >/dev/null 2>&1 &
    local pf_pid=$!
    sleep 3
    
    local success=0
    
    # Test health endpoint
    if curl -f -s --max-time $TIMEOUT http://localhost:3001/health >/dev/null 2>&1; then
        echo -e "  ✓ Product Service Health: ${GREEN}OK${NC}"
        
        # Test product API
        local response=$(curl -s --max-time $TIMEOUT http://localhost:3001/api/products 2>/dev/null)
        
        if [[ $? -eq 0 ]] && [[ "$response" != *"error"* ]]; then
            echo -e "  ✓ Product API: ${GREEN}Functional${NC}"
            success=1
        else
            echo -e "  ✗ Product API: ${RED}Not functional${NC}"
        fi
        
    else
        echo -e "  ✗ Product Service Health: ${RED}Failed${NC}"
    fi
    
    # Clean up port forward
    kill $pf_pid 2>/dev/null || true
    return $success
}

test_monitoring() {
    echo -e "${BLUE}Testing Monitoring...${NC}"
    
    # Check if Prometheus is running
    if kubectl get pods -l app.kubernetes.io/name=prometheus -n monitoring --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "  ✓ Prometheus: ${GREEN}Running${NC}"
    else
        echo -e "  ⚠ Prometheus: ${YELLOW}Not running${NC}"
    fi
    
    # Check if Grafana is running
    if kubectl get pods -l app.kubernetes.io/name=grafana -n monitoring --no-headers 2>/dev/null | grep -q "Running"; then
        echo -e "  ✓ Grafana: ${GREEN}Running${NC}"
    else
        echo -e "  ⚠ Grafana: ${YELLOW}Not running${NC}"
    fi
}

test_all() {
    echo -e "${YELLOW}🧪 Running comprehensive tests...${NC}\n"
    
    local total_tests=0
    local passed_tests=0
    
    # Infrastructure tests
    ((total_tests++))
    if test_postgres; then ((passed_tests++)); fi
    
    ((total_tests++))
    if test_redis; then ((passed_tests++)); fi
    
    # Service tests
    if kubectl get deployment cart-service-local &>/dev/null; then
        ((total_tests++))
        if test_cart_service; then ((passed_tests++)); fi
    fi
    
    if kubectl get deployment product-service-local &>/dev/null; then
        ((total_tests++))
        if test_product_service; then ((passed_tests++)); fi
    fi
    
    # Monitoring tests (non-critical)
    test_monitoring
    
    # Summary
    echo -e "\n${YELLOW}Test Summary:${NC}"
    if [ $passed_tests -eq $total_tests ]; then
        echo -e "  ${GREEN}✓ All tests passed ($passed_tests/$total_tests)${NC}"
        return 0
    else
        echo -e "  ${RED}✗ Some tests failed ($passed_tests/$total_tests)${NC}"
        return 1
    fi
}

load_test() {
    echo -e "${BLUE}Running basic load test...${NC}"
    
    kubectl port-forward svc/cart-service-local 8080:80 >/dev/null 2>&1 &
    local pf_pid=$!
    sleep 3
    
    # Simple load test using curl
    echo -e "  Running 100 requests with 10 concurrent connections..."
    
    if command -v ab &> /dev/null; then
        # Use Apache Bench if available
        ab -n 100 -c 10 -q http://localhost:8080/actuator/health
        echo -e "  ✓ Load test completed with Apache Bench"
    else
        # Fallback to simple curl loop
        for i in {1..20}; do
            curl -s http://localhost:8080/actuator/health >/dev/null &
        done
        wait
        echo -e "  ✓ Load test completed with curl"
    fi
    
    kill $pf_pid 2>/dev/null || true
}

# Show pod status
show_pod_status() {
    echo -e "${BLUE}Pod Status:${NC}"
    kubectl get pods -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp" 2>/dev/null || echo "No pods found"
}

# Show service status
show_service_status() {
    echo -e "\n${BLUE}Service Status:${NC}"
    kubectl get svc -o custom-columns="NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,PORT(S):.spec.ports[*].port" 2>/dev/null || echo "No services found"
}

# Check resource usage
check_resources() {
    echo -e "\n${BLUE}Resource Usage:${NC}"
    if command -v kubectl &> /dev/null && kubectl top pods &>/dev/null; then
        kubectl top pods
    else
        echo "  Resource metrics not available (metrics-server not installed)"
    fi
}

# Main function
main() {
    echo -e "${GREEN}🚀 Quick Test Suite for Local Development${NC}\n"
    
    case $SERVICE in
        "postgres")
            test_postgres
            ;;
        "redis")
            test_redis
            ;;
        "cart")
            test_cart_service
            ;;
        "product")
            test_product_service
            ;;
        "monitoring")
            test_monitoring
            ;;
        "load")
            load_test
            ;;
        "status")
            show_pod_status
            show_service_status
            check_resources
            ;;
        "all")
            test_all
            ;;
        *)
            echo "Usage: $0 {all|postgres|redis|cart|product|monitoring|load|status}"
            echo ""
            echo "Test options:"
            echo "  all        - Run all tests"
            echo "  postgres   - Test PostgreSQL connectivity"
            echo "  redis      - Test Redis connectivity"
            echo "  cart       - Test Cart Service API"
            echo "  product    - Test Product Service API"
            echo "  monitoring - Check monitoring stack"
            echo "  load       - Run basic load test"
            echo "  status     - Show pod and service status"
            exit 1
            ;;
    esac
}

# Cleanup on exit
cleanup() {
    # Kill any background port-forward processes
    jobs -p | xargs -r kill 2>/dev/null || true
}

trap cleanup EXIT

# Run main function
main "$@"