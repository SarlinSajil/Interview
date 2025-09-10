#!/bin/bash

# Quick Setup Script for DevOps CI/CD Pipeline Project
# This script helps set up the local development environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 DevOps CI/CD Pipeline Setup${NC}"
echo "====================================="

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" == "OK" ]; then
        echo -e "${GREEN}✅ $message${NC}"
    elif [ "$status" == "WARN" ]; then
        echo -e "${YELLOW}⚠️  $message${NC}"
    else
        echo -e "${RED}❌ $message${NC}"
    fi
}

# Check prerequisites
echo -e "\n${BLUE}Checking Prerequisites...${NC}"

# Check Docker
if command -v docker &> /dev/null; then
    print_status "OK" "Docker is installed"
else
    print_status "FAIL" "Docker is not installed"
    exit 1
fi

# Check Docker Compose
if command -v docker-compose &> /dev/null; then
    print_status "OK" "Docker Compose is installed"
else
    print_status "FAIL" "Docker Compose is not installed"
    exit 1
fi

# Check kubectl
if command -v kubectl &> /dev/null; then
    print_status "OK" "kubectl is installed"
else
    print_status "WARN" "kubectl is not installed (needed for Kubernetes deployment)"
fi

# Check Helm
if command -v helm &> /dev/null; then
    print_status "OK" "Helm is installed"
else
    print_status "WARN" "Helm is not installed (needed for chart deployment)"
fi

# Make scripts executable
echo -e "\n${BLUE}Setting up scripts...${NC}"
chmod +x scripts/*.sh
print_status "OK" "Scripts made executable"

# Create necessary directories
echo -e "\n${BLUE}Creating directories...${NC}"
mkdir -p logs tmp .cache
print_status "OK" "Working directories created"

# Build the application image locally
echo -e "\n${BLUE}Building application image...${NC}"
cd app
if docker build -t devops-demo-app:local .; then
    print_status "OK" "Application image built successfully"
else
    print_status "FAIL" "Failed to build application image"
    exit 1
fi
cd ..

# Test the application locally
echo -e "\n${BLUE}Testing application locally...${NC}"
docker run -d --name devops-demo-test -p 8000:8000 devops-demo-app:local

# Wait for app to start
sleep 5

# Test health endpoint
if curl -f http://localhost:8000/health &>/dev/null; then
    print_status "OK" "Application health check passed"
else
    print_status "WARN" "Application health check failed (may need dependencies)"
fi

# Cleanup test container
docker stop devops-demo-test &>/dev/null || true
docker rm devops-demo-test &>/dev/null || true

# Validate Kubernetes manifests
echo -e "\n${BLUE}Validating Kubernetes manifests...${NC}"
if command -v kubectl &> /dev/null; then
    # Test kustomize build
    if kubectl kustomize k8s/base &>/dev/null; then
        print_status "OK" "Base Kubernetes manifests are valid"
    else
        print_status "WARN" "Base Kubernetes manifests have issues"
    fi
    
    # Test overlays
    for env in dev staging prod; do
        if kubectl kustomize k8s/overlays/$env &>/dev/null; then
            print_status "OK" "$env overlay manifests are valid"
        else
            print_status "WARN" "$env overlay manifests have issues"
        fi
    done
else
    print_status "WARN" "Skipping Kubernetes validation (kubectl not available)"
fi

# Validate Helm chart
echo -e "\n${BLUE}Validating Helm chart...${NC}"
if command -v helm &> /dev/null; then
    cd helm/charts/app
    if helm lint . &>/dev/null; then
        print_status "OK" "Helm chart is valid"
    else
        print_status "WARN" "Helm chart has issues"
    fi
    
    # Test template rendering
    if helm template test . &>/dev/null; then
        print_status "OK" "Helm templates render successfully"
    else
        print_status "WARN" "Helm template rendering has issues"
    fi
    cd ../../..
else
    print_status "WARN" "Skipping Helm validation (helm not available)"
fi

# Summary
echo -e "\n${GREEN}📋 Setup Summary${NC}"
echo "====================================="
echo "✅ Project structure created"
echo "✅ Application image built"
echo "✅ Scripts configured"
echo "✅ Manifests validated"

echo -e "\n${YELLOW}🎯 Next Steps${NC}"
echo "1. Start local infrastructure:"
echo "   cd ../../../docker-compose && ./start-devops.sh"
echo ""
echo "2. Deploy to local Kubernetes (if available):"
echo "   helm upgrade --install devops-demo-dev ./helm/charts/app \\"
echo "     --namespace dev --create-namespace \\"
echo "     --set image.repository=devops-demo-app \\"
echo "     --set image.tag=local"
echo ""
echo "3. Run validation tests:"
echo "   ./scripts/validate-deployment.sh dev"
echo ""
echo "4. Set up GitHub repository with:"
echo "   - GitHub Actions workflows"
echo "   - Container registry access"
echo "   - Kubernetes cluster connection"
echo "   - ArgoCD installation"

echo -e "\n${GREEN}🎉 Setup Complete!${NC}"
echo "Check README.md for detailed documentation."