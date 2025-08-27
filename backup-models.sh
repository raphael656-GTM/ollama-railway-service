#!/bin/bash
# Backup and Restore Script for Railway Ollama Models
# Provides disaster recovery and model management capabilities

set -e

# Configuration
MODELS_DIR="/root/.ollama/models"
BACKUP_BASE_DIR="/app/backups"
LOG_FILE="/app/logs/backup.log"
API_URL="http://localhost:11434"
MAX_BACKUPS=5  # Keep last 5 backups
COMPRESSION_LEVEL=6  # Balance between speed and compression

# Colors for output
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' NC=''
fi

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE" 2>/dev/null || echo "$1"
}

# Function to show usage
show_usage() {
    echo -e "${BLUE}Ollama Model Backup & Restore Utility${NC}"
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  backup [NAME]           Create backup (optional custom name)"
    echo "  restore BACKUP_FILE     Restore from backup file"
    echo "  list                    List available backups"
    echo "  status                  Show backup system status"
    echo "  clean                   Clean old backups (keep last $MAX_BACKUPS)"
    echo "  verify BACKUP_FILE      Verify backup integrity"
    echo "  schedule                Set up automated backups"
    echo ""
    echo "Examples:"
    echo "  $0 backup                     # Create timestamped backup"
    echo "  $0 backup phase1_complete     # Create named backup"
    echo "  $0 list                       # Show available backups"
    echo "  $0 restore backup.tar.gz      # Restore from file"
    echo "  $0 verify backup.tar.gz       # Check backup integrity"
}

# Function to check if Ollama is available
check_ollama() {
    curl -s -f "$API_URL/api/tags" > /dev/null 2>&1
}

# Function to create backup
create_backup() {
    local backup_name="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    # Generate backup filename
    if [ -n "$backup_name" ]; then
        local backup_file="models_${backup_name}_${timestamp}.tar.gz"
    else
        local backup_file="models_backup_${timestamp}.tar.gz"
    fi
    
    local backup_path="$BACKUP_BASE_DIR/$backup_file"
    
    log "Starting backup creation: $backup_file"
    echo -e "${BLUE}💾 Creating Model Backup${NC}"
    echo "=========================="
    
    # Create backup directory
    mkdir -p "$BACKUP_BASE_DIR"
    
    # Check if models directory exists
    if [ ! -d "$MODELS_DIR" ]; then
        echo -e "${RED}❌ Models directory not found: $MODELS_DIR${NC}"
        log "ERROR: Models directory not found: $MODELS_DIR"
        return 1
    fi
    
    # Check available space
    local available_space
    available_space=$(df "$BACKUP_BASE_DIR" | awk 'NR==2 {print $4}')
    local models_size
    models_size=$(du -s "$MODELS_DIR" | awk '{print $1}')
    
    if [ "$available_space" -lt $((models_size * 2)) ]; then
        echo -e "${YELLOW}⚠️ Warning: Low disk space. Available: ${available_space}K, Need: ~$((models_size * 2))K${NC}"
    fi
    
    # Get model list for metadata
    local model_list=""
    if check_ollama; then
        echo "📋 Collecting model metadata..."
        model_list=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | paste -sd ',' - || echo "unknown")
    else
        echo -e "${YELLOW}⚠️ Ollama service unavailable, proceeding with file-based backup${NC}"
        model_list="service_unavailable"
    fi
    
    # Create metadata file
    local metadata_file="/tmp/backup_metadata_$timestamp.json"
    cat > "$metadata_file" << EOF
{
    "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
    "backup_name": "$backup_name",
    "models_directory": "$MODELS_DIR",
    "models_list": "$model_list",
    "hostname": "$(hostname)",
    "ollama_version": "$(ollama --version 2>/dev/null || echo 'unknown')",
    "backup_script_version": "1.0.0"
}
EOF
    
    echo "🗜️ Creating compressed archive..."
    local start_time=$(date +%s)
    
    # Create the backup with progress indication
    if tar -czf "$backup_path" \
        -C "$(dirname "$MODELS_DIR")" "$(basename "$MODELS_DIR")" \
        -C /tmp "$(basename "$metadata_file")" \
        2>/dev/null; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local backup_size
        backup_size=$(du -sh "$backup_path" | cut -f1)
        
        echo -e "${GREEN}✅ Backup created successfully!${NC}"
        echo "📂 File: $backup_file"
        echo "📦 Size: $backup_size"
        echo "⏱️ Duration: ${duration}s"
        echo "📍 Path: $backup_path"
        
        log "SUCCESS: Backup created - $backup_file ($backup_size) in ${duration}s"
        
        # Verify backup immediately
        if verify_backup "$backup_path" silent; then
            echo -e "${GREEN}✅ Backup verification passed${NC}"
        else
            echo -e "${YELLOW}⚠️ Backup verification failed, but file was created${NC}"
        fi
        
        # Clean up metadata file
        rm -f "$metadata_file"
        
        # Clean old backups
        clean_old_backups
        
        echo -e "${CYAN}💡 Backup complete: $backup_file${NC}"
        
    else
        echo -e "${RED}❌ Backup creation failed${NC}"
        log "ERROR: Backup creation failed: $backup_file"
        rm -f "$metadata_file"
        return 1
    fi
}

# Function to restore backup
restore_backup() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        echo -e "${RED}❌ Backup file required${NC}"
        echo "Usage: $0 restore BACKUP_FILE"
        return 1
    fi
    
    # Handle relative paths
    if [[ ! "$backup_file" == /* ]]; then
        if [ -f "$BACKUP_BASE_DIR/$backup_file" ]; then
            backup_file="$BACKUP_BASE_DIR/$backup_file"
        elif [ ! -f "$backup_file" ]; then
            echo -e "${RED}❌ Backup file not found: $backup_file${NC}"
            return 1
        fi
    fi
    
    log "Starting restore from: $backup_file"
    echo -e "${BLUE}🔄 Restoring Models from Backup${NC}"
    echo "================================"
    
    # Verify backup before restoring
    if ! verify_backup "$backup_file" silent; then
        echo -e "${RED}❌ Backup verification failed, aborting restore${NC}"
        return 1
    fi
    
    # Stop Ollama if running
    local ollama_was_running=false
    if check_ollama; then
        echo "🛑 Stopping Ollama service for restore..."
        # In Railway, we can't easily stop/start services, so warn user
        echo -e "${YELLOW}⚠️ Warning: Ollama is currently running${NC}"
        echo "   Restore may fail if models are in use"
        echo "   Continue anyway? (y/N)"
        read -r confirmation
        if [[ ! "$confirmation" =~ ^[Yy]$ ]]; then
            echo "Restore cancelled"
            return 0
        fi
        ollama_was_running=true
    fi
    
    # Backup current models directory
    if [ -d "$MODELS_DIR" ]; then
        local current_backup="/tmp/current_models_$(date +%Y%m%d_%H%M%S).tar.gz"
        echo "💾 Creating backup of current models..."
        tar -czf "$current_backup" -C "$(dirname "$MODELS_DIR")" "$(basename "$MODELS_DIR")" 2>/dev/null || true
        echo "📂 Current models backed up to: $current_backup"
    fi
    
    # Extract backup
    echo "📦 Extracting backup..."
    local temp_dir="/tmp/ollama_restore_$$"
    mkdir -p "$temp_dir"
    
    if tar -xzf "$backup_file" -C "$temp_dir" 2>/dev/null; then
        echo -e "${GREEN}✅ Backup extracted successfully${NC}"
        
        # Replace models directory
        if [ -d "$MODELS_DIR" ]; then
            echo "🗑️ Removing current models directory..."
            rm -rf "$MODELS_DIR"
        fi
        
        echo "📁 Installing restored models..."
        if mv "$temp_dir/$(basename "$MODELS_DIR")" "$MODELS_DIR"; then
            echo -e "${GREEN}✅ Models restored successfully${NC}"
            
            # Show restored metadata if available
            if [ -f "$temp_dir/backup_metadata_"*.json ]; then
                local metadata_file=$(ls "$temp_dir/backup_metadata_"*.json | head -1)
                if command -v jq >/dev/null 2>&1; then
                    echo -e "${CYAN}📋 Backup Information:${NC}"
                    jq -r '"Date: " + .backup_date + "\nModels: " + .models_list' "$metadata_file" 2>/dev/null || true
                fi
            fi
            
            log "SUCCESS: Models restored from $backup_file"
            
            # Cleanup
            rm -rf "$temp_dir"
            
            echo -e "${GREEN}🎉 Restore completed successfully!${NC}"
            echo "💡 You may need to restart Ollama service to load models"
            
        else
            echo -e "${RED}❌ Failed to install restored models${NC}"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        echo -e "${RED}❌ Failed to extract backup${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Function to list backups
list_backups() {
    echo -e "${BLUE}📋 Available Backups${NC}"
    echo "==================="
    
    if [ ! -d "$BACKUP_BASE_DIR" ] || [ -z "$(ls -A "$BACKUP_BASE_DIR" 2>/dev/null)" ]; then
        echo -e "${YELLOW}⚠️ No backups found${NC}"
        return 0
    fi
    
    local backup_count=0
    echo "$(printf "%-30s %-10s %-20s" "BACKUP NAME" "SIZE" "DATE")"
    echo "$(printf "%-30s %-10s %-20s" "----------" "----" "----")"
    
    for backup in "$BACKUP_BASE_DIR"/*.tar.gz; do
        if [ -f "$backup" ]; then
            local filename=$(basename "$backup")
            local size=$(du -sh "$backup" | cut -f1)
            local date=$(stat -c %y "$backup" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
            
            printf "%-30s %-10s %-20s\n" "$filename" "$size" "$date"
            ((backup_count++))
        fi
    done
    
    echo ""
    echo -e "${GREEN}Total backups: $backup_count${NC}"
    
    if [ $backup_count -gt $MAX_BACKUPS ]; then
        echo -e "${YELLOW}💡 Tip: Run '$0 clean' to remove old backups${NC}"
    fi
}

# Function to show backup status
show_status() {
    echo -e "${BLUE}📊 Backup System Status${NC}"
    echo "======================="
    
    # Backup directory info
    if [ -d "$BACKUP_BASE_DIR" ]; then
        local backup_count
        backup_count=$(find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f | wc -l)
        local total_size
        total_size=$(du -sh "$BACKUP_BASE_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
        
        echo -e "${GREEN}📂 Backup Directory: $BACKUP_BASE_DIR${NC}"
        echo -e "${GREEN}📊 Total Backups: $backup_count${NC}"
        echo -e "${GREEN}💾 Total Size: $total_size${NC}"
    else
        echo -e "${YELLOW}📂 Backup Directory: Not created${NC}"
    fi
    
    # Models directory info
    if [ -d "$MODELS_DIR" ]; then
        local models_size
        models_size=$(du -sh "$MODELS_DIR" 2>/dev/null | cut -f1 || echo "Unknown")
        echo -e "${GREEN}🤖 Models Directory: $MODELS_DIR ($models_size)${NC}"
    else
        echo -e "${YELLOW}🤖 Models Directory: Not found${NC}"
    fi
    
    # Disk space
    local available_space
    available_space=$(df -h "$BACKUP_BASE_DIR" 2>/dev/null | awk 'NR==2 {print $4}' || echo "Unknown")
    echo -e "${GREEN}💿 Available Space: $available_space${NC}"
    
    # Ollama status
    if check_ollama; then
        local model_count
        model_count=$(ollama list 2>/dev/null | tail -n +2 | wc -l || echo "0")
        echo -e "${GREEN}🟢 Ollama Status: Running ($model_count models loaded)${NC}"
    else
        echo -e "${YELLOW}🟡 Ollama Status: Not responding${NC}"
    fi
    
    # Last backup info
    local latest_backup
    latest_backup=$(find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$latest_backup" ]; then
        local backup_name=$(basename "$latest_backup")
        local backup_date=$(stat -c %y "$latest_backup" 2>/dev/null | cut -d'.' -f1 || echo "unknown")
        echo -e "${GREEN}🕒 Latest Backup: $backup_name ($backup_date)${NC}"
    else
        echo -e "${YELLOW}🕒 Latest Backup: None found${NC}"
    fi
}

# Function to verify backup integrity
verify_backup() {
    local backup_file="$1"
    local silent_mode="$2"
    
    if [ -z "$backup_file" ]; then
        echo -e "${RED}❌ Backup file required${NC}"
        return 1
    fi
    
    # Handle relative paths
    if [[ ! "$backup_file" == /* ]]; then
        if [ -f "$BACKUP_BASE_DIR/$backup_file" ]; then
            backup_file="$BACKUP_BASE_DIR/$backup_file"
        fi
    fi
    
    if [ "$silent_mode" != "silent" ]; then
        echo -e "${BLUE}🔍 Verifying Backup${NC}"
        echo "=================="
    fi
    
    # Check if file exists
    if [ ! -f "$backup_file" ]; then
        [ "$silent_mode" != "silent" ] && echo -e "${RED}❌ Backup file not found: $backup_file${NC}"
        return 1
    fi
    
    # Check file size
    local file_size
    file_size=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
    if [ "$file_size" -lt 1000 ]; then
        [ "$silent_mode" != "silent" ] && echo -e "${RED}❌ Backup file too small (${file_size} bytes)${NC}"
        return 1
    fi
    
    # Test archive integrity
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        [ "$silent_mode" != "silent" ] && echo -e "${GREEN}✅ Archive integrity: OK${NC}"
    else
        [ "$silent_mode" != "silent" ] && echo -e "${RED}❌ Archive integrity: FAILED${NC}"
        return 1
    fi
    
    # Check for required contents
    if tar -tzf "$backup_file" | grep -q "models/"; then
        [ "$silent_mode" != "silent" ] && echo -e "${GREEN}✅ Models directory: Found${NC}"
    else
        [ "$silent_mode" != "silent" ] && echo -e "${YELLOW}⚠️ Models directory: Not found${NC}"
    fi
    
    # Check for metadata
    if tar -tzf "$backup_file" | grep -q "backup_metadata"; then
        [ "$silent_mode" != "silent" ] && echo -e "${GREEN}✅ Metadata: Found${NC}"
    else
        [ "$silent_mode" != "silent" ] && echo -e "${YELLOW}⚠️ Metadata: Not found${NC}"
    fi
    
    if [ "$silent_mode" != "silent" ]; then
        local backup_size
        backup_size=$(du -sh "$backup_file" | cut -f1)
        echo -e "${GREEN}📦 Size: $backup_size${NC}"
        echo -e "${GREEN}✅ Backup verification completed${NC}"
    fi
    
    return 0
}

# Function to clean old backups
clean_old_backups() {
    if [ ! -d "$BACKUP_BASE_DIR" ]; then
        return 0
    fi
    
    local backup_files
    backup_files=$(find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f | wc -l)
    
    if [ "$backup_files" -le $MAX_BACKUPS ]; then
        return 0
    fi
    
    echo "🧹 Cleaning old backups (keeping last $MAX_BACKUPS)..."
    
    # Remove oldest backups
    find "$BACKUP_BASE_DIR" -name "*.tar.gz" -type f -printf '%T@ %p\n' | \
        sort -n | head -n -$MAX_BACKUPS | cut -d' ' -f2- | \
        while read -r file; do
            echo "  - Removing: $(basename "$file")"
            rm -f "$file"
            log "Cleaned old backup: $(basename "$file")"
        done
}

# Main function
main() {
    local command="$1"
    shift || true
    
    # Create necessary directories
    mkdir -p /app/logs "$BACKUP_BASE_DIR" 2>/dev/null || true
    
    case "$command" in
        "backup")
            create_backup "$1"
            ;;
        "restore")
            restore_backup "$1"
            ;;
        "list"|"ls")
            list_backups
            ;;
        "status")
            show_status
            ;;
        "verify")
            verify_backup "$1"
            ;;
        "clean")
            clean_old_backups
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