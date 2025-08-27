# Simplified Ollama service for Railway
FROM ollama/ollama:latest

# Install curl for health checks
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy simple startup script
COPY start-simple.sh /start-simple.sh
RUN chmod +x /start-simple.sh

# Expose port
EXPOSE 11434

# Simple health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s \
  CMD curl -f http://localhost:11434/api/tags || exit 1

# Run the simple startup script
CMD ["/start-simple.sh"]