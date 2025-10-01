#!/bin/bash

# CatOps Update Script
# curl -sfL https://get.catops.io/update.sh | bash

set -e

# Colors - Orange Theme
ORANGE='\033[38;5;214m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Print header
print_header() {
    printf "\n"
    printf "${ORANGE} ██████╗ █████╗ ████████╗ ██████╗ ██████╗ ███████╗${NC}\n"
    printf "${ORANGE}██╔════╝██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝${NC}\n"
    printf "${ORANGE}██║     ███████║   ██║   ██║   ██║██████╔╝███████╗${NC}\n"
    printf "${ORANGE}██║     ██╔══██║   ██║   ██║   ██║██╔═══╝ ╚════██║${NC}\n"
    printf "${ORANGE}╚██████╗██║  ██║   ██║   ╚██████╔╝██║     ███████║${NC}\n"
    printf "${ORANGE} ╚═════╝╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝     ╚══════╝${NC}\n"
    printf "\n"
    printf "                    ${WHITE}Server Monitor${NC}\n"
    printf "\n"
}

# Print section
print_section() {
    local title="$1"
    local total_width=70
    local prefix="+- "
    local suffix="-+"
    local title_len=${#title}
    local dash_count=$((total_width - ${#prefix} - ${#suffix} - title_len))
    if [ $dash_count -lt 0 ]; then dash_count=0; fi
    printf "${ORANGE}${prefix}${WHITE}%s${ORANGE}%s${suffix}${NC}\n" "$title" "$(printf '%*s' $dash_count | sed 's/ /-/g')"
}

# Print section end
print_section_end() {
    local total_width=70
    printf "${ORANGE}+%s+${NC}\n" "$(printf '%*s' $((total_width-2)) | sed 's/ /-/g')"
}

# Print status
print_status() {
    local type="$1"
    local message="$2"
    case $type in
        "success") printf "  ${GREEN}✓ $message${NC}\n" ;;
        "info") printf "  ${BLUE}ℹ $message${NC}\n" ;;
        "warning") printf "  ${YELLOW}⚠ $message${NC}\n" ;;
        "error") printf "  ${RED}✗ $message${NC}\n" ;;
    esac
}

# Check if catops is installed
check_installation() {
    if ! command -v catops &> /dev/null; then
        print_status "error" "CatOps is not installed"
        print_status "info" "Please install first: curl -sfL https://get.catops.io/install.sh | bash"
        exit 1
    fi
}

# Check for updates via API
check_for_updates() {
    print_status "info" "Checking for updates..."
    
    # Get current version from catops binary
    CURRENT_VERSION=$(catops --version 2>/dev/null | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | sed 's/v//' || echo "0.0.0")
    
    # Check API for latest version with proper headers
    API_RESPONSE=$(curl -s "https://api.catops.io/api/versions/check" \
        -H "User-Agent: CatOps-CLI/1.0.0" \
        -H "X-Platform: $(uname -s | tr '[:upper:]' '[:lower:]')" \
        -H "X-Version: 1.0.0" \
        2>/dev/null || echo "{}")
    LATEST_VERSION=$(echo "$API_RESPONSE" | grep -o '"latest_version":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "0.0.0")
    
    if [ "$LATEST_VERSION" = "0.0.0" ] || [ "$LATEST_VERSION" = "$CURRENT_VERSION" ]; then
        print_status "info" "No updates available (current: $CURRENT_VERSION)"
        print_section_end
        return 1
    fi
    
    print_status "success" "Update available! Latest version: $LATEST_VERSION"
    return 0
}

# Function to kill duplicate processes
kill_duplicate_processes() {
    # Find all catops daemon processes
    local pids=$(pgrep -f "catops daemon" 2>/dev/null)
    if [ -n "$pids" ]; then
        local pid_count=$(echo "$pids" | wc -l)
        if [ "$pid_count" -gt 1 ]; then
            # Keep the first process, kill the rest
            local first_pid=$(echo "$pids" | head -n1)
            echo "$pids" | tail -n +2 | while read pid; do
                if [ "$pid" != "$first_pid" ]; then
                    kill "$pid" 2>/dev/null
                fi
            done
        fi
    fi
}

# Stop catops service if running
stop_service() {
    # Kill any duplicate processes first
    kill_duplicate_processes
    
    if pgrep -f "catops daemon" > /dev/null; then
        pkill -f "catops daemon" || true
        sleep 2
    fi
}

# Determine OS and architecture
get_system_info() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    
    # Map architecture names
    case $ARCH in
        "x86_64") ARCH="amd64" ;;
        "aarch64") ARCH="arm64" ;;
        "arm64") ARCH="arm64" ;;
    esac
    
    BINARY_NAME="catops-$OS-$ARCH"
}

# Download and install new version
download_and_install() {
    print_status "info" "Downloading latest version..."
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Download binary
    if curl -sfL "https://get.catops.io/$BINARY_NAME" -o "$TEMP_DIR/catops"; then
        chmod +x "$TEMP_DIR/catops"
        print_status "success" "Download completed"
    else
        print_status "error" "Download failed"
        exit 1
    fi
    
    # Find current catops location
    CURRENT_CATOPS=$(which catops)
    
    # Backup old version
    if [ -f "$CURRENT_CATOPS" ]; then
        cp "$CURRENT_CATOPS" "$CURRENT_CATOPS.backup"
    fi
    
    # Install new version
    if [ -w "$(dirname "$CURRENT_CATOPS")" ]; then
        # Direct replacement
        mv "$TEMP_DIR/catops" "$CURRENT_CATOPS"
    else
        # Use sudo if needed
        sudo mv "$TEMP_DIR/catops" "$CURRENT_CATOPS"
    fi
    
    print_status "success" "Installation completed"
}

# Test new installation
test_installation() {
    print_status "info" "Testing new installation..."
    if catops --help > /dev/null 2>&1; then
        print_status "success" "New version works correctly"
    else
        print_status "error" "New version test failed"
        print_status "info" "Restoring backup..."
        if [ -f "$CURRENT_CATOPS.backup" ]; then
            if [ -w "$(dirname "$CURRENT_CATOPS")" ]; then
                mv "$CURRENT_CATOPS.backup" "$CURRENT_CATOPS"
            else
                sudo mv "$CURRENT_CATOPS.backup" "$CURRENT_CATOPS"
            fi
        fi
        exit 1
    fi
}

# Start service if it was running
start_service() {
    # Kill any duplicate processes before starting
    kill_duplicate_processes
    
    if catops start > /dev/null 2>&1; then
        print_status "success" "Monitoring service started"
    fi
}

# Function to get CPU cores
get_cpu_cores() {
    if [ "$(uname -s)" = "Darwin" ]; then
        # macOS
        sysctl -n hw.ncpu 2>/dev/null || echo "0"
    elif [ "$(uname -s)" = "Linux" ]; then
        # Linux
        nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Function to get total memory in GB
get_total_memory() {
    if [ "$(uname -s)" = "Darwin" ]; then
        # macOS
        local memory_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo "0")
        echo $((memory_bytes / 1024 / 1024 / 1024))
    elif [ "$(uname -s)" = "Linux" ]; then
        # Linux
        local memory_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo "0")
        echo $((memory_kb / 1024 / 1024))
    else
        echo "0"
    fi
}

# Function to get total storage in GB
get_total_storage() {
    if [ "$(uname -s)" = "Darwin" ]; then
        # macOS
        df -g / | tail -1 | awk '{print $2}' 2>/dev/null || echo "0"
    elif [ "$(uname -s)" = "Linux" ]; then
        # Linux
        df -BG / | tail -1 | awk '{print $2}' | sed 's/G//' 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Send update statistics
send_update_stats() {
    local platform=$(uname -s | tr '[:upper:]' '[:lower:]')
    local arch=$(uname -m)
    case $arch in
        "x86_64") arch="amd64" ;;
        "aarch64") arch="arm64" ;;
        "arm64") arch="arm64" ;;
    esac

    # Get server specifications
    local cpu_cores=$(get_cpu_cores)
    local total_memory=$(get_total_memory)
    local total_storage=$(get_total_storage)
    local hostname=$(hostname)
    
    # Get current version from backend API
    local catops_version="0.0.0"  # Default fallback
    
    # Try to get version from backend API
    local version_response=$(curl -s -X GET "https://api.catops.io/api/versions/check" \
        -H "Content-Type: application/json" \
        -H "User-Agent: CatOps-CLI/1.0.0" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$version_response" ]; then
        # Extract version from JSON response using grep and sed
        local extracted_version=$(echo "$version_response" | grep -o '"version":"[^"]*"' | sed 's/"version":"//;s/"//')
        if [ -n "$extracted_version" ] && [ "$extracted_version" != "null" ]; then
            catops_version="$extracted_version"
        fi
    fi
    
    # Prepare JSON data with correct format for new backend
    local json_data="{\"timestamp\":\"$(date +%s)\",\"user_token\":\"\",\"server_info\":{\"hostname\":\"$hostname\",\"os_type\":\"$platform\",\"os_version\":\"$platform\",\"catops_version\":\"$catops_version\"},\"cpu_cores\":$cpu_cores,\"total_memory\":$total_memory,\"total_storage\":$total_storage}"

    # Send stats silently (don't interrupt update) - using CLI install endpoint
    curl -s -X POST "https://api.catops.io/api/cli/install" \
        -H "Content-Type: application/json" \
        -H "User-Agent: CatOps-CLI/1.0.0" \
        -H "X-Platform: $platform" \
        -H "X-Version: 1.0.0" \
        -d "$json_data" \
        >/dev/null 2>&1 || true
}

# Main function
main() {
    print_header
    
    print_section "Updating CatOps"
    
    check_installation
    check_for_updates
    
    # If no updates available, exit after closing section
    if [ $? -eq 1 ]; then
        print_section_end
        exit 0
    fi
    
    stop_service
    get_system_info
    download_and_install
    test_installation
    start_service
    
    print_section_end
    
    print_section "Update Complete"
    print_status "success" "CatOps updated successfully"
    print_status "info" "Run 'catops status' to check your system"
    print_status "info" "Run 'catops --help' to see all commands"
    
    # Send update statistics
    send_update_stats
    
    print_section_end
}

main 