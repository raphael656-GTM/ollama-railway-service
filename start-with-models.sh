#!/bin/bash
# Start Ollama and download essential models

echo "🚀 Starting Ollama with model downloads..."

# Clean up any partial downloads to free space
echo "🧹 Cleaning up partial downloads..."
rm -rf /root/.ollama/models/blobs/*-partial 2>/dev/null || true
rm -rf /root/.ollama/tmp/* 2>/dev/null || true

# Check disk space
echo "💾 Disk space before cleanup:"
df -h /root/.ollama/ || df -h /

# Start Ollama in background
/bin/ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready
echo "⏳ Waiting for Ollama to start..."
sleep 10

# Check if Ollama is responding
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "✅ Ollama is ready!"
        break
    fi
    echo "Waiting... attempt $i/30"
    sleep 2
done

# Check current models first
echo "📊 Current models:"
/bin/ollama list

# Count existing models
MODEL_COUNT=$(/bin/ollama list | grep -c ":" 2>/dev/null || echo "0")
echo "Found $MODEL_COUNT models already downloaded"

# Only download if we don't have 2 models (phi3 + mistral is enough for testing)
if [ "$MODEL_COUNT" -lt 2 ]; then
    echo "📥 Downloading mistral:7b (essential model)..."
    
    # Check available space
    AVAILABLE=$(df /root/.ollama | tail -1 | awk '{print $4}')
    echo "Available space: ${AVAILABLE} KB"
    
    # Only download mistral if we have space and don't have it
    if ! /bin/ollama list | grep -q "mistral:7b"; then
        if [ "$AVAILABLE" -gt 1000000 ]; then  # More than 1GB available
            echo "1️⃣ Downloading mistral:7b..."
            if /bin/ollama pull mistral:7b; then
                echo "✅ mistral:7b download successful"
            else
                echo "❌ mistral:7b download failed - not enough space"
            fi
        else
            echo "⚠️ Not enough space for mistral:7b (need ~1GB free)"
        fi
    fi
    
    echo "💾 Final disk usage:"
    df -h /root/.ollama/ || df -h /
else
    echo "✅ Sufficient models already downloaded (phi3 + others)"
fi

echo "📊 Final model list:"
/bin/ollama list

echo "🔄 Ollama service ready. Keeping alive..."
wait $OLLAMA_PID