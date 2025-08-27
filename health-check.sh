#!/bin/bash
# Enhanced Health Check Script for Railway Ollama Service
# Provides detailed health status for monitoring and alerting

set -e

# Configuration
API_URL="http://localhost:11434"
TIMEOUT=10
HEALTH_LOG="/app/logs/health.log"
MODELS_READY_FILE="/app/.models_ready"

# Colors for output (if terminal supports it)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

# Function to log with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$HEALTH_LOG" 2>/dev/null || true
}

# Function to check basic API availability
check_api_availability() {
    local response
    local http_code
    
    response=$(curl -s -m $TIMEOUT -w "HTTP_CODE:%{http_code}" "$API_URL/api/tags" 2>/dev/null || echo "HTTP_CODE:000")
    http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✅ API Available${NC}"
        log_message "SUCCESS: API responding (HTTP 200)"
        return 0
    else
        echo -e "${RED}❌ API Unavailable (HTTP $http_code)${NC}"
        log_message "ERROR: API not responding (HTTP $http_code)"
        return 1
    fi
}

# Function to check model availability
check_models() {
    local models_response
    local model_count
    
    if ! models_response=$(curl -s -m $TIMEOUT "$API_URL/api/tags" 2>/dev/null); then
        echo -e "${RED}❌ Cannot retrieve model list${NC}"
        log_message "ERROR: Cannot retrieve model list"
        return 1
    fi
    
    # Count models using jq if available, otherwise use basic parsing
    if command -v jq >/dev/null 2>&1; then
        model_count=$(echo "$models_response" | jq -r '.models | length' 2>/dev/null || echo "0")
    else
        # Fallback: count occurrences of "name" in response
        model_count=$(echo "$models_response" | grep -o '"name"' | wc -l || echo "0")
    fi
    
    if [ "$model_count" -gt 0 ]; then
        echo -e "${GREEN}✅ Models Available ($model_count)${NC}"
        log_message "SUCCESS: $model_count models available"
        return 0
    else
        echo -e "${YELLOW}⚠️ No models loaded${NC}"
        log_message "WARNING: No models loaded"
        return 1
    fi
}

# Function to check if models are ready (setup completed)
check_models_ready() {
    if [ -f "$MODELS_READY_FILE" ]; then
        echo -e "${GREEN}✅ Model setup completed${NC}"
        log_message "SUCCESS: Model setup completed"
        return 0
    else
        echo -e "${YELLOW}⏳ Model setup in progress${NC}"
        log_message "WARNING: Model setup still in progress"
        return 1
    fi
}

# Function to test model inference
test_model_inference() {
    local test_model="phi3:3.8b"  # Use fastest model for health check
    local test_prompt="Hello"
    local response
    
    # Skip if no models available
    if ! check_models >/dev/null 2>&1; then
        echo -e "${YELLOW}⏭️ Skipping inference test (no models)${NC}"
        return 0
    fi
    
    # Quick inference test with timeout
    response=$(curl -s -m 15 -X POST "$API_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$test_model\",\"prompt\":\"$test_prompt\",\"stream\":false,\"options\":{\"max_tokens\":10}}" 2>/dev/null || echo "")
    
    if echo "$response" | grep -q '"response"'; then
        echo -e "${GREEN}✅ Model inference working${NC}"
        log_message "SUCCESS: Model inference test passed"
        return 0
    else
        echo -e "${YELLOW}⚠️ Model inference unavailable${NC}"
        log_message "WARNING: Model inference test failed"
        return 1
    fi
}

# Function to check resource usage
check_resources() {
    local memory_usage
    local disk_usage
    
    # Memory usage (if available)
    if command -v free >/dev/null 2>&1; then
        memory_usage=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}' 2>/dev/null || echo "N/A")
        if [ "$memory_usage" != "N/A" ]; then
            echo -e "${GREEN}📊 Memory: ${memory_usage}%${NC}"
            log_message "INFO: Memory usage $memory_usage%"
        fi
    fi
    
    # Disk usage for models directory
    if [ -d "/root/.ollama/models" ]; then
        disk_usage=$(du -sh /root/.ollama/models 2>/dev/null | cut -f1 || echo "N/A")
        if [ "$disk_usage" != "N/A" ]; then
            echo -e "${GREEN}💾 Models storage: ${disk_usage}${NC}"
            log_message "INFO: Models storage usage $disk_usage"
        fi
    fi
}

# Main health check function
main() {
    local overall_status=0
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create log directory if it doesn't exist
    mkdir -p /app/logs 2>/dev/null || true
    
    echo -e "\n🏥 Ollama Health Check - $timestamp"
    echo "=================================="
    
    log_message "Starting health check"
    
    # Basic API check (critical)
    if ! check_api_availability; then
        overall_status=1
    fi
    
    # Model availability check
    if ! check_models; then
        overall_status=1
    fi
    
    # Model setup completion check
    check_models_ready || true  # Non-critical
    
    # Inference test (warning only)
    test_model_inference || true  # Non-critical
    
    # Resource monitoring (informational)
    check_resources || true  # Non-critical
    
    echo ""
    
    # Overall status
    if [ $overall_status -eq 0 ]; then
        echo -e "${GREEN}🎉 Overall Status: HEALTHY${NC}"
        log_message "SUCCESS: Overall health check passed"
    else
        echo -e "${RED}💥 Overall Status: UNHEALTHY${NC}"
        log_message "ERROR: Overall health check failed"
    fi
    
    return $overall_status
}

# Run health check
main "$@"