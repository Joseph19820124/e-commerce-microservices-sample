#!/bin/bash

# Installation Verification Script
# Usage: ./scripts/verify-installation.sh

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
REQUIRED_PASSED=0
REQUIRED_TOTAL=0
OPTIONAL_PASSED=0
OPTIONAL_TOTAL=0

# Check tool function
check_tool() {
    local cmd=$1
    local name=$2
    local required=${3:-false}
    local check_running=${4:-false}
    
    if [ "$required" = "true" ]; then
        ((REQUIRED_TOTAL++))
    else
        ((OPTIONAL_TOTAL++))
    fi
    
    if command -v "$cmd" &> /dev/null; then
        local version=""
        case $cmd in
            "docker")
                if [ "$check_running" = "true" ]; then
                    if docker info &> /dev/null; then
                        version="✅ Running: $(docker --version | cut -d' ' -f3 | tr -d ',')"
                        if [ "$required" = "true" ]; then ((REQUIRED_PASSED++)); else ((OPTIONAL_PASSED++)); fi
                    else
                        version="⚠️  Installed but not running"
                    fi
                else
                    version="✅ $(docker --version | cut -d' ' -f3 | tr -d ',')"
                    if [ "$required" = "true" ]; then ((REQUIRED_PASSED++)); else ((OPTIONAL_PASSED++)); fi
                fi
                ;;
            "kubectl")
                version="✅ $(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' 2>/dev/null || kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo 'Unknown')"
                if [ "$required" = "true" ]; then ((REQUIRED_PASSED++)); else ((OPTIONAL_PASSED++)); fi
                ;;
            "java")
                version="✅ $(java -version 2>&1 | head -1 | cut -d'"' -f2)"
                if [ "$required" = "true" ]; then ((REQUIRED_PASSED++)); else ((OPTIONAL_PASSED++)); fi
                ;;
            "node")
                version="✅ $(node --version)"
                if [ "$required" = "true" ]; then ((REQUIRED_PASSED++)); else ((OPTIONAL_PASSED++)); fi
                ;;
            "python3")
                version="✅ $(python3 --version | cut -d' ' -f2)"
                if [ "$required" = "true" ]; then ((REQUIRED_PASSED++)); else ((OPTIONAL_PASSED++)); fi
                ;;
            *)
                version="✅ $(which $cmd)"
                if [ "$required" = "true" ]; then ((REQUIRED_PASSED++)); else ((OPTIONAL_PASSED++)); fi
                ;;
        esac
        
        printf "  %-20s %s\n" "$name:" "$version"
        return 0
    else
        if [ "$required" = "true" ]; then
            printf "  %-20s ${RED}❌ Not found${NC}\n" "$name:"
        else
            printf "  %-20s ${YELLOW}⚠️  Not found${NC}\n" "$name:"
        fi
        return 1
    fi
}

# Check cluster connectivity
check_kubernetes_cluster() {
    echo -e "\n${BLUE}=== Kubernetes Cluster ===${NC}"
    
    if kubectl cluster-info &> /dev/null; then
        local context=$(kubectl config current-context 2>/dev/null || echo "unknown")
        echo -e "  ${GREEN}✅ Cluster connected: $context${NC}"
        
        # Check if it's a local cluster
        if [[ "$context" == *"kind"* ]] || [[ "$context" == *"minikube"* ]] || [[ "$context" == *"docker-desktop"* ]]; then
            echo -e "  ${GREEN}✅ Local development cluster detected${NC}"
        else
            echo -e "  ${YELLOW}⚠️  External cluster detected${NC}"
        fi
        
        # Check nodes
        local nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
        local ready_nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep " Ready " | wc -l | tr -d ' ')
        echo -e "  ${GREEN}✅ Nodes: $ready_nodes/$nodes ready${NC}"
        
        return 0
    else
        echo -e "  ${YELLOW}⚠️  No Kubernetes cluster connected${NC}"
        echo -e "  ${BLUE}💡 To set up a local cluster:${NC}"
        echo -e "     • Docker Desktop: Enable Kubernetes in settings"
        echo -e "     • Kind: kind create cluster --name ecommerce-local"
        echo -e "     • Minikube: minikube start"
        return 1
    fi
}

# Check development environments
check_dev_environments() {
    echo -e "\n${BLUE}=== Development Environment Checks ===${NC}"
    
    # Check JAVA_HOME
    if [ -n "${JAVA_HOME:-}" ]; then
        echo -e "  ${GREEN}✅ JAVA_HOME: $JAVA_HOME${NC}"
    else
        echo -e "  ${YELLOW}⚠️  JAVA_HOME not set${NC}"
        echo -e "     Add to your shell rc: export JAVA_HOME=\"/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home\""
    fi
    
    # Check Node.js modules
    if command -v npm &> /dev/null; then
        echo -e "  ${GREEN}✅ npm: $(npm --version)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  npm not found${NC}"
    fi
    
    # Check Python pip
    if command -v pip3 &> /dev/null; then
        echo -e "  ${GREEN}✅ pip3: $(pip3 --version | cut -d' ' -f2)${NC}"
    else
        echo -e "  ${YELLOW}⚠️  pip3 not found${NC}"
    fi
}

# Check project structure
check_project_structure() {
    echo -e "\n${BLUE}=== Project Structure ===${NC}"
    
    local project_files=(
        "cart-cna-microservice"
        "products-cna-microservice"
        "users-cna-microservice"
        "scripts/local-dev.sh"
        "scripts/quick-test.sh"
        "docs/LOCAL_DEVELOPMENT_GUIDE.md"
    )
    
    local missing_files=()
    
    for file in "${project_files[@]}"; do
        if [ -e "$file" ]; then
            echo -e "  ${GREEN}✅ $file${NC}"
        else
            echo -e "  ${RED}❌ $file${NC}"
            missing_files+=("$file")
        fi
    done
    
    if [ ${#missing_files[@]} -eq 0 ]; then
        echo -e "  ${GREEN}✅ All project files present${NC}"
        return 0
    else
        echo -e "  ${YELLOW}⚠️  ${#missing_files[@]} file(s) missing${NC}"
        return 1
    fi
}

# Test Docker functionality
test_docker_functionality() {
    echo -e "\n${BLUE}=== Docker Functionality Test ===${NC}"
    
    if ! command -v docker &> /dev/null; then
        echo -e "  ${RED}❌ Docker not installed${NC}"
        return 1
    fi
    
    if ! docker info &> /dev/null; then
        echo -e "  ${RED}❌ Docker not running${NC}"
        echo -e "     Please start Docker Desktop"
        return 1
    fi
    
    # Test basic Docker functionality
    echo -e "  ${BLUE}Testing basic Docker functionality...${NC}"
    
    if docker run --rm hello-world &> /dev/null; then
        echo -e "  ${GREEN}✅ Docker can run containers${NC}"
    else
        echo -e "  ${RED}❌ Docker cannot run containers${NC}"
        return 1
    fi
    
    # Check Docker Kubernetes (if enabled)
    if kubectl config get-contexts | grep -q "docker-desktop"; then
        echo -e "  ${GREEN}✅ Docker Desktop Kubernetes available${NC}"
    else
        echo -e "  ${YELLOW}⚠️  Docker Desktop Kubernetes not enabled${NC}"
        echo -e "     Enable in Docker Desktop settings for easier local development"
    fi
    
    return 0
}

# Performance and resource check
check_system_resources() {
    echo -e "\n${BLUE}=== System Resources ===${NC}"
    
    # Check available memory
    if command -v free &> /dev/null; then
        local memory_gb=$(free -g | awk '/^Mem:/{print $2}')
        echo -e "  ${GREEN}✅ Memory: ${memory_gb}GB${NC}"
        
        if [ "$memory_gb" -lt 8 ]; then
            echo -e "  ${YELLOW}⚠️  Less than 8GB RAM detected. Consider upgrading for better performance.${NC}"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        local memory_gb=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}')
        echo -e "  ${GREEN}✅ Memory: ${memory_gb}GB${NC}"
        
        if [ "$memory_gb" -lt 8 ]; then
            echo -e "  ${YELLOW}⚠️  Less than 8GB RAM detected. Consider upgrading for better performance.${NC}"
        fi
    fi
    
    # Check CPU cores
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local cpu_cores=$(sysctl -n hw.ncpu)
        echo -e "  ${GREEN}✅ CPU cores: $cpu_cores${NC}"
        
        if [ "$cpu_cores" -lt 4 ]; then
            echo -e "  ${YELLOW}⚠️  Less than 4 CPU cores detected. Performance may be limited.${NC}"
        fi
    elif command -v nproc &> /dev/null; then
        local cpu_cores=$(nproc)
        echo -e "  ${GREEN}✅ CPU cores: $cpu_cores${NC}"
        
        if [ "$cpu_cores" -lt 4 ]; then
            echo -e "  ${YELLOW}⚠️  Less than 4 CPU cores detected. Performance may be limited.${NC}"
        fi
    fi
    
    # Check disk space
    local disk_space=$(df -h . | awk 'NR==2 {print $4}')
    echo -e "  ${GREEN}✅ Available disk space: $disk_space${NC}"
}

# Provide recommendations
provide_recommendations() {
    echo -e "\n${BLUE}=== Recommendations ===${NC}"
    
    local recommendations=()
    
    if ! command -v docker &> /dev/null || ! docker info &> /dev/null; then
        recommendations+=("Install and start Docker Desktop")
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        recommendations+=("Set up a local Kubernetes cluster (Docker Desktop, Kind, or Minikube)")
    fi
    
    if [ -z "${JAVA_HOME:-}" ]; then
        recommendations+=("Set JAVA_HOME environment variable")
    fi
    
    if ! command -v helm &> /dev/null; then
        recommendations+=("Install Helm for easier Kubernetes package management")
    fi
    
    if ! command -v k9s &> /dev/null; then
        recommendations+=("Install k9s for better Kubernetes management experience")
    fi
    
    if [ ${#recommendations[@]} -eq 0 ]; then
        echo -e "  ${GREEN}🎉 Your setup looks great! No recommendations.${NC}"
    else
        echo -e "  ${YELLOW}Consider the following improvements:${NC}"
        for rec in "${recommendations[@]}"; do
            echo -e "    • $rec"
        done
    fi
}

# Main verification function
main() {
    echo -e "${GREEN}🔍 E-Commerce Microservices Development Environment Verification${NC}"
    echo -e "${GREEN}=============================================================${NC}\n"
    
    # Required tools
    echo -e "${BLUE}=== Required Tools ===${NC}"
    check_tool "docker" "Docker" true true
    check_tool "kubectl" "Kubernetes CLI" true
    check_tool "git" "Git" true
    
    # Optional but recommended tools
    echo -e "\n${BLUE}=== Kubernetes Tools ===${NC}"
    check_tool "kind" "Kind" false
    check_tool "helm" "Helm" false
    check_tool "k9s" "K9s" false
    check_tool "stern" "Stern" false
    
    # Development environments
    echo -e "\n${BLUE}=== Development Environments ===${NC}"
    check_tool "java" "Java JDK" false
    check_tool "node" "Node.js" false
    check_tool "python3" "Python" false
    
    # Utility tools
    echo -e "\n${BLUE}=== Utility Tools ===${NC}"
    check_tool "jq" "JSON Processor" false
    check_tool "curl" "HTTP Client" false
    check_tool "ab" "Apache Bench" false
    check_tool "k6" "K6 Load Testing" false
    
    # Additional checks
    check_kubernetes_cluster
    check_dev_environments
    check_project_structure
    test_docker_functionality
    check_system_resources
    
    # Summary
    echo -e "\n${BLUE}=== Summary ===${NC}"
    echo -e "Required tools: ${GREEN}$REQUIRED_PASSED${NC}/${BLUE}$REQUIRED_TOTAL${NC}"
    echo -e "Optional tools: ${GREEN}$OPTIONAL_PASSED${NC}/${BLUE}$OPTIONAL_TOTAL${NC}"
    
    if [ $REQUIRED_PASSED -eq $REQUIRED_TOTAL ]; then
        echo -e "\n${GREEN}🎉 All required tools are ready!${NC}"
        echo -e "\n${BLUE}Next steps:${NC}"
        echo -e "  1. Run: ${GREEN}./scripts/local-dev.sh start${NC}"
        echo -e "  2. Test: ${GREEN}./scripts/quick-test.sh all${NC}"
        echo -e "  3. Explore: ${GREEN}./scripts/local-dev.sh status${NC}"
    else
        echo -e "\n${RED}❌ Missing required tools. Please install them first.${NC}"
        echo -e "\n${BLUE}Installation help:${NC}"
        echo -e "  • macOS: ${GREEN}./scripts/install-macos.sh${NC}"
        echo -e "  • Linux: ${GREEN}./scripts/install-linux.sh${NC}"
        echo -e "  • Manual: ${GREEN}docs/LOCAL_SETUP_REQUIREMENTS.md${NC}"
    fi
    
    provide_recommendations
    
    echo -e "\n${BLUE}📚 Documentation:${NC}"
    echo -e "  • Setup: docs/LOCAL_SETUP_REQUIREMENTS.md"
    echo -e "  • Development: docs/LOCAL_DEVELOPMENT_GUIDE.md"
    echo -e "  • Testing: docs/PRODUCTION_TESTING_PLAN.md"
}

# Run verification
main "$@"