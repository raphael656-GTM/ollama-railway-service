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

# Only download if we don't have all models
if [ "$MODEL_COUNT" -lt 3 ]; then
    echo "📥 Downloading missing models one at a time..."
    
    # Check and download mistral:7b
    if ! /bin/ollama list | grep -q "mistral:7b"; then
        echo "1️⃣ Downloading mistral:7b..."
        /bin/ollama pull mistral:7b
        echo "✅ mistral:7b download complete"
    fi
    
    # Check disk space before second download
    echo "💾 Disk space after mistral:"
    df -h /root/.ollama/ || df -h /
    
    # Check and download llama3:8b
    if ! /bin/ollama list | grep -q "llama3:8b"; then
        echo "2️⃣ Downloading llama3:8b..."
        /bin/ollama pull llama3:8b
        echo "✅ llama3:8b download complete"
    fi
else
    echo "✅ All models already downloaded"
fi

echo "📊 Final model list:"
/bin/ollama list

echo "🔄 Ollama service ready. Keeping alive..."
wait $OLLAMA_PID