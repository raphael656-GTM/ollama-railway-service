#!/bin/bash
# Start Ollama and download essential models

echo "🚀 Starting Ollama with model downloads..."

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

# Download models
echo "📥 Downloading essential models..."

echo "1️⃣ Downloading mistral:7b..."
/bin/ollama pull mistral:7b &

echo "2️⃣ Downloading llama3:8b..." 
/bin/ollama pull llama3:8b &

# Let downloads start
sleep 5

echo "📊 Current models:"
/bin/ollama list

echo "🔄 Downloads running in background. Keeping Ollama alive..."
wait $OLLAMA_PID