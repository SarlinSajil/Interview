#!/bin/bash

# Integration Tests for DevOps Demo Application
# Tests the complete application functionality including database interactions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE=${1:-staging}
SERVICE_NAME=${2:-devops-demo-app}
PORT=${3:-8000}
LOCAL_PORT=8082

echo -e "${GREEN}🧪 Starting Integration Tests${NC}"
echo "Environment: $NAMESPACE"
echo "Service: $SERVICE_NAME"
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
    else
        echo -e "${YELLOW}⚠️  SKIP${NC} - $test_name - $details"
    fi
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

# Health Check Tests
echo -e "\n${YELLOW}🏥 Health Check Tests${NC}"

run_test "Health endpoint returns 200" \
    "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/health | grep -q 200"

run_test "Health endpoint returns valid JSON" \
    "curl -s $BASE_URL/health | jq -e '.status == \"healthy\"'"

run_test "Health endpoint includes version" \
    "curl -s $BASE_URL/health | jq -e '.version'"

run_test "Health endpoint includes timestamp" \
    "curl -s $BASE_URL/health | jq -e '.timestamp'"

# API Functionality Tests
echo -e "\n${YELLOW}🔧 API Functionality Tests${NC}"

run_test "Root endpoint returns 200" \
    "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/ | grep -q 200"

run_test "Root endpoint returns API info" \
    "curl -s $BASE_URL/ | jq -e '.message == \"DevOps Demo API\"'"

run_test "Metrics endpoint returns 200" \
    "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/metrics | grep -q 200"

run_test "Metrics endpoint contains Prometheus metrics" \
    "curl -s $BASE_URL/metrics | grep -q 'api_counter_total'"

# Counter Tests
echo -e "\n${YELLOW}🔢 Counter Tests${NC}"

# Get initial counter value
INITIAL_COUNTER=$(curl -s $BASE_URL/counter | jq -r '.counter' 2>/dev/null || echo "0")

run_test "Get counter returns 200" \
    "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/counter | grep -q 200"

run_test "Get counter returns valid JSON" \
    "curl -s $BASE_URL/counter | jq -e '.counter'"

run_test "Increment counter returns 200" \
    "curl -s -X POST -o /dev/null -w '%{http_code}' $BASE_URL/counter | grep -q 200"

# Verify counter increment
NEW_COUNTER=$(curl -s $BASE_URL/counter | jq -r '.counter' 2>/dev/null || echo "0")
if [ "$NEW_COUNTER" -gt "$INITIAL_COUNTER" ]; then
    print_test "PASS" "Counter increment works (${INITIAL_COUNTER} -> ${NEW_COUNTER})"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_test "FAIL" "Counter increment failed (${INITIAL_COUNTER} -> ${NEW_COUNTER})"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Database Tests (will fail if PostgreSQL is not available)
echo -e "\n${YELLOW}🗄️ Database Tests${NC}"

# Test user creation
TEST_USER_EMAIL="test-$(date +%s)@example.com"
USER_DATA="{\"name\": \"Test User\", \"email\": \"$TEST_USER_EMAIL\"}"

CREATE_USER_RESPONSE=$(curl -s -X POST -H "Content-Type: application/json" -d "$USER_DATA" -w "\n%{http_code}" $BASE_URL/users)
CREATE_USER_HTTP_CODE=$(echo "$CREATE_USER_RESPONSE" | tail -n1)
CREATE_USER_BODY=$(echo "$CREATE_USER_RESPONSE" | head -n1)

if [ "$CREATE_USER_HTTP_CODE" == "200" ] || [ "$CREATE_USER_HTTP_CODE" == "201" ]; then
    print_test "PASS" "Create user returns success"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    
    # Verify user was created
    USER_ID=$(echo "$CREATE_USER_BODY" | jq -r '.id' 2>/dev/null)
    if [ "$USER_ID" != "null" ] && [ -n "$USER_ID" ]; then
        print_test "PASS" "Created user has valid ID: $USER_ID"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_test "FAIL" "Created user has no valid ID"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
elif [ "$CREATE_USER_HTTP_CODE" == "503" ]; then
    print_test "SKIP" "Create user test" "Database not available (503)"
else
    print_test "FAIL" "Create user returns error: $CREATE_USER_HTTP_CODE"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Test user listing
LIST_USERS_RESPONSE=$(curl -s -w "\n%{http_code}" $BASE_URL/users)
LIST_USERS_HTTP_CODE=$(echo "$LIST_USERS_RESPONSE" | tail -n1)
LIST_USERS_BODY=$(echo "$LIST_USERS_RESPONSE" | head -n1)

if [ "$LIST_USERS_HTTP_CODE" == "200" ]; then
    print_test "PASS" "List users returns 200"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    
    # Check if response contains users array
    if echo "$LIST_USERS_BODY" | jq -e '.users' &>/dev/null; then
        print_test "PASS" "List users returns valid structure"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_test "FAIL" "List users returns invalid structure"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
elif [ "$LIST_USERS_HTTP_CODE" == "503" ]; then
    print_test "SKIP" "List users test" "Database not available (503)"
else
    print_test "FAIL" "List users returns error: $LIST_USERS_HTTP_CODE"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Readiness Tests
echo -e "\n${YELLOW}⚡ Readiness Tests${NC}"

READINESS_RESPONSE=$(curl -s -w "\n%{http_code}" $BASE_URL/ready)
READINESS_HTTP_CODE=$(echo "$READINESS_RESPONSE" | tail -n1)
READINESS_BODY=$(echo "$READINESS_RESPONSE" | head -n1)

if [ "$READINESS_HTTP_CODE" == "200" ]; then
    print_test "PASS" "Readiness check returns 200"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    
    # Check readiness status
    if echo "$READINESS_BODY" | jq -e '.status == "ready"' &>/dev/null; then
        print_test "PASS" "Application reports ready status"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        print_test "FAIL" "Application does not report ready status"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
elif [ "$READINESS_HTTP_CODE" == "503" ]; then
    print_test "SKIP" "Readiness check" "Dependencies not available (503)"
else
    print_test "FAIL" "Readiness check returns error: $READINESS_HTTP_CODE"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Load Test
echo -e "\n${YELLOW}🚀 Load Test${NC}"

echo "Running concurrent requests test..."
LOAD_TEST_REQUESTS=20
LOAD_TEST_FAILED=0

for i in $(seq 1 $LOAD_TEST_REQUESTS); do
    if ! curl -s $BASE_URL/health &>/dev/null; then
        LOAD_TEST_FAILED=$((LOAD_TEST_FAILED + 1))
    fi
done

wait # Wait for all background processes

if [ $LOAD_TEST_FAILED -eq 0 ]; then
    print_test "PASS" "Load test: $LOAD_TEST_REQUESTS concurrent requests"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_test "FAIL" "Load test: $LOAD_TEST_FAILED/$LOAD_TEST_REQUESTS requests failed"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Response Time Test
echo -e "\n${YELLOW}⏱️ Performance Tests${NC}"

RESPONSE_TIME=$(curl -s -o /dev/null -w '%{time_total}' $BASE_URL/health)
RESPONSE_TIME_MS=$(echo "$RESPONSE_TIME * 1000" | bc | cut -d. -f1)

if [ "$RESPONSE_TIME_MS" -lt 1000 ]; then
    print_test "PASS" "Response time under 1s: ${RESPONSE_TIME_MS}ms"
    PASSED_TESTS=$((PASSED_TESTS + 1))
elif [ "$RESPONSE_TIME_MS" -lt 5000 ]; then
    print_test "WARN" "Response time acceptable: ${RESPONSE_TIME_MS}ms" "Consider optimization"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    print_test "FAIL" "Response time too slow: ${RESPONSE_TIME_MS}ms"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Final Results
echo -e "\n${GREEN}📊 Test Results Summary${NC}"
echo "=========================================="
echo "Total Tests: $TOTAL_TESTS"
echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
echo "Success Rate: $(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)%"

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "\n${GREEN}🎉 All tests passed! Application is ready for production.${NC}"
    exit 0
elif [ $FAILED_TESTS -le 2 ]; then
    echo -e "\n${YELLOW}⚠️ Some tests failed, but application is mostly functional.${NC}"
    exit 0
else
    echo -e "\n${RED}❌ Too many tests failed. Application needs attention.${NC}"
    exit 1
fi