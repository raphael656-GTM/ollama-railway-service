#!/bin/bash
# Simplified startup script for Ollama with essential models only

echo "🚀 Starting Ollama service..."

# Start Ollama in background
ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to be ready with retries
echo "⏳ Waiting for Ollama to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "✅ Ollama is ready after $i attempts!"
        break
    fi
    echo "Waiting... attempt $i/30"
    sleep 2
done

# Try to pull models regardless
echo "📥 Attempting to pull essential models..."

# Try pulling the smallest model first
echo "1️⃣ Pulling phi3:3.8b (smallest/fastest)..."
timeout 120 ollama pull phi3:3.8b 2>&1 || echo "⚠️ phi3 download timeout/failed"

# List what we have
echo "📊 Currently available models:"
ollama list || echo "No models available yet"

# Keep Ollama running
echo "🔄 Ollama service running..."
echo "💡 Additional models will be downloaded on first use"
wait $OLLAMA_PID