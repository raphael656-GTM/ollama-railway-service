#!/bin/bash
# Production Ollama Setup Script - Phase 1 Models for Meeting Intelligence
# Optimized for Railway deployment with cost efficiency

set -e

# Configuration
SCRIPT_DIR="/app/scripts"
LOG_FILE="/app/logs/setup-$(date +%Y%m%d_%H%M%S).log"
MODELS_DIR="/root/.ollama/models"
HEALTH_CHECK_RETRIES=30
HEALTH_CHECK_INTERVAL=2

# Create log file
mkdir -p /app/logs
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "🚀 Starting Production Ollama Service - Phase 1 Model Setup"
echo "📅 $(date)"
echo "🌐 Host: ${OLLAMA_HOST:-0.0.0.0}:${OLLAMA_PORT:-11434}"
echo "📊 Max Models: ${OLLAMA_MAX_LOADED_MODELS:-3}"
echo "⚡ Flash Attention: ${OLLAMA_FLASH_ATTENTION:-1}"

# Start Ollama server in background
echo "🤖 Starting Ollama server..."
ollama serve &
OLLAMA_PID=$!

# Function to check if Ollama is ready
check_ollama_ready() {
    curl -s -f http://localhost:11434/api/tags > /dev/null 2>&1
}

# Wait for Ollama to be ready with timeout
echo "⏳ Waiting for Ollama to initialize..."
for i in $(seq 1 $HEALTH_CHECK_RETRIES); do
    if check_ollama_ready; then
        echo "✅ Ollama is ready after ${i} attempts!"
        break
    fi
    
    if [ $i -eq $HEALTH_CHECK_RETRIES ]; then
        echo "❌ Ollama failed to start within timeout period"
        exit 1
    fi
    
    echo "⏳ Attempt $i/$HEALTH_CHECK_RETRIES - still waiting..."
    sleep $HEALTH_CHECK_INTERVAL
done

# Function to pull model with retry logic
pull_model_with_retry() {
    local model_name=$1
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        echo "📥 Pulling $model_name (attempt $attempt/$max_attempts)..."
        
        if ollama pull "$model_name"; then
            echo "✅ Successfully pulled $model_name"
            return 0
        else
            echo "❌ Failed to pull $model_name (attempt $attempt/$max_attempts)"
            if [ $attempt -lt $max_attempts ]; then
                echo "⏳ Waiting 10 seconds before retry..."
                sleep 10
            fi
        fi
        
        ((attempt++))
    done
    
    echo "💥 Failed to pull $model_name after $max_attempts attempts"
    return 1
}

# Function to verify model installation
verify_model() {
    local model_name=$1
    local response
    
    response=$(ollama list | grep -c "$model_name" || echo "0")
    if [ "$response" -gt 0 ]; then
        echo "✅ Model $model_name verified successfully"
        return 0
    else
        echo "❌ Model $model_name verification failed"
        return 1
    fi
}

echo "🎯 Installing Phase 1 Models for Meeting Intelligence..."
echo "📋 Target models: mistral:7b, phi3:3.8b, llama3:8b, codellama:7b, qwen2:7b, command-r:35b"

# Phase 1 Essential Models - Optimized for Meeting Intelligence tasks
MODELS=(
    "phi3:3.8b"          # Fast sentiment analysis and basic summaries
    "mistral:7b"         # General purpose, good balance of speed/quality  
    "llama3:8b"          # High quality summaries and action items
    "codellama:7b"       # Technical meeting analysis
    "qwen2:7b"           # Alternative high-quality model
    "command-r:35b"      # Complex PAQ scoring and pipeline detection
)

# Track installation results
SUCCESSFUL_MODELS=()
FAILED_MODELS=()

for model in "${MODELS[@]}"; do
    echo ""
    echo "🔄 Processing $model..."
    
    if pull_model_with_retry "$model"; then
        if verify_model "$model"; then
            SUCCESSFUL_MODELS+=("$model")
        else
            FAILED_MODELS+=("$model")
        fi
    else
        FAILED_MODELS+=("$model")
    fi
done

# Installation Summary
echo ""
echo "📊 INSTALLATION SUMMARY"
echo "======================="
echo "✅ Successfully installed (${#SUCCESSFUL_MODELS[@]}):"
for model in "${SUCCESSFUL_MODELS[@]}"; do
    echo "  - $model"
done

if [ ${#FAILED_MODELS[@]} -gt 0 ]; then
    echo ""
    echo "❌ Failed to install (${#FAILED_MODELS[@]}):"
    for model in "${FAILED_MODELS[@]}"; do
        echo "  - $model"
    done
fi

# Check minimum requirements
if [ ${#SUCCESSFUL_MODELS[@]} -ge 3 ]; then
    echo ""
    echo "🎉 Minimum model requirements met! Service ready for production."
    echo "💡 Available for Meeting Intelligence tasks:"
    echo "   - Sentiment Analysis: phi3:3.8b, mistral:7b"
    echo "   - Summaries & Action Items: llama3:8b, mistral:7b"
    echo "   - PAQ Scoring: command-r:35b, llama3:8b"
    echo "   - Pipeline Detection: command-r:35b, qwen2:7b"
    echo "   - Technical Analysis: codellama:7b"
else
    echo ""
    echo "⚠️ WARNING: Less than 3 models installed successfully"
    echo "   Service may have limited functionality"
fi

# Final health check
echo ""
echo "🔍 Final system check..."
if check_ollama_ready; then
    echo "✅ Ollama API is responding"
    
    # Show available models
    echo "📋 Currently available models:"
    ollama list || echo "⚠️ Could not list models"
    
    echo ""
    echo "💾 Model storage usage:"
    du -sh /root/.ollama/models 2>/dev/null || echo "⚠️ Could not check storage"
    
    echo ""
    echo "🚀 Ollama service is ready for production!"
    echo "🌐 API endpoint: http://localhost:11434"
    echo "📊 Health check endpoint: http://localhost:11434/api/tags"
else
    echo "❌ Final health check failed"
    exit 1
fi

# Create marker file for successful initialization
touch /app/.models_ready

# Keep Ollama running
echo ""
echo "🔄 Keeping Ollama service running..."
echo "📝 Logs available at: $LOG_FILE"

# Handle shutdown gracefully
trap 'echo "🛑 Shutting down Ollama service..."; kill $OLLAMA_PID; exit 0' SIGTERM SIGINT

# Wait for Ollama process
wait $OLLAMA_PID