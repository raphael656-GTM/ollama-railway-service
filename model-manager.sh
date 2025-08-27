#!/bin/bash
# Model Manager Script for Railway Ollama Service
# Handles model lifecycle, optimization, and maintenance

set -e

# Configuration
API_URL="http://localhost:11434"
MODELS_DIR="/root/.ollama/models"
LOG_FILE="/app/logs/model-manager.log"
BACKUP_DIR="/app/backups"

# Colors for output
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' NC=''
fi

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" 2>/dev/null || echo "$1"
}

# Function to show usage
show_usage() {
    echo "Model Manager for Railway Ollama Service"
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  list                    List all available models"
    echo "  status                  Show detailed model status"
    echo "  install MODEL           Install a specific model"
    echo "  remove MODEL            Remove a specific model"
    echo "  optimize                Optimize loaded models"
    echo "  cleanup                 Clean up unused models"
    echo "  backup                  Backup all models"
    echo "  restore BACKUP_FILE     Restore models from backup"
    echo "  update MODEL            Update a specific model"
    echo "  health                  Run health check"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 install phi3:3.8b"
    echo "  $0 status"
    echo "  $0 optimize"
}

# Function to check if Ollama is ready
check_ollama_ready() {
    curl -s -f "$API_URL/api/tags" > /dev/null 2>&1
}

# Function to list models
list_models() {
    log "Listing all models"
    
    if ! check_ollama_ready; then
        echo -e "${RED}❌ Ollama service not available${NC}"
        return 1
    fi
    
    echo -e "${BLUE}📋 Available Models:${NC}"
    echo "==================="
    
    local models_json
    if ! models_json=$(curl -s "$API_URL/api/tags" 2>/dev/null); then
        echo -e "${RED}❌ Failed to fetch model list${NC}"
        return 1
    fi
    
    if command -v jq >/dev/null 2>&1; then
        echo "$models_json" | jq -r '.models[] | "\(.name) - Size: \(.size // "Unknown") - Modified: \(.modified_at // "Unknown")"' 2>/dev/null || {
            echo -e "${YELLOW}⚠️ Could not parse model details with jq${NC}"
            ollama list 2>/dev/null || echo "No models available"
        }
    else
        ollama list 2>/dev/null || echo "No models available"
    fi
}

# Function to show model status
show_status() {
    log "Showing model status"
    
    echo -e "${BLUE}📊 Model Status Report:${NC}"
    echo "======================"
    
    # API availability
    if check_ollama_ready; then
        echo -e "${GREEN}✅ Ollama API: Available${NC}"
    else
        echo -e "${RED}❌ Ollama API: Unavailable${NC}"
        return 1
    fi
    
    # Model count
    local model_count
    if command -v jq >/dev/null 2>&1; then
        model_count=$(curl -s "$API_URL/api/tags" 2>/dev/null | jq -r '.models | length' 2>/dev/null || echo "0")
    else
        model_count=$(ollama list 2>/dev/null | tail -n +2 | wc -l || echo "0")
    fi
    
    echo -e "${GREEN}📈 Total Models: $model_count${NC}"
    
    # Storage usage
    if [ -d "$MODELS_DIR" ]; then
        local storage_usage
        storage_usage=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
        echo -e "${GREEN}💾 Storage Used: $storage_usage${NC}"
    fi
    
    # Memory usage
    if command -v free >/dev/null 2>&1; then
        local mem_usage
        mem_usage=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}' 2>/dev/null || echo "Unknown")
        echo -e "${GREEN}🧠 Memory Usage: $mem_usage${NC}"
    fi
    
    # Show individual model details
    echo ""
    list_models
}

# Function to install a model
install_model() {
    local model_name="$1"
    
    if [ -z "$model_name" ]; then
        echo -e "${RED}❌ Model name required${NC}"
        echo "Usage: $0 install MODEL_NAME"
        return 1
    fi
    
    log "Installing model: $model_name"
    
    if ! check_ollama_ready; then
        echo -e "${RED}❌ Ollama service not available${NC}"
        return 1
    fi
    
    echo -e "${BLUE}📥 Installing model: $model_name${NC}"
    
    if ollama pull "$model_name"; then
        echo -e "${GREEN}✅ Successfully installed $model_name${NC}"
        log "Successfully installed model: $model_name"
        
        # Verify installation
        if ollama list | grep -q "$model_name"; then
            echo -e "${GREEN}✅ Installation verified${NC}"
        else
            echo -e "${YELLOW}⚠️ Installation may not have completed properly${NC}"
        fi
    else
        echo -e "${RED}❌ Failed to install $model_name${NC}"
        log "Failed to install model: $model_name"
        return 1
    fi
}

# Function to remove a model
remove_model() {
    local model_name="$1"
    
    if [ -z "$model_name" ]; then
        echo -e "${RED}❌ Model name required${NC}"
        echo "Usage: $0 remove MODEL_NAME"
        return 1
    fi
    
    log "Removing model: $model_name"
    
    if ! check_ollama_ready; then
        echo -e "${RED}❌ Ollama service not available${NC}"
        return 1
    fi
    
    # Confirm removal
    echo -e "${YELLOW}⚠️ Are you sure you want to remove $model_name? (y/N)${NC}"
    read -r confirmation
    
    if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
        echo "Operation cancelled"
        return 0
    fi
    
    echo -e "${BLUE}🗑️ Removing model: $model_name${NC}"
    
    if ollama rm "$model_name"; then
        echo -e "${GREEN}✅ Successfully removed $model_name${NC}"
        log "Successfully removed model: $model_name"
    else
        echo -e "${RED}❌ Failed to remove $model_name${NC}"
        log "Failed to remove model: $model_name"
        return 1
    fi
}

# Function to optimize models
optimize_models() {
    log "Optimizing models"
    
    echo -e "${BLUE}⚡ Optimizing model performance${NC}"
    
    if ! check_ollama_ready; then
        echo -e "${RED}❌ Ollama service not available${NC}"
        return 1
    fi
    
    # Get current model count
    local model_count
    model_count=$(ollama list 2>/dev/null | tail -n +2 | wc -l || echo "0")
    
    if [ "$model_count" -eq 0 ]; then
        echo -e "${YELLOW}⚠️ No models to optimize${NC}"
        return 0
    fi
    
    echo "🔧 Running optimization tasks..."
    
    # 1. Memory optimization
    echo "  - Optimizing memory usage..."
    # Force garbage collection if supported
    curl -s -X POST "$API_URL/api/generate" \
        -H "Content-Type: application/json" \
        -d '{"model":"","prompt":"","stream":false,"options":{"temperature":0}}' \
        >/dev/null 2>&1 || true
    
    # 2. Cache optimization
    echo "  - Clearing temporary caches..."
    if [ -d "/tmp/ollama" ]; then
        rm -rf /tmp/ollama/* 2>/dev/null || true
    fi
    
    # 3. Model file optimization
    echo "  - Checking model file integrity..."
    local corrupted_models=()
    
    # Check each model (simplified check)
    while IFS= read -r model_line; do
        if [ -n "$model_line" ] && [ "$model_line" != "NAME" ]; then
            local model_name
            model_name=$(echo "$model_line" | awk '{print $1}')
            
            if [ -n "$model_name" ] && [ "$model_name" != "NAME" ]; then
                # Quick test by trying to get model info
                if ! ollama show "$model_name" >/dev/null 2>&1; then
                    corrupted_models+=("$model_name")
                fi
            fi
        fi
    done < <(ollama list 2>/dev/null | tail -n +2)
    
    if [ ${#corrupted_models[@]} -gt 0 ]; then
        echo -e "${YELLOW}⚠️ Found potentially corrupted models:${NC}"
        for model in "${corrupted_models[@]}"; do
            echo "    - $model"
        done
    else
        echo -e "${GREEN}✅ All models appear healthy${NC}"
    fi
    
    echo -e "${GREEN}✅ Optimization complete${NC}"
    log "Model optimization completed"
}

# Function to cleanup unused models
cleanup_models() {
    log "Cleaning up unused models"
    
    echo -e "${BLUE}🧹 Cleaning up unused models and files${NC}"
    
    # Clean temporary files
    if [ -d "/tmp/ollama" ]; then
        echo "  - Cleaning temporary files..."
        rm -rf /tmp/ollama/* 2>/dev/null || true
    fi
    
    # Clean old logs (keep last 10)
    if [ -d "/app/logs" ]; then
        echo "  - Cleaning old log files..."
        find /app/logs -name "*.log" -type f | sort -r | tail -n +11 | xargs rm -f 2>/dev/null || true
    fi
    
    # Clean old backups (keep last 5)
    if [ -d "$BACKUP_DIR" ]; then
        echo "  - Cleaning old backup files..."
        find "$BACKUP_DIR" -name "*.tar.gz" -type f | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
    fi
    
    echo -e "${GREEN}✅ Cleanup complete${NC}"
    log "Cleanup completed"
}

# Function to backup models
backup_models() {
    log "Starting model backup"
    
    echo -e "${BLUE}💾 Creating model backup${NC}"
    
    mkdir -p "$BACKUP_DIR"
    
    local backup_name="models_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    if [ ! -d "$MODELS_DIR" ]; then
        echo -e "${RED}❌ Models directory not found${NC}"
        return 1
    fi
    
    echo "  - Creating archive..."
    if tar -czf "$backup_path" -C "$(dirname "$MODELS_DIR")" "$(basename "$MODELS_DIR")" 2>/dev/null; then
        local backup_size
        backup_size=$(du -sh "$backup_path" | cut -f1)
        echo -e "${GREEN}✅ Backup created: $backup_name ($backup_size)${NC}"
        log "Backup created: $backup_path ($backup_size)"
        echo "📂 Location: $backup_path"
    else
        echo -e "${RED}❌ Backup failed${NC}"
        log "Backup failed: $backup_path"
        return 1
    fi
}

# Function to update a model
update_model() {
    local model_name="$1"
    
    if [ -z "$model_name" ]; then
        echo -e "${RED}❌ Model name required${NC}"
        echo "Usage: $0 update MODEL_NAME"
        return 1
    fi
    
    log "Updating model: $model_name"
    
    echo -e "${BLUE}🔄 Updating model: $model_name${NC}"
    
    # Check if model exists
    if ! ollama list | grep -q "$model_name"; then
        echo -e "${YELLOW}⚠️ Model $model_name not found locally${NC}"
        echo "Would you like to install it instead? (y/N)"
        read -r confirmation
        
        if [[ "$confirmation" =~ ^[Yy]$ ]]; then
            install_model "$model_name"
            return $?
        else
            return 1
        fi
    fi
    
    # Re-pull the model to update it
    if ollama pull "$model_name"; then
        echo -e "${GREEN}✅ Successfully updated $model_name${NC}"
        log "Successfully updated model: $model_name"
    else
        echo -e "${RED}❌ Failed to update $model_name${NC}"
        log "Failed to update model: $model_name"
        return 1
    fi
}

# Function to run health check
run_health_check() {
    if [ -f "/app/scripts/health-check.sh" ]; then
        /app/scripts/health-check.sh
    else
        echo -e "${RED}❌ Health check script not found${NC}"
        return 1
    fi
}

# Main function
main() {
    local command="$1"
    shift || true
    
    # Create log directory
    mkdir -p /app/logs 2>/dev/null || true
    
    case "$command" in
        "list"|"ls")
            list_models
            ;;
        "status"|"stat")
            show_status
            ;;
        "install"|"add")
            install_model "$1"
            ;;
        "remove"|"rm"|"delete")
            remove_model "$1"
            ;;
        "optimize"|"opt")
            optimize_models
            ;;
        "cleanup"|"clean")
            cleanup_models
            ;;
        "backup")
            backup_models
            ;;
        "update"|"upgrade")
            update_model "$1"
            ;;
        "health"|"check")
            run_health_check
            ;;
        "help"|"-h"|"--help"|"")
            show_usage
            ;;
        *)
            echo -e "${RED}❌ Unknown command: $command${NC}"
            echo ""
            show_usage
            return 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"