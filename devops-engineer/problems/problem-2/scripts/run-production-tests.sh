#!/bin/bash

# Production Readiness Tests for DevOps Demo Application
# Tests specific to production environment requirements

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
COLOR=${1:-blue}
NAMESPACE="production"
SERVICE_NAME="devops-demo-app-${COLOR}"
PORT=8000
LOCAL_PORT=8083

echo -e "${GREEN}🏭 Starting Production Readiness Tests${NC}"
echo "Environment: $NAMESPACE"
echo "Service: $SERVICE_NAME"
echo "Color: $COLOR"
echo "=========================================="

# Function to print test results
print_test() {
    local status=$1
    local test_name=$2
    local details=$3
    
    if [ "$status" == "PASS" ]; then
        echo -e "${GREEN}✅ PASS${NC} - $test_name"
    elif [ "$status" == "FAIL" ]; then
        echo -e "${RED}❌ FAIL${NC} - $test_name"
        if [ -n "$details" ]; then
            echo -e "   ${RED}Details: $details${NC}"
        fi
        return 1
    else
        echo -e "${YELLOW}⚠️  WARN${NC} - $test_name - $details"
    fi
    return 0
}

# Setup port forwarding
echo -e "\n${BLUE}Setting up port forwarding...${NC}"
kubectl port-forward service/$SERVICE_NAME -n $NAMESPACE $LOCAL_PORT:$PORT &
PF_PID=$!
sleep 10

# Cleanup function
cleanup() {
    echo -e "\n${BLUE}Cleaning up...${NC}"
    kill $PF_PID 2>/dev/null || true
    wait $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

BASE_URL="http://localhost:$LOCAL_PORT"

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local test_name=$1
    local test_command=$2
    
    if eval "$test_command" &>/dev/null; then
        print_test "PASS" "$test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        print_test "FAIL" "$test_name" "Command: $test_command"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Critical Production Tests
echo -e "\n${YELLOW}🔒 Critical Production Tests${NC}"

# Service availability
if ! curl -s --max-time 5 $BASE_URL/health &>/dev/null; then
    print_test "FAIL" "Service is not reachable" "Cannot connect to $BASE_URL"
    echo -e "${RED}CRITICAL: Service is not reachable. Aborting tests.${NC}"
    exit 1
fi

run_test "Health endpoint responds quickly (< 2s)" \
    "timeout 2s curl -s $BASE_URL/health | jq -e '.status == \"healthy\"'"

run_test "Application reports production environment" \
    "curl -s $BASE_URL/health | jq -e '.environment == \"production\"'"

# Security Tests
echo -e "\n${YELLOW}🛡️ Security Tests${NC}"

run_test "Security headers present" \
    "curl -s -I $BASE_URL/ | grep -i 'server:' | grep -v 'nginx/[0-9]'"

run_test "No sensitive information in health endpoint" \
    "! curl -s $BASE_URL/health | grep -i -E '(password|secret|key|token)'"

run_test "No debug information exposed" \
    "! curl -s $BASE_URL/ | grep -i -E '(debug|trace|stack)'"

# Performance Tests
echo -e "\n${YELLOW}⚡ Performance Tests${NC}"

echo "Running performance benchmark..."

# Response time test
RESPONSE_TIMES=()
for i in {1..10}; do
    RESPONSE_TIME=$(curl -s -o /dev/null -w '%{time_total}' $BASE_URL/health)
    RESPONSE_TIMES+=($RESPONSE_TIME)
done

# Calculate average response time
TOTAL_TIME=0
for time in "${RESPONSE_TIMES[@]}"; do
    TOTAL_TIME=$(echo "$TOTAL_TIME + $time" | bc)
done
AVG_TIME=$(echo "scale=3; $TOTAL_TIME / ${#RESPONSE_TIMES[@]}" | bc)
AVG_TIME_MS=$(echo "$AVG_TIME * 1000" | bc | cut -d. -f1)

if [ "$AVG_TIME_MS" -lt 200 ]; then
    print_test "PASS" "Average response time excellent: ${AVG_TIME_MS}ms"
    PASSED_TESTS=$((PASSED_TESTS + 1))
elif [ "$AVG_TIME_MS" -lt 500 ]; then
    print_test "PASS" "Average response time good: ${AVG_TIME_MS}ms"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_test "FAIL" "Average response time too slow: ${AVG_TIME_MS}ms"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Concurrent request test
echo "Testing concurrent load handling..."
CONCURRENT_REQUESTS=50
FAILED_REQUESTS=0

for i in $(seq 1 $CONCURRENT_REQUESTS); do
    (
        if ! curl -s --max-time 10 $BASE_URL/health &>/dev/null; then
            echo "FAIL" > /tmp/test_$i
        fi
    ) &
done

wait

# Count failures
for i in $(seq 1 $CONCURRENT_REQUESTS); do
    if [ -f /tmp/test_$i ]; then
        FAILED_REQUESTS=$((FAILED_REQUESTS + 1))
        rm -f /tmp/test_$i
    fi
done

SUCCESS_RATE=$(echo "scale=1; ($CONCURRENT_REQUESTS - $FAILED_REQUESTS) * 100 / $CONCURRENT_REQUESTS" | bc)

if [ "$FAILED_REQUESTS" -eq 0 ]; then
    print_test "PASS" "Concurrent load test: 100% success rate ($CONCURRENT_REQUESTS requests)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
elif [ "$(echo "$SUCCESS_RATE >= 95" | bc)" -eq 1 ]; then
    print_test "PASS" "Concurrent load test: ${SUCCESS_RATE}% success rate"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_test "FAIL" "Concurrent load test: Only ${SUCCESS_RATE}% success rate"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Resource Tests
echo -e "\n${YELLOW}📊 Resource Utilization Tests${NC}"

# Check pod resource usage
POD_NAME=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=devops-demo-app,app.kubernetes.io/color=$COLOR --no-headers -o custom-columns=":metadata.name" | head -n1)

if [ -n "$POD_NAME" ]; then
    # CPU usage
    CPU_USAGE=$(kubectl top pod $POD_NAME -n $NAMESPACE --no-headers | awk '{print $2}' | sed 's/m//')
    if [ -n "$CPU_USAGE" ] && [ "$CPU_USAGE" -lt 400 ]; then
        print_test "PASS" "CPU usage within limits: ${CPU_USAGE}m"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_test "WARN" "CPU usage high or unknown: ${CPU_USAGE}m"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    # Memory usage
    MEM_USAGE=$(kubectl top pod $POD_NAME -n $NAMESPACE --no-headers | awk '{print $3}' | sed 's/Mi//')
    if [ -n "$MEM_USAGE" ] && [ "$MEM_USAGE" -lt 800 ]; then
        print_test "PASS" "Memory usage within limits: ${MEM_USAGE}Mi"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_test "WARN" "Memory usage high or unknown: ${MEM_USAGE}Mi"
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
fi

# High Availability Tests
echo -e "\n${YELLOW}🔄 High Availability Tests${NC}"

# Check number of replicas
READY_REPLICAS=$(kubectl get deployment devops-demo-app-$COLOR -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
DESIRED_REPLICAS=$(kubectl get deployment devops-demo-app-$COLOR -n $NAMESPACE -o jsonpath='{.spec.replicas}')

if [ "$READY_REPLICAS" -eq "$DESIRED_REPLICAS" ] && [ "$READY_REPLICAS" -ge 3 ]; then
    print_test "PASS" "High availability: $READY_REPLICAS/$DESIRED_REPLICAS replicas ready"
    PASSED_TESTS=$((PASSED_TESTS + 1))
elif [ "$READY_REPLICAS" -eq "$DESIRED_REPLICAS" ]; then
    print_test "WARN" "Replicas ready but count low: $READY_REPLICAS/$DESIRED_REPLICAS"
else
    print_test "FAIL" "Replica mismatch: $READY_REPLICAS/$DESIRED_REPLICAS ready"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Check Pod Disruption Budget
if kubectl get pdb devops-demo-app-$COLOR -n $NAMESPACE &>/dev/null; then
    print_test "PASS" "Pod Disruption Budget configured"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_test "WARN" "Pod Disruption Budget not found"
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Monitoring Tests
echo -e "\n${YELLOW}📈 Monitoring Tests${NC}"

run_test "Metrics endpoint accessible" \
    "curl -s $BASE_URL/metrics | grep -q 'api_counter_total'"

run_test "Prometheus annotations present" \
    "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=devops-demo-app,app.kubernetes.io/color=$COLOR -o jsonpath='{.items[0].metadata.annotations.prometheus\.io/scrape}' | grep -q true"

# Database Connection Test
echo -e "\n${YELLOW}🗄️ Database Connection Tests${NC}"

# Test database connectivity through readiness check
READINESS_RESPONSE=$(curl -s -w "\n%{http_code}" $BASE_URL/ready)
READINESS_HTTP_CODE=$(echo "$READINESS_RESPONSE" | tail -n1)

if [ "$READINESS_HTTP_CODE" == "200" ]; then
    print_test "PASS" "Database connections healthy"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_test "FAIL" "Database connection issues detected"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Backup and Recovery Test (Simulated)
echo -e "\n${YELLOW}💾 Backup and Recovery Tests${NC}"

# Check if backup job exists
if kubectl get cronjob backup-job -n $NAMESPACE &>/dev/null; then
    print_test "PASS" "Backup job configured"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_test "WARN" "Backup job not found (may be managed externally)"
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Blue-Green Deployment Test
echo -e "\n${YELLOW}🔵🟢 Blue-Green Deployment Tests${NC}"

# Check if the other color deployment exists
OTHER_COLOR="green"
if [ "$COLOR" == "green" ]; then
    OTHER_COLOR="blue"
fi

if kubectl get deployment devops-demo-app-$OTHER_COLOR -n $NAMESPACE &>/dev/null; then
    # Check if other deployment has 0 replicas (should be scaled down)
    OTHER_REPLICAS=$(kubectl get deployment devops-demo-app-$OTHER_COLOR -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    if [ "$OTHER_REPLICAS" -eq 0 ]; then
        print_test "PASS" "Blue-green deployment: inactive deployment scaled to 0"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_test "WARN" "Blue-green deployment: both deployments active"
    fi
else
    print_test "PASS" "Blue-green deployment: single active deployment"
    PASSED_TESTS=$((PASSED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Final Results
echo -e "\n${GREEN}📊 Production Readiness Test Results${NC}"
echo "=========================================="
echo "Environment: $NAMESPACE"
echo "Service: $SERVICE_NAME"
echo "Color: $COLOR"
echo "Total Tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
echo "Success Rate: $(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"

# Production deployment criteria
REQUIRED_PASS_RATE=90
ACTUAL_PASS_RATE=$(echo "scale=0; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}🎉 Production deployment approved! All tests passed.${NC}"
    exit 0
elif [ "$ACTUAL_PASS_RATE" -ge "$REQUIRED_PASS_RATE" ]; then
    echo -e "\n${YELLOW}⚠️ Production deployment approved with warnings.${NC}"
    echo "Pass rate: ${ACTUAL_PASS_RATE}% (required: ${REQUIRED_PASS_RATE}%)"
    exit 0
else
    echo -e "\n${RED}❌ Production deployment rejected.${NC}"
    echo "Pass rate: ${ACTUAL_PASS_RATE}% (required: ${REQUIRED_PASS_RATE}%)"
    echo "Please fix the failing tests before deploying to production."
    exit 1
fi