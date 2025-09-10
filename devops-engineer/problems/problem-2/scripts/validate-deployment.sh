#!/bin/bash

# DevOps Demo CI/CD Pipeline Validation Script
# This script validates the complete GitOps workflow

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${1:-dev}
APP_NAME="devops-demo-app"
TIMEOUT=300

echo -e "${GREEN}🚀 Starting CI/CD Pipeline Validation${NC}"
echo "Environment: $NAMESPACE"
echo "Application: $APP_NAME"
echo "Timeout: ${TIMEOUT}s"
echo "=========================================="

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

# Function to wait for condition
wait_for_condition() {
    local condition=$1
    local description=$2
    local timeout=${3:-$TIMEOUT}
    
    echo "⏳ Waiting for: $description"
    
    local count=0
    while ! eval "$condition"; do
        sleep 5
        count=$((count + 5))
        if [ $count -ge $timeout ]; then
            print_status "FAIL" "$description - TIMEOUT after ${timeout}s"
            return 1
        fi
        echo "   ... still waiting (${count}s/${timeout}s)"
    done
    
    print_status "OK" "$description"
    return 0
}

# 1. Validate Kubernetes cluster connectivity
echo -e "\n${YELLOW}1. Validating Kubernetes Cluster${NC}"
if kubectl cluster-info &>/dev/null; then
    print_status "OK" "Kubernetes cluster is accessible"
else
    print_status "FAIL" "Cannot connect to Kubernetes cluster"
    exit 1
fi

# 2. Validate namespace exists
echo -e "\n${YELLOW}2. Validating Namespace${NC}"
if kubectl get namespace $NAMESPACE &>/dev/null; then
    print_status "OK" "Namespace '$NAMESPACE' exists"
else
    print_status "WARN" "Namespace '$NAMESPACE' does not exist, creating it"
    kubectl create namespace $NAMESPACE
fi

# 3. Validate deployment exists and is ready
echo -e "\n${YELLOW}3. Validating Deployment${NC}"
if kubectl get deployment $APP_NAME -n $NAMESPACE &>/dev/null; then
    print_status "OK" "Deployment '$APP_NAME' exists in namespace '$NAMESPACE'"
    
    # Wait for deployment to be ready
    wait_for_condition \
        "kubectl get deployment $APP_NAME -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -v '^$' | xargs test 1 -le" \
        "Deployment '$APP_NAME' to have at least 1 ready replica"
    
    # Check rollout status
    kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=${TIMEOUT}s
    print_status "OK" "Deployment rollout completed successfully"
else
    print_status "FAIL" "Deployment '$APP_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

# 4. Validate pods are running
echo -e "\n${YELLOW}4. Validating Pods${NC}"
READY_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$APP_NAME --field-selector=status.phase=Running --no-headers | wc -l)
TOTAL_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$APP_NAME --no-headers | wc -l)

if [ "$READY_PODS" -gt 0 ]; then
    print_status "OK" "$READY_PODS/$TOTAL_PODS pods are running"
else
    print_status "FAIL" "No pods are running for application '$APP_NAME'"
    kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$APP_NAME
    exit 1
fi

# 5. Validate service exists and has endpoints
echo -e "\n${YELLOW}5. Validating Service${NC}"
if kubectl get service $APP_NAME -n $NAMESPACE &>/dev/null; then
    print_status "OK" "Service '$APP_NAME' exists"
    
    # Check if service has endpoints
    ENDPOINTS=$(kubectl get endpoints $APP_NAME -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
    if [ "$ENDPOINTS" -gt 0 ]; then
        print_status "OK" "Service has $ENDPOINTS endpoint(s)"
    else
        print_status "WARN" "Service has no endpoints"
    fi
else
    print_status "FAIL" "Service '$APP_NAME' not found"
    exit 1
fi

# 6. Validate application health endpoints
echo -e "\n${YELLOW}6. Validating Application Health${NC}"

# Port forward for testing
echo "Setting up port forwarding..."
kubectl port-forward service/$APP_NAME -n $NAMESPACE 8080:8000 &
PF_PID=$!
sleep 5

# Test health endpoint
if curl -f http://localhost:8080/health &>/dev/null; then
    print_status "OK" "Health endpoint is responding"
else
    print_status "FAIL" "Health endpoint is not responding"
    kill $PF_PID 2>/dev/null || true
    exit 1
fi

# Test readiness endpoint
if curl -f http://localhost:8080/ready &>/dev/null; then
    print_status "OK" "Readiness endpoint is responding"
else
    print_status "WARN" "Readiness endpoint is not responding (may be expected if dependencies are not available)"
fi

# Test metrics endpoint
if curl -f http://localhost:8080/metrics &>/dev/null; then
    print_status "OK" "Metrics endpoint is responding"
else
    print_status "WARN" "Metrics endpoint is not responding"
fi

# Test API functionality
if curl -f http://localhost:8080/ &>/dev/null; then
    print_status "OK" "Root API endpoint is responding"
else
    print_status "FAIL" "Root API endpoint is not responding"
fi

# Clean up port forward
kill $PF_PID 2>/dev/null || true

# 7. Validate ConfigMap and Secret
echo -e "\n${YELLOW}7. Validating Configuration${NC}"
if kubectl get configmap ${APP_NAME}-config -n $NAMESPACE &>/dev/null; then
    print_status "OK" "ConfigMap exists"
else
    print_status "WARN" "ConfigMap not found"
fi

if kubectl get secret ${APP_NAME}-secrets -n $NAMESPACE &>/dev/null; then
    print_status "OK" "Secret exists"
else
    print_status "WARN" "Secret not found"
fi

# 8. Validate resource limits and requests
echo -e "\n${YELLOW}8. Validating Resource Configuration${NC}"
CONTAINERS_WITH_LIMITS=$(kubectl get deployment $APP_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[*].resources.limits}' | wc -w)
CONTAINERS_WITH_REQUESTS=$(kubectl get deployment $APP_NAME -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[*].resources.requests}' | wc -w)

if [ "$CONTAINERS_WITH_LIMITS" -gt 0 ]; then
    print_status "OK" "Resource limits are configured"
else
    print_status "WARN" "No resource limits configured"
fi

if [ "$CONTAINERS_WITH_REQUESTS" -gt 0 ]; then
    print_status "OK" "Resource requests are configured"
else
    print_status "WARN" "No resource requests configured"
fi

# 9. Validate HPA (if enabled)
echo -e "\n${YELLOW}9. Validating Auto-scaling${NC}"
if kubectl get hpa $APP_NAME -n $NAMESPACE &>/dev/null; then
    print_status "OK" "HorizontalPodAutoscaler is configured"
    
    # Check HPA status
    HPA_READY=$(kubectl get hpa $APP_NAME -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="AbleToScale")].status}')
    if [ "$HPA_READY" == "True" ]; then
        print_status "OK" "HPA is able to scale"
    else
        print_status "WARN" "HPA may not be ready to scale"
    fi
else
    print_status "WARN" "HorizontalPodAutoscaler not found (may be disabled)"
fi

# 10. Validate monitoring integration
echo -e "\n${YELLOW}10. Validating Monitoring Integration${NC}"

# Check for Prometheus annotations
PROMETHEUS_SCRAPE=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=$APP_NAME -o jsonpath='{.items[0].metadata.annotations.prometheus\.io/scrape}')
if [ "$PROMETHEUS_SCRAPE" == "true" ]; then
    print_status "OK" "Prometheus scraping is enabled"
else
    print_status "WARN" "Prometheus scraping not configured"
fi

# 11. Performance test
echo -e "\n${YELLOW}11. Running Basic Performance Test${NC}"
echo "Setting up port forwarding for performance test..."
kubectl port-forward service/$APP_NAME -n $NAMESPACE 8081:8000 &
PF_PID=$!
sleep 5

echo "Running load test (10 requests)..."
for i in {1..10}; do
    if ! curl -s http://localhost:8081/health > /dev/null; then
        print_status "WARN" "Request $i failed"
    fi
done
print_status "OK" "Basic performance test completed"

# Clean up
kill $PF_PID 2>/dev/null || true

echo -e "\n${GREEN}🎉 Validation Complete!${NC}"
echo "=========================================="
echo "Summary:"
echo "  Environment: $NAMESPACE"
echo "  Application: $APP_NAME"
echo "  Pods Running: $READY_PODS/$TOTAL_PODS"
echo "  Service Endpoints: $ENDPOINTS"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Check application logs: kubectl logs -l app.kubernetes.io/name=$APP_NAME -n $NAMESPACE"
echo "2. Monitor metrics: Access Prometheus/Grafana dashboards"
echo "3. View ArgoCD: Check deployment status in ArgoCD UI"
echo "4. Run integration tests: ./run-integration-tests.sh $NAMESPACE"

exit 0