# Production Railway Ollama Service - Optimized for Meeting Intelligence
FROM ollama/ollama:latest

# Set environment variables for optimization
ENV OLLAMA_HOST=0.0.0.0
ENV OLLAMA_PORT=11434
ENV OLLAMA_KEEP_ALIVE=24h
ENV OLLAMA_MAX_LOADED_MODELS=3
ENV OLLAMA_FLASH_ATTENTION=1
ENV OLLAMA_NUM_PARALLEL=2

# Install essential system packages
RUN apt-get update && apt-get install -y \
    curl \
    jq \
    htop \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create optimized directory structure
RUN mkdir -p /root/.ollama/models \
    && mkdir -p /app/scripts \
    && mkdir -p /app/logs \
    && mkdir -p /app/backups

# Copy model installation and management scripts
COPY setup-models.sh /app/scripts/
COPY health-check.sh /app/scripts/
COPY model-manager.sh /app/scripts/
COPY backup-models.sh /app/scripts/

# Make scripts executable
RUN chmod +x /app/scripts/*.sh

# Set working directory
WORKDIR /app

# Create non-root user for security (Railway requirement)
RUN useradd -m -u 1001 -s /bin/bash ollama-user \
    && chown -R ollama-user:ollama-user /root/.ollama \
    && chown -R ollama-user:ollama-user /app

# Switch to non-root user
USER ollama-user

# Expose Ollama API port
EXPOSE 11434

# Enhanced health check with retry logic
HEALTHCHECK --interval=30s --timeout=15s --start-period=60s --retries=5 \
  CMD /app/scripts/health-check.sh || exit 1

# Volume for persistent model storage
VOLUME ["/root/.ollama"]

# Start with model initialization script
CMD ["/app/scripts/setup-models.sh"]