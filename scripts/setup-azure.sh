#!/bin/bash
set -e

echo "🔧 设置 Azure 环境..."

# 检查是否已安装 Azure CLI
if ! command -v az &> /dev/null; then
    echo "📥 正在安装 Azure CLI..."
    
    # 检查操作系统
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            echo "使用 Homebrew 安装 Azure CLI..."
            brew install azure-cli
        else
            echo "请先安装 Homebrew 或手动安装 Azure CLI"
            echo "https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-macos"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        echo "使用官方脚本安装 Azure CLI..."
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    else
        echo "不支持的操作系统: $OSTYPE"
        exit 1
    fi
else
    echo "✅ Azure CLI 已安装"
fi

echo "🔑 检查 Azure 登录状态..."
if ! az account show &> /dev/null; then
    echo "请登录到 Azure..."
    echo "这将打开浏览器进行认证"
    read -p "按 Enter 继续..."
    az login
else
    echo "✅ 已登录到 Azure"
    az account show --query "{Name:name, SubscriptionId:id, TenantId:tenantId}" -o table
fi

echo "📍 获取本地公网 IP..."
MY_IP=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s ipv4.icanhazip.com 2>/dev/null || echo "未知")
echo "本地公网 IP: $MY_IP"

if [ "$MY_IP" != "未知" ]; then
    echo "更新 Terraform 配置中的 IP 白名单..."
    sed -i.bak "s/\"0.0.0.0\"/\"$MY_IP\"/" terraform/azure/environments/dev/terraform.tfvars
    echo "✅ IP 白名单已更新为: $MY_IP"
else
    echo "⚠️  无法获取公网 IP，将使用 0.0.0.0（允许所有 IP）"
fi

echo "🎉 Azure 环境设置完成！"
echo ""
echo "下一步："
echo "1. cd terraform/azure"
echo "2. terraform plan -var-file=environments/dev/terraform.tfvars"
echo "3. terraform apply -var-file=environments/dev/terraform.tfvars"