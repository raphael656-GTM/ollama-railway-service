#!/bin/bash
# Minimal Ollama startup - just run with existing models

echo "🚀 Starting Ollama (minimal mode)..."

# Clean up any failed downloads
echo "🧹 Cleaning up failed downloads..."
rm -rf /root/.ollama/models/blobs/*-partial* 2>/dev/null || true
rm -rf /root/.ollama/tmp/* 2>/dev/null || true

# Check disk space
echo "💾 Current disk usage:"
df -h /root/.ollama/ 2>/dev/null || df -h /

# Start Ollama
/bin/ollama serve &
OLLAMA_PID=$!

# Wait for ready
echo "⏳ Waiting for Ollama..."
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "✅ Ollama ready!"
        break
    fi
    sleep 2
done

# Show what we have
echo "📊 Available models:"
/bin/ollama list

echo "🔄 Ollama running with available models..."
wait $OLLAMA_PID