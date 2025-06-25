# 本地开发环境工具安装清单

## 必需工具 (Required Tools)

### 1. Docker Desktop 🐳
**用途**: 容器运行时和本地Kubernetes集群
**安装方式**: 
- **macOS**: 从官网下载安装包
- **Windows**: 从官网下载安装包  
- **Linux**: 使用包管理器

```bash
# 验证安装
docker version
docker info
```

**Claude能否帮助安装**: ❌ 需要手动下载安装
**下载链接**: https://docs.docker.com/get-docker/

---

### 2. kubectl ⚓
**用途**: Kubernetes命令行工具
**安装方式**:

```bash
# macOS (推荐使用Homebrew)
brew install kubectl

# macOS (官方方式)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Windows (PowerShell)
curl.exe -LO "https://dl.k8s.io/release/v1.28.0/bin/windows/amd64/kubectl.exe"
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `kubectl version --client`

---

### 3. Git 📝
**用途**: 版本控制
**安装方式**:

```bash
# macOS
brew install git
# 或使用Xcode Command Line Tools
xcode-select --install

# Linux (Ubuntu/Debian)
sudo apt update && sudo apt install git

# Linux (CentOS/RHEL)
sudo yum install git

# Windows
# 从 https://git-scm.com/download/win 下载安装
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `git --version`

---

## 推荐工具 (Recommended Tools)

### 4. Homebrew (仅macOS) 🍺
**用途**: 包管理器，简化其他工具安装
**安装方式**:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `brew --version`

---

### 5. Kind 🎭
**用途**: 本地Kubernetes集群 (Docker Desktop的替代方案)
**安装方式**:

```bash
# macOS
brew install kind

# Linux
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Windows
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
Move-Item .\kind-windows-amd64.exe c:\some-dir-in-your-PATH\kind.exe
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `kind version`

---

### 6. Helm ⛵
**用途**: Kubernetes包管理器
**安装方式**:

```bash
# macOS
brew install helm

# Linux/macOS (官方脚本)
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Windows
choco install kubernetes-helm
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `helm version`

---

### 7. k9s 🐕
**用途**: Kubernetes可视化管理工具
**安装方式**:

```bash
# macOS
brew install k9s

# Linux
curl -sS https://webinstall.dev/k9s | bash

# Windows
choco install k9s
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `k9s version`

---

### 8. stern 📡
**用途**: 多Pod日志查看工具
**安装方式**:

```bash
# macOS
brew install stern

# Linux
curl -LO https://github.com/stern/stern/releases/download/v1.25.0/stern_1.25.0_linux_amd64.tar.gz
tar -xzf stern_1.25.0_linux_amd64.tar.gz
sudo mv stern /usr/local/bin/
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `stern --version`

---

## 可选工具 (Optional Tools)

### 9. jq 📊
**用途**: JSON处理工具
**安装方式**:

```bash
# macOS
brew install jq

# Linux
sudo apt install jq  # Ubuntu/Debian
sudo yum install jq  # CentOS/RHEL

# Windows
choco install jq
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `jq --version`

---

### 10. curl 🌐
**用途**: HTTP客户端工具
**安装方式**:

```bash
# 通常系统自带，如果没有：
# macOS
brew install curl

# Linux
sudo apt install curl  # Ubuntu/Debian

# Windows (通常自带)
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `curl --version`

---

### 11. Apache Bench (ab) 🚀
**用途**: 简单性能测试工具
**安装方式**:

```bash
# macOS
brew install httpd

# Linux
sudo apt install apache2-utils  # Ubuntu/Debian
sudo yum install httpd-tools     # CentOS/RHEL

# Windows
# 需要安装Apache HTTP Server
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `ab -V`

---

## 编程环境 (Development Environment)

### 12. Java Development Kit (JDK) ☕
**用途**: Java应用开发和运行
**版本**: JDK 17 或更高
**安装方式**:

```bash
# macOS
brew install openjdk@17

# Linux
sudo apt install openjdk-17-jdk  # Ubuntu/Debian

# Windows
# 从 https://adoptium.net/ 下载安装
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `java -version`

---

### 13. Node.js 🟢
**用途**: JavaScript应用开发和运行
**版本**: Node.js 18 或更高
**安装方式**:

```bash
# macOS
brew install node@18

# Linux (使用NodeSource)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Windows
# 从 https://nodejs.org/ 下载安装
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `node --version && npm --version`

---

### 14. Python 🐍
**用途**: Python应用开发和运行
**版本**: Python 3.9 或更高
**安装方式**:

```bash
# macOS
brew install python@3.11

# Linux
sudo apt install python3.11 python3.11-pip  # Ubuntu/Debian

# Windows
# 从 https://python.org/ 下载安装
```

**Claude能否帮助安装**: ✅ 可以提供安装脚本
**验证**: `python3 --version && pip3 --version`

---

## 一键安装脚本

### macOS 安装脚本
```bash
#!/bin/bash
# install-macos.sh

echo "🚀 Installing development tools for macOS..."

# Install Homebrew if not present
if ! command -v brew &> /dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install tools
echo "Installing required tools..."
brew install kubectl git kind helm k9s stern jq curl
brew install openjdk@17 node@18 python@3.11

# Install Docker Desktop manually
echo "⚠️  Please install Docker Desktop manually from:"
echo "   https://docs.docker.com/desktop/install/mac-install/"

echo "✅ Installation completed!"
echo "Please restart your terminal and run: ./scripts/verify-installation.sh"
```

### Linux (Ubuntu/Debian) 安装脚本
```bash
#!/bin/bash
# install-linux.sh

echo "🚀 Installing development tools for Linux..."

# Update package manager
sudo apt update

# Install basic tools
sudo apt install -y curl wget git apt-transport-https ca-certificates gnupg lsb-release

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install Kind
[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io

# Add user to docker group
sudo usermod -aG docker $USER

# Install development environments
sudo apt install -y openjdk-17-jdk nodejs npm python3.11 python3.11-pip

echo "✅ Installation completed!"
echo "Please log out and log back in, then run: ./scripts/verify-installation.sh"
```

---

## 验证安装脚本

```bash
#!/bin/bash
# scripts/verify-installation.sh

echo "🔍 Verifying installation..."

# Required tools
tools=(
    "docker:Docker"
    "kubectl:Kubernetes CLI"
    "git:Git"
)

# Optional tools
optional_tools=(
    "kind:Kind"
    "helm:Helm"
    "k9s:K9s"
    "stern:Stern"
    "jq:jq"
    "java:Java"
    "node:Node.js"
    "python3:Python"
)

check_tool() {
    local cmd=$1
    local name=$2
    
    if command -v $cmd &> /dev/null; then
        echo "✅ $name: $(which $cmd)"
        return 0
    else
        echo "❌ $name: Not found"
        return 1
    fi
}

echo "Required tools:"
for tool_pair in "${tools[@]}"; do
    IFS=':' read -r cmd name <<< "$tool_pair"
    check_tool $cmd "$name"
done

echo -e "\nOptional tools:"
for tool_pair in "${optional_tools[@]}"; do
    IFS=':' read -r cmd name <<< "$tool_pair"
    check_tool $cmd "$name"
done

echo -e "\n🎉 Verification completed!"
```

---

## Claude 能否帮助安装？

| 工具 | Claude 能帮助 | 说明 |
|------|---------------|------|
| Docker Desktop | ❌ | 需要手动下载GUI安装包 |
| kubectl | ✅ | 可以提供命令和脚本 |
| Git | ✅ | 可以提供安装命令 |
| Homebrew | ✅ | 可以提供安装脚本 |
| Kind | ✅ | 可以提供安装命令 |
| Helm | ✅ | 可以提供安装脚本 |
| k9s | ✅ | 可以提供安装命令 |
| stern | ✅ | 可以提供安装脚本 |
| JDK | ✅ | 可以提供安装命令 |
| Node.js | ✅ | 可以提供安装脚本 |
| Python | ✅ | 可以提供安装命令 |

## 💡 总结

**Claude可以帮助安装的工具**: 90%以上的工具都可以通过命令行安装，Claude可以提供完整的安装脚本。

**需要手动安装的工具**: 只有Docker Desktop需要从官网下载GUI安装包。

**推荐安装顺序**:
1. 先安装Docker Desktop (手动)
2. 安装包管理器 (Homebrew/apt)
3. 使用Claude提供的脚本批量安装其他工具
4. 运行验证脚本确认安装成功

您想让我为您的操作系统创建具体的安装脚本吗？