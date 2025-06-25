#!/bin/bash

# macOS Development Environment Setup Script
# Usage: ./scripts/install-macos.sh

set -euo pipefail

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

# Check if running on macOS
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        log "ERROR" "This script is designed for macOS only"
        log "INFO" "For Linux, use: ./scripts/install-linux.sh"
        log "INFO" "For Windows, see: docs/LOCAL_SETUP_REQUIREMENTS.md"
        exit 1
    fi
    log "SUCCESS" "Running on macOS"
}

# Install Homebrew
install_homebrew() {
    if command -v brew &> /dev/null; then
        log "INFO" "Homebrew already installed: $(brew --version | head -1)"
        return 0
    fi
    
    log "INFO" "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH for Apple Silicon Macs
    if [[ -f "/opt/homebrew/bin/brew" ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
    
    if command -v brew &> /dev/null; then
        log "SUCCESS" "Homebrew installed successfully"
    else
        log "ERROR" "Homebrew installation failed"
        exit 1
    fi
}

# Update Homebrew
update_homebrew() {
    log "INFO" "Updating Homebrew..."
    brew update
    log "SUCCESS" "Homebrew updated"
}

# Install required tools
install_required_tools() {
    log "INFO" "Installing required tools..."
    
    local tools=(
        "kubectl:Kubernetes CLI"
        "git:Git version control"
    )
    
    for tool_pair in "${tools[@]}"; do
        IFS=':' read -r tool description <<< "$tool_pair"
        
        if command -v "$tool" &> /dev/null; then
            log "INFO" "$description already installed: $($tool --version | head -1 | cut -d' ' -f1-3)"
        else
            log "INFO" "Installing $description..."
            brew install "$tool"
            log "SUCCESS" "$description installed"
        fi
    done
}

# Install Kubernetes tools
install_kubernetes_tools() {
    log "INFO" "Installing Kubernetes tools..."
    
    local k8s_tools=(
        "kind:Local Kubernetes clusters"
        "helm:Kubernetes package manager"
        "k9s:Kubernetes UI"
        "stern:Multi-pod log viewer"
    )
    
    for tool_pair in "${k8s_tools[@]}"; do
        IFS=':' read -r tool description <<< "$tool_pair"
        
        if command -v "$tool" &> /dev/null; then
            log "INFO" "$description already installed"
        else
            log "INFO" "Installing $description..."
            brew install "$tool"
            log "SUCCESS" "$description installed"
        fi
    done
}

# Install utility tools
install_utility_tools() {
    log "INFO" "Installing utility tools..."
    
    local utils=(
        "jq:JSON processor"
        "curl:HTTP client"
        "wget:File downloader"
    )
    
    for tool_pair in "${utils[@]}"; do
        IFS=':' read -r tool description <<< "$tool_pair"
        
        if command -v "$tool" &> /dev/null; then
            log "INFO" "$description already installed"
        else
            log "INFO" "Installing $description..."
            brew install "$tool"
            log "SUCCESS" "$description installed"
        fi
    done
}

# Install development environments
install_dev_environments() {
    log "INFO" "Installing development environments..."
    
    # Java
    if command -v java &> /dev/null; then
        log "INFO" "Java already installed: $(java -version 2>&1 | head -1)"
    else
        log "INFO" "Installing OpenJDK 17..."
        brew install openjdk@17
        
        # Link Java for system use
        if [[ -d "/opt/homebrew/opt/openjdk@17" ]]; then
            sudo ln -sfn /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk
        elif [[ -d "/usr/local/opt/openjdk@17" ]]; then
            sudo ln -sfn /usr/local/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk
        fi
        
        log "SUCCESS" "Java 17 installed"
    fi
    
    # Node.js
    if command -v node &> /dev/null; then
        log "INFO" "Node.js already installed: $(node --version)"
    else
        log "INFO" "Installing Node.js 18..."
        brew install node@18
        log "SUCCESS" "Node.js 18 installed"
    fi
    
    # Python
    if command -v python3 &> /dev/null; then
        log "INFO" "Python already installed: $(python3 --version)"
    else
        log "INFO" "Installing Python 3.11..."
        brew install python@3.11
        log "SUCCESS" "Python 3.11 installed"
    fi
}

# Install performance testing tools
install_performance_tools() {
    log "INFO" "Installing performance testing tools..."
    
    # Apache Bench (comes with httpd)
    if command -v ab &> /dev/null; then
        log "INFO" "Apache Bench already installed"
    else
        log "INFO" "Installing Apache HTTP Server (for ab tool)..."
        brew install httpd
        log "SUCCESS" "Apache Bench installed"
    fi
    
    # K6 (performance testing)
    if command -v k6 &> /dev/null; then
        log "INFO" "K6 already installed"
    else
        log "INFO" "Installing K6 performance testing tool..."
        brew install k6
        log "SUCCESS" "K6 installed"
    fi
}

# Check Docker Desktop
check_docker() {
    log "INFO" "Checking Docker installation..."
    
    if command -v docker &> /dev/null; then
        if docker info &> /dev/null; then
            log "SUCCESS" "Docker is installed and running: $(docker --version)"
            return 0
        else
            log "WARN" "Docker is installed but not running"
            log "INFO" "Please start Docker Desktop application"
            return 1
        fi
    else
        log "WARN" "Docker is not installed"
        log "INFO" "Please install Docker Desktop manually:"
        log "INFO" "  1. Visit: https://docs.docker.com/desktop/install/mac-install/"
        log "INFO" "  2. Download Docker Desktop for Mac"
        log "INFO" "  3. Install and start the application"
        log "INFO" "  4. Enable Kubernetes in Docker Desktop settings (optional)"
        return 1
    fi
}

# Setup shell environment
setup_shell_environment() {
    log "INFO" "Setting up shell environment..."
    
    local shell_rc=""
    if [[ "$SHELL" == *"zsh"* ]]; then
        shell_rc="$HOME/.zshrc"
    elif [[ "$SHELL" == *"bash"* ]]; then
        shell_rc="$HOME/.bash_profile"
    else
        log "WARN" "Unknown shell: $SHELL"
        return 0
    fi
    
    # Create shell rc file if it doesn't exist
    touch "$shell_rc"
    
    # Add useful aliases
    if ! grep -q "# E-Commerce Development Aliases" "$shell_rc"; then
        log "INFO" "Adding development aliases to $shell_rc..."
        cat >> "$shell_rc" << 'EOF'

# E-Commerce Development Aliases
alias k='kubectl'
alias kgp='kubectl get pods'
alias kgs='kubectl get svc'
alias kgd='kubectl get deployments'
alias klogs='kubectl logs -f'
alias kdesc='kubectl describe'
alias kctx='kubectl config current-context'
alias docker-clean='docker system prune -f'
alias local-dev='./scripts/local-dev.sh'
alias quick-test='./scripts/quick-test.sh'

# Java environment
export JAVA_HOME="/Library/Java/JavaVirtualMachines/openjdk-17.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
EOF
        log "SUCCESS" "Development aliases added"
    else
        log "INFO" "Development aliases already configured"
    fi
}

# Verify installation
verify_installation() {
    log "INFO" "Verifying installation..."
    
    local required_tools=(
        "docker:Docker"
        "kubectl:Kubernetes CLI"
        "git:Git"
    )
    
    local optional_tools=(
        "kind:Kind"
        "helm:Helm"
        "k9s:K9s"
        "stern:Stern"
        "jq:jq"
        "java:Java"
        "node:Node.js"
        "python3:Python"
        "ab:Apache Bench"
        "k6:K6"
    )
    
    local missing_required=0
    local missing_optional=0
    
    echo -e "\n${BLUE}=== Required Tools ===${NC}"
    for tool_pair in "${required_tools[@]}"; do
        IFS=':' read -r cmd name <<< "$tool_pair"
        
        if command -v "$cmd" &> /dev/null; then
            echo -e "  ✅ $name: ${GREEN}Installed${NC}"
        else
            echo -e "  ❌ $name: ${RED}Missing${NC}"
            ((missing_required++))
        fi
    done
    
    echo -e "\n${BLUE}=== Optional Tools ===${NC}"
    for tool_pair in "${optional_tools[@]}"; do
        IFS=':' read -r cmd name <<< "$tool_pair"
        
        if command -v "$cmd" &> /dev/null; then
            echo -e "  ✅ $name: ${GREEN}Installed${NC}"
        else
            echo -e "  ⚠️  $name: ${YELLOW}Missing${NC}"
            ((missing_optional++))
        fi
    done
    
    echo -e "\n${BLUE}=== Summary ===${NC}"
    if [ $missing_required -eq 0 ]; then
        log "SUCCESS" "All required tools are installed!"
    else
        log "ERROR" "$missing_required required tool(s) missing"
    fi
    
    if [ $missing_optional -eq 0 ]; then
        log "SUCCESS" "All optional tools are installed!"
    else
        log "INFO" "$missing_optional optional tool(s) missing (this is okay)"
    fi
}

# Create desktop shortcuts (optional)
create_shortcuts() {
    log "INFO" "Creating development shortcuts..."
    
    # Create a simple script launcher
    cat > "$HOME/Desktop/E-Commerce Dev.command" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")/../../Documents/ai_project/MSA-1/e-commerce-microservices-sample" 2>/dev/null || {
    echo "Please update the path in this script to point to your project directory"
    read -p "Press enter to continue..."
    exit 1
}

echo "🚀 E-Commerce Microservices Development Environment"
echo "=================================================="
echo "1. Start local environment: ./scripts/local-dev.sh start"
echo "2. Run tests: ./scripts/quick-test.sh all"
echo "3. Check status: ./scripts/local-dev.sh status"
echo "4. View logs: ./scripts/local-dev.sh logs"
echo "5. Stop environment: ./scripts/local-dev.sh stop"
echo ""
echo "Current directory: $(pwd)"
echo ""

PS3="Choose an option: "
options=("Start Environment" "Run Tests" "Check Status" "View Logs" "Stop Environment" "Open Terminal Here" "Exit")

select opt in "${options[@]}"; do
    case $opt in
        "Start Environment")
            ./scripts/local-dev.sh start
            break
            ;;
        "Run Tests")
            ./scripts/quick-test.sh all
            break
            ;;
        "Check Status")
            ./scripts/local-dev.sh status
            read -p "Press enter to continue..."
            ;;
        "View Logs")
            ./scripts/local-dev.sh logs
            break
            ;;
        "Stop Environment")
            ./scripts/local-dev.sh stop
            break
            ;;
        "Open Terminal Here")
            open -a Terminal .
            break
            ;;
        "Exit")
            break
            ;;
        *) echo "Invalid option $REPLY";;
    esac
done
EOF
    
    chmod +x "$HOME/Desktop/E-Commerce Dev.command"
    log "SUCCESS" "Desktop shortcut created"
}

# Main installation process
main() {
    echo -e "${GREEN}🚀 E-Commerce Microservices Development Environment Setup${NC}"
    echo -e "${GREEN}==========================================================${NC}\n"
    
    check_macos
    install_homebrew
    update_homebrew
    install_required_tools
    install_kubernetes_tools
    install_utility_tools
    install_dev_environments
    install_performance_tools
    setup_shell_environment
    
    echo -e "\n${BLUE}=== Checking Docker Desktop ===${NC}"
    check_docker
    
    echo -e "\n${BLUE}=== Verification ===${NC}"
    verify_installation
    
    echo -e "\n${BLUE}=== Creating Shortcuts ===${NC}"
    create_shortcuts
    
    echo -e "\n${GREEN}🎉 Installation completed!${NC}"
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo "1. If Docker is not running, please start Docker Desktop"
    echo "2. Restart your terminal or run: source ~/.zshrc"
    echo "3. Navigate to your project directory"
    echo "4. Run: ./scripts/local-dev.sh start"
    echo "5. Run: ./scripts/quick-test.sh all"
    echo ""
    echo "📱 Desktop shortcut created: ~/Desktop/E-Commerce Dev.command"
    echo "📚 Documentation: docs/LOCAL_DEVELOPMENT_GUIDE.md"
    echo ""
    echo "For help, see: docs/LOCAL_SETUP_REQUIREMENTS.md"
}

# Error handling
trap 'log "ERROR" "Installation failed at line $LINENO"' ERR

# Run main function
main "$@"