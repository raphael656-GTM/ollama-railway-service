#!/bin/bash
echo "📥 Downloading additional models for Ollama..."
ollama pull mistral:7b || echo "mistral download failed"
ollama pull llama3:8b || echo "llama3 download failed"
ollama list
echo "✅ Done!"