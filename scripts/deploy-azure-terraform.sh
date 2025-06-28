#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO") echo -e "${BLUE}[$timestamp] INFO: $message${NC}" ;;
        "WARN") echo -e "${YELLOW}[$timestamp] WARN: $message${NC}" ;;
        "ERROR") echo -e "${RED}[$timestamp] ERROR: $message${NC}" ;;
        "SUCCESS") echo -e "${GREEN}[$timestamp] SUCCESS: $message${NC}" ;;
    esac
}

# 检查前置条件
check_prerequisites() {
    log "INFO" "检查前置条件..."
    
    # 检查 Terraform
    if ! command -v terraform &> /dev/null; then
        log "ERROR" "Terraform 未安装，请先安装 Terraform"
        exit 1
    fi
    
    # 检查 Azure CLI
    if ! command -v az &> /dev/null; then
        log "WARN" "Azure CLI 未安装，正在尝试安装..."
        if [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install azure-cli
            else
                log "ERROR" "请先安装 Homebrew 或手动安装 Azure CLI"
                exit 1
            fi
        else
            log "ERROR" "请手动安装 Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
            exit 1
        fi
    fi
    
    log "SUCCESS" "前置条件检查完成"
}

# Azure 登录
azure_login() {
    log "INFO" "检查 Azure 登录状态..."
    
    if ! az account show &> /dev/null; then
        log "INFO" "需要登录到 Azure..."
        echo "即将打开浏览器进行 Azure 认证"
        read -p "按 Enter 继续..."
        
        az login
        
        if [ $? -eq 0 ]; then
            log "SUCCESS" "Azure 登录成功"
        else
            log "ERROR" "Azure 登录失败"
            exit 1
        fi
    else
        log "SUCCESS" "已登录到 Azure"
    fi
    
    # 显示当前账户信息
    log "INFO" "当前 Azure 账户信息:"
    az account show --query "{Name:name, SubscriptionId:id, TenantId:tenantId}" -o table
}

# 更新 IP 白名单
update_ip_whitelist() {
    log "INFO" "更新 IP 白名单..."
    
    # 获取公网 IP
    MY_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s ipv4.icanhazip.com 2>/dev/null || echo "")
    
    if [ -n "$MY_IP" ] && [[ $MY_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log "INFO" "检测到公网 IP: $MY_IP"
        
        # 更新 terraform.tfvars
        if [ -f "terraform/azure/environments/dev/terraform.tfvars" ]; then
            sed -i.bak "s/\"0.0.0.0\"/\"$MY_IP\"/" terraform/azure/environments/dev/terraform.tfvars
            log "SUCCESS" "IP 白名单已更新为: $MY_IP"
        fi
    else
        log "WARN" "无法获取有效的 IPv4 地址，将使用 0.0.0.0（允许所有 IP）"
    fi
}

# Terraform 初始化
terraform_init() {
    log "INFO" "初始化 Terraform..."
    cd terraform/azure
    
    terraform init
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Terraform 初始化完成"
    else
        log "ERROR" "Terraform 初始化失败"
        exit 1
    fi
}

# Terraform 计划
terraform_plan() {
    log "INFO" "生成 Terraform 执行计划..."
    
    terraform plan -var-file=environments/dev/terraform.tfvars -out=tfplan
    
    if [ $? -eq 0 ]; then
        log "SUCCESS" "Terraform 计划生成完成"
        echo ""
        log "INFO" "计划摘要已保存为 tfplan 文件"
        return 0
    else
        log "ERROR" "Terraform 计划生成失败"
        return 1
    fi
}

# Terraform 应用
terraform_apply() {
    log "INFO" "开始部署 Azure 基础设施..."
    
    echo "即将执行以下操作："
    echo "- 创建 Azure 资源组"
    echo "- 部署 PostgreSQL 数据库"
    echo "- 部署 Redis 缓存"
    echo "- 配置 Application Insights"
    echo "- 设置 Log Analytics"
    echo ""
    
    read -p "确认要继续部署吗？(y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        terraform apply tfplan
        
        if [ $? -eq 0 ]; then
            log "SUCCESS" "Azure 基础设施部署完成！"
            return 0
        else
            log "ERROR" "Azure 基础设施部署失败"
            return 1
        fi
    else
        log "INFO" "用户取消了部署"
        return 1
    fi
}

# 生成连接信息
generate_connection_info() {
    log "INFO" "生成连接配置信息..."
    
    # 获取 Terraform 输出
    terraform output -json > terraform-outputs.json
    
    # 创建环境配置文件
    cat > ../../.env.azure-hybrid <<EOF
# Azure 混合环境配置
# 由 Terraform 自动生成于 $(date)

# PostgreSQL 配置
DATABASE_HOST=$(terraform output -raw postgresql_fqdn)
DATABASE_NAME=ecommerce
DATABASE_USER=$(terraform output -raw postgresql_admin_username)
DATABASE_PASSWORD=$(terraform output -raw postgresql_admin_password)
DATABASE_URL="jdbc:postgresql://\${DATABASE_HOST}:5432/\${DATABASE_NAME}?sslmode=require"

# Redis 配置
REDIS_HOST=$(terraform output -raw redis_hostname)
REDIS_PORT=$(terraform output -raw redis_ssl_port)
REDIS_PASSWORD=$(terraform output -raw redis_primary_access_key)
REDIS_SSL=true

# Application Insights
APPLICATIONINSIGHTS_CONNECTION_STRING=$(terraform output -raw application_insights_connection_string)

# Spring Profile
SPRING_PROFILES_ACTIVE=azure-hybrid
EOF
    
    log "SUCCESS" "环境配置已保存到 .env.azure-hybrid"
}

# 部署后验证
post_deployment_verification() {
    log "INFO" "执行部署后验证..."
    
    # 测试数据库连接
    log "INFO" "测试数据库连接..."
    DB_HOST=$(terraform output -raw postgresql_fqdn)
    DB_USER=$(terraform output -raw postgresql_admin_username)
    DB_PASS=$(terraform output -raw postgresql_admin_password)
    
    # 使用 Docker 测试连接
    if docker run --rm postgres:15 pg_isready -h "$DB_HOST" -p 5432 -U "$DB_USER" > /dev/null 2>&1; then
        log "SUCCESS" "数据库连接测试成功"
    else
        log "WARN" "数据库连接测试失败，可能需要等待服务启动完成"
    fi
    
    # 显示资源信息
    log "INFO" "部署的资源信息:"
    az resource list --resource-group $(terraform output -raw resource_group_name) --output table
}

# 清理函数
cleanup() {
    log "INFO" "清理临时文件..."
    rm -f tfplan terraform-outputs.json
}

# 主函数
main() {
    log "INFO" "开始 Azure Terraform 部署流程..."
    
    # 设置清理陷阱
    trap cleanup EXIT
    
    # 检查是否在正确的目录
    if [ ! -f "terraform/azure/main.tf" ]; then
        log "ERROR" "请在项目根目录执行此脚本"
        exit 1
    fi
    
    # 执行部署步骤
    check_prerequisites
    azure_login
    update_ip_whitelist
    terraform_init
    
    if terraform_plan; then
        if terraform_apply; then
            generate_connection_info
            post_deployment_verification
            
            log "SUCCESS" "🎉 Azure 混合环境部署完成！"
            echo ""
            echo "📋 下一步操作："
            echo "1. 查看环境配置: cat .env.azure-hybrid"
            echo "2. 启动本地应用: docker-compose -f docker-compose.azure.yml up"
            echo "3. 运行测试: ./scripts/test-azure-hybrid.sh"
            echo ""
            echo "📊 监控地址:"
            echo "- Azure Portal: https://portal.azure.com"
            echo "- Application Insights: 在 Azure Portal 中查看"
            
        else
            log "ERROR" "部署失败，请检查错误信息"
            exit 1
        fi
    else
        log "ERROR" "计划生成失败，请检查配置"
        exit 1
    fi
}

# 运行主函数
main "$@"