#!/bin/bash
# Simplified startup script for Ollama with essential models only

set -e

echo "🚀 Starting Ollama service..."

# Start Ollama in background
ollama serve &
OLLAMA_PID=$!

echo "⏳ Waiting for Ollama to be ready..."
sleep 10

# Check if ready
if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "✅ Ollama is ready!"
    
    echo "📥 Pulling essential models (this may take a while)..."
    
    # Pull just the most essential model first
    echo "1️⃣ Pulling phi3:3.8b (fastest model)..."
    ollama pull phi3:3.8b || true
    
    echo "2️⃣ Pulling mistral:7b (general purpose)..."
    ollama pull mistral:7b || true
    
    echo "3️⃣ Pulling llama3:8b (high quality)..."
    ollama pull llama3:8b || true
    
    echo "📊 Available models:"
    ollama list
else
    echo "⚠️ Ollama not ready, starting anyway..."
fi

# Keep Ollama running
echo "🔄 Ollama service running..."
wait $OLLAMA_PID