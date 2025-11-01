#!/bin/bash

################################################################################
# Kokoro TTS MCP Server Installer
# Automated installation script for complete setup
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Logging
LOG_FILE="/tmp/claude-voice-tts-install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Installation paths (configurable during installation)
INSTALL_DIR="$HOME/.local/share/claude-code-voice-mcp-server"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/tts-service"
SYSTEMD_DIR="$HOME/.config/systemd/user"
CONDA_DIR="$HOME/miniconda3"
PYTHON_ENV_NAME="tts-mcp"

# Docker configuration
DOCKER_IMAGE="ghcr.io/remsky/kokoro-fastapi-gpu:latest"
CONTAINER_NAME="claude-voice-tts"
TTS_PORT=8880

################################################################################
# Helper functions
################################################################################

print_header() {
    echo
    echo -e "${PURPLE}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}  $1"
    echo -e "${PURPLE}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    echo -e "${RED}Check log file: $LOG_FILE${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    while true; do
        read -p "$prompt" response
        response="${response:-$default}"
        case "$response" in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

check_command() {
    command -v "$1" &> /dev/null
}

error_exit() {
    print_error "$1"
    exit 1
}

################################################################################
# Welcome screen
################################################################################

show_welcome() {
    clear
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║                 Kokoro TTS MCP Server Installation                       ║
║                                                                           ║
║           High-Quality Text-to-Speech with Voice Blending                ║
║                  GPU-Accelerated | Claude MCP Integration                ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo
    print_info "This installer will set up:"
    echo "  • Kokoro-82M TTS model (Docker container)"
    echo "  • MCP server for Claude Code/Desktop integration"
    echo "  • Python environment with all dependencies"
    echo "  • Systemd service for auto-start"
    echo "  • Command-line control tools"
    echo
    print_warning "Requirements:"
    echo "  • NVIDIA GPU with CUDA 12.3+ (or CPU fallback)"
    echo "  • Docker with NVIDIA Container Toolkit (GPU)"
    echo "  • ~4GB disk space (Docker image + models)"
    echo "  • Internet connection"
    echo
    print_info "Installation log: $LOG_FILE"
    echo

    if ! prompt_yes_no "Ready to proceed with installation?" "y"; then
        echo "Installation cancelled."
        exit 0
    fi
}

################################################################################
# System checks
################################################################################

check_system() {
    print_header "System Check"

    # OS check and package manager detection
    print_info "Checking operating system..."

    # Detect OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        OS_TYPE="macos"
        PKG_MANAGER="brew"
        print_success "OS: macOS"
        print_info "Package manager: Homebrew"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        print_success "OS: $PRETTY_NAME"

        # Detect package manager
        if check_command apt-get; then
            OS_TYPE="debian"
            PKG_MANAGER="apt"

            # For distros based on Ubuntu/Debian (like Linux Mint)
            # Use the Ubuntu codename for repository compatibility
            if [ -n "${UBUNTU_CODENAME:-}" ]; then
                DISTRO_CODENAME="$UBUNTU_CODENAME"
                print_info "Detected Ubuntu-based distro, using codename: $DISTRO_CODENAME"
            elif [[ "$ID" == "debian" ]]; then
                DISTRO_CODENAME="$VERSION_CODENAME"
            else
                DISTRO_CODENAME="noble"  # Ubuntu 24.04 LTS fallback
                print_warning "Could not detect codename, using Ubuntu 24.04 LTS (noble)"
            fi
        elif check_command dnf; then
            OS_TYPE="rhel"
            PKG_MANAGER="dnf"
        elif check_command yum; then
            OS_TYPE="rhel"
            PKG_MANAGER="yum"
        elif check_command pacman; then
            OS_TYPE="arch"
            PKG_MANAGER="pacman"
        elif check_command zypper; then
            OS_TYPE="suse"
            PKG_MANAGER="zypper"
        else
            print_error "Could not detect package manager"
            print_info "Supported: apt (Debian/Ubuntu), dnf/yum (RHEL/Fedora), pacman (Arch), zypper (SUSE), brew (macOS)"
            exit 1
        fi

        print_info "Package manager: $PKG_MANAGER"
    else
        print_error "Could not detect OS"
        exit 1
    fi

    # GPU check (NVIDIA only, no support for Apple Silicon/AMD)
    print_info "Checking for NVIDIA GPU..."
    if [[ "$OS_TYPE" == "macos" ]]; then
        print_info "macOS detected - NVIDIA GPU not supported, using CPU"
        HAS_GPU=false
    elif check_command nvidia-smi; then
        GPU_INFO=$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader | head -n1)
        print_success "GPU detected: $GPU_INFO"
        HAS_GPU=true
    else
        print_warning "No NVIDIA GPU detected or nvidia-smi not installed"
        print_info "Will set up CPU-only configuration"
        HAS_GPU=false
    fi

    # Docker check
    print_info "Checking for Docker..."
    if check_command docker; then
        DOCKER_VERSION=$(docker --version)
        print_success "$DOCKER_VERSION"
        HAS_DOCKER=true

        # Check if user can run docker without sudo
        if ! docker ps &> /dev/null; then
            print_warning "Docker requires sudo. Adding user to docker group..."
            sudo usermod -aG docker "$USER"
            print_info "You'll need to log out and back in for docker group to take effect"
            NEEDS_RELOGIN=true
        fi
    else
        print_warning "Docker not installed"
        HAS_DOCKER=false
    fi

    # NVIDIA Container Toolkit check (only if GPU present)
    if [ "$HAS_GPU" = true ]; then
        print_info "Checking for NVIDIA Container Toolkit..."
        if docker info 2>/dev/null | grep -q "Runtimes.*nvidia"; then
            print_success "NVIDIA Container Toolkit detected"
            HAS_NVIDIA_DOCKER=true
        else
            print_warning "NVIDIA Container Toolkit not installed"
            HAS_NVIDIA_DOCKER=false
        fi
    fi

    # Python check
    print_info "Checking for Python..."
    if check_command python3; then
        PYTHON_VERSION=$(python3 --version)
        print_success "$PYTHON_VERSION"
    else
        print_warning "Python 3 not found"
    fi
}

################################################################################
# Install dependencies
################################################################################

install_dependencies() {
    print_header "Installing Dependencies"

    # Clean up any broken repo files from previous failed installations
    # This must happen BEFORE any apt-get update calls
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        if [ -f /etc/apt/sources.list.d/nvidia-container-toolkit.list ]; then
            print_info "Cleaning up broken files from previous installation attempts..."
            sudo rm -f /etc/apt/sources.list.d/nvidia-container-toolkit.list
            sudo rm -f /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
        fi
    elif [[ "$PKG_MANAGER" == "dnf" ]] || [[ "$PKG_MANAGER" == "yum" ]]; then
        if [ -f /etc/yum.repos.d/nvidia-container-toolkit.repo ]; then
            print_info "Cleaning up broken files from previous installation attempts..."
            sudo rm -f /etc/yum.repos.d/nvidia-container-toolkit.repo
        fi
    fi

    print_info "Installing system packages..."

    # Install packages based on package manager
    case "$PKG_MANAGER" in
        apt)
            sudo apt-get update
            sudo apt-get install -y python3 python3-dev python3-pip python3-venv curl wget git jq
            ;;
        dnf)
            sudo dnf install -y python3 python3-devel python3-pip curl wget git jq
            ;;
        yum)
            sudo yum install -y python3 python3-devel python3-pip curl wget git jq
            ;;
        pacman)
            sudo pacman -Sy --noconfirm python python-pip curl wget git jq
            ;;
        zypper)
            sudo zypper install -y python3 python3-devel python3-pip curl wget git jq
            ;;
        brew)
            # macOS with Homebrew
            brew install python curl wget git jq 2>/dev/null || true
            ;;
        *)
            print_error "Unsupported package manager: $PKG_MANAGER"
            exit 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        print_success "System packages installed"
    else
        error_exit "Failed to install system packages"
    fi

    # Install Docker if not present
    if [ "$HAS_DOCKER" = false ]; then
        print_info "Installing Docker..."
        if prompt_yes_no "Install Docker now?" "y"; then
            if [[ "$OS_TYPE" == "macos" ]]; then
                print_info "Please install Docker Desktop for Mac from: https://www.docker.com/products/docker-desktop"
                print_warning "After installing, restart this script"
                exit 0
            else
                curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
                sudo sh /tmp/get-docker.sh
                sudo usermod -aG docker "$USER"
                print_success "Docker installed"
                print_warning "You'll need to log out and back in for docker group to take effect"
                NEEDS_RELOGIN=true
                HAS_DOCKER=true
            fi
        else
            print_error "Docker is required. Please install manually and re-run this script"
            exit 1
        fi
    fi

    # Install NVIDIA Container Toolkit if GPU present but toolkit missing
    if [ "$HAS_GPU" = true ] && [ "$HAS_NVIDIA_DOCKER" = false ]; then
        print_info "Installing NVIDIA Container Toolkit..."
        if prompt_yes_no "Install NVIDIA Container Toolkit for GPU acceleration?" "y"; then
            install_nvidia_container_toolkit
        else
            print_warning "Proceeding without GPU support (will use CPU)"
            HAS_GPU=false
        fi
    fi
}

# Install NVIDIA Container Toolkit (separate function for different distros)
install_nvidia_container_toolkit() {
    case "$PKG_MANAGER" in
        apt)
            # Use generic Debian repository
            print_info "Adding NVIDIA Container Toolkit repository..."
            curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

            # Use generic stable deb repository
            echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /" | \
                sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

            sudo apt-get update
            sudo apt-get install -y nvidia-container-toolkit
            sudo nvidia-ctk runtime configure --runtime=docker
            sudo systemctl restart docker
            ;;

        dnf|yum)
            # Use generic RPM repository
            print_info "Adding NVIDIA Container Toolkit repository..."
            curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
                sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

            sudo $PKG_MANAGER install -y nvidia-container-toolkit
            sudo nvidia-ctk runtime configure --runtime=docker
            sudo systemctl restart docker
            ;;

        pacman)
            # Arch Linux - use AUR or manual install
            print_warning "Arch Linux: Please install nvidia-container-toolkit from AUR"
            print_info "Run: yay -S nvidia-container-toolkit"
            print_info "Or: paru -S nvidia-container-toolkit"
            if ! prompt_yes_no "Have you installed it?" "n"; then
                print_warning "Proceeding without GPU support"
                HAS_GPU=false
                return
            fi
            sudo nvidia-ctk runtime configure --runtime=docker
            sudo systemctl restart docker
            ;;

        zypper)
            print_warning "SUSE: Please install nvidia-container-toolkit manually"
            print_info "See: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html"
            if ! prompt_yes_no "Have you installed it?" "n"; then
                print_warning "Proceeding without GPU support"
                HAS_GPU=false
                return
            fi
            sudo nvidia-ctk runtime configure --runtime=docker
            sudo systemctl restart docker
            ;;

        *)
            print_error "NVIDIA Container Toolkit installation not supported for $PKG_MANAGER"
            print_warning "Proceeding without GPU support"
            HAS_GPU=false
            return
            ;;
    esac

    if [ $? -eq 0 ]; then
        print_success "NVIDIA Container Toolkit installed"
        HAS_NVIDIA_DOCKER=true
    else
        print_error "Failed to install NVIDIA Container Toolkit"
        print_warning "Proceeding without GPU support"
        HAS_GPU=false
    fi
}

################################################################################
# Setup Python environment
################################################################################

setup_python_env() {
    print_header "Python Environment Setup"

    # Check for conda
    if check_command conda; then
        print_info "Conda detected. Using conda environment."
        USE_CONDA=true
    else
        print_info "Conda not found. Installing Miniconda..."

        # Ask for custom conda path
        read -p "Conda installation directory [$CONDA_DIR]: " custom_conda
        CONDA_DIR="${custom_conda:-$CONDA_DIR}"
        CONDA_DIR="${CONDA_DIR/#\~/$HOME}"

        # Download and install Miniconda
        if [[ "$OS_TYPE" == "macos" ]]; then
            if [[ $(uname -m) == "arm64" ]]; then
                MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh"
            else
                MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh"
            fi
        else
            MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
        fi
        MINICONDA_INSTALLER="/tmp/miniconda.sh"

        print_info "Downloading Miniconda..."
        if wget -q --show-progress "$MINICONDA_URL" -O "$MINICONDA_INSTALLER"; then
            print_success "Downloaded Miniconda installer"
        else
            error_exit "Failed to download Miniconda"
        fi

        print_info "Installing Miniconda to $CONDA_DIR..."
        if bash "$MINICONDA_INSTALLER" -b -p "$CONDA_DIR"; then
            print_success "Miniconda installed"
            rm "$MINICONDA_INSTALLER"
        else
            error_exit "Failed to install Miniconda"
        fi

        # Initialize conda
        eval "$("$CONDA_DIR/bin/conda" shell.bash hook)"
        USE_CONDA=true
    fi

    # Create Python environment
    if [ "$USE_CONDA" = true ]; then
        print_info "Creating conda environment: $PYTHON_ENV_NAME..."

        if conda env list | grep -q "^$PYTHON_ENV_NAME "; then
            print_warning "Environment $PYTHON_ENV_NAME already exists"
            if prompt_yes_no "Remove and recreate?" "n"; then
                conda env remove -n "$PYTHON_ENV_NAME" -y
            fi
        fi

        if ! conda env list | grep -q "^$PYTHON_ENV_NAME "; then
            conda create -n "$PYTHON_ENV_NAME" python=3.10 -y
            print_success "Conda environment created"
        fi

        # Activate environment
        eval "$(conda shell.bash hook)"
        conda activate "$PYTHON_ENV_NAME"

        # Install uv
        print_info "Installing uv package manager..."
        pip install --quiet uv
        print_success "uv installed"
    else
        # Use venv
        print_info "Creating Python virtual environment..."
        ENV_DIR="$HOME/.local/share/tts-mcp-env"
        python3 -m venv "$ENV_DIR"
        source "$ENV_DIR/bin/activate"

        # Install uv
        print_info "Installing uv package manager..."
        pip install --quiet uv
        print_success "uv installed"
    fi
}

################################################################################
# Pull Docker image
################################################################################

pull_docker_image() {
    print_header "Docker Image Setup"

    # Determine which image to use
    if [ "$HAS_GPU" = true ] && [ "$HAS_NVIDIA_DOCKER" = true ]; then
        DOCKER_IMAGE="ghcr.io/remsky/kokoro-fastapi-gpu:latest"
        print_info "Using GPU-accelerated image"
    else
        DOCKER_IMAGE="ghcr.io/remsky/kokoro-fastapi-cpu:latest"
        print_info "Using CPU-only image"
    fi

    print_info "Pulling Docker image: $DOCKER_IMAGE"
    print_warning "This may take several minutes (downloading ~2-3GB)..."
    print_info "Monitor progress: watch -n 2 'docker system df'"
    echo

    # Pull image (progress bar may not show due to logging redirection)
    if docker pull "$DOCKER_IMAGE"; then
        echo
        print_success "Docker image pulled successfully"
    else
        error_exit "Failed to pull Docker image"
    fi
}

################################################################################
# Install files
################################################################################

install_files() {
    print_header "Installing Files"

    # Create directories
    print_info "Creating installation directories..."
    mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$CONFIG_DIR" "$SYSTEMD_DIR"
    print_success "Directories created"

    # Copy MCP server
    print_info "Installing MCP server..."
    cp -r "$SCRIPT_DIR/src" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/pyproject.toml" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/LICENSE" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/.env.example" "$INSTALL_DIR/" 2>/dev/null || true
    print_success "MCP server installed to $INSTALL_DIR"

    # Install Python dependencies
    print_info "Installing Python dependencies..."
    cd "$INSTALL_DIR"
    if [ "$USE_CONDA" = true ]; then
        conda run -n "$PYTHON_ENV_NAME" uv pip install -e .
    else
        source "$HOME/.local/share/tts-mcp-env/bin/activate"
        uv pip install -e .
    fi
    print_success "Dependencies installed"

    # Copy control scripts
    print_info "Installing control scripts..."
    cp "$SCRIPT_DIR/bin/tts" "$BIN_DIR/"
    cp "$SCRIPT_DIR/bin/tts-voice-mode" "$BIN_DIR/"
    cp "$SCRIPT_DIR/bin/tts-auto-speak" "$BIN_DIR/"
    chmod +x "$BIN_DIR/tts"
    chmod +x "$BIN_DIR/tts-voice-mode"
    chmod +x "$BIN_DIR/tts-auto-speak"
    print_success "Control scripts installed"

    # Copy systemd service (Linux only)
    if [[ "$OS_TYPE" != "macos" ]]; then
        print_info "Installing systemd service..."
        envsubst < "$SCRIPT_DIR/config/systemd/claude-voice-tts.service" > "$SYSTEMD_DIR/claude-voice-tts.service"
        systemctl --user daemon-reload
        print_success "Systemd service installed"
    else
        print_info "macOS: Systemd not available, use 'tts start' manually or docker-compose"
    fi

    # Copy config
    if [ ! -f "$CONFIG_DIR/config.json" ]; then
        print_info "Creating default configuration..."
        cp "$SCRIPT_DIR/config/tts-service/config.json.default" "$CONFIG_DIR/config.json"
        print_success "Configuration created"
    else
        print_info "Configuration already exists (not overwriting)"
    fi

    # Create .env file for MCP
    print_info "Creating .env file..."
    cat > "$INSTALL_DIR/.env" << EOF
KOKORO_BASE_URL=http://localhost:$TTS_PORT
DEFAULT_VOICE=af_bella
DEFAULT_SPEED=1.0
OUTPUT_DIR=$HOME/tts_output
TIMEOUT=30
EOF
    print_success ".env file created"

    # Create output directory
    mkdir -p "$HOME/tts_output"
}

################################################################################
# Configure Claude Desktop
################################################################################

configure_claude() {
    print_header "Claude Configuration"

    local mcp_command="uv"
    local mcp_args=("--directory" "$INSTALL_DIR" "run" "claude-voice-mcp")

    # Configure Claude Desktop
    print_info "Configuring Claude Desktop..."
    local claude_desktop_config="$HOME/.config/claude/claude_desktop_config.json"

    if [ ! -f "$claude_desktop_config" ]; then
        print_info "Creating Claude Desktop config..."
        mkdir -p "$(dirname "$claude_desktop_config")"

        cat > "$claude_desktop_config" << EOF
{
  "mcpServers": {
    "claude-voice-tts": {
      "command": "$mcp_command",
      "args": [
        "--directory",
        "$INSTALL_DIR",
        "run",
        "claude-voice-mcp"
      ],
      "env": {
        "KOKORO_BASE_URL": "http://localhost:$TTS_PORT"
      }
    }
  }
}
EOF
        print_success "Claude Desktop configured"
    else
        print_warning "Claude Desktop config exists - manual update needed"
        print_info "Add to $claude_desktop_config:"
        cat << EOF
  "claude-voice-tts": {
    "command": "$mcp_command",
    "args": ["--directory", "$INSTALL_DIR", "run", "claude-voice-mcp"],
    "env": {"KOKORO_BASE_URL": "http://localhost:$TTS_PORT"}
  }
EOF
    fi

    # Configure Claude Code (CLI)
    print_info "Configuring Claude Code..."
    local claude_code_config="$HOME/.claude/mcp_settings.json"

    if [ ! -f "$claude_code_config" ]; then
        print_info "Creating Claude Code MCP config..."
        mkdir -p "$(dirname "$claude_code_config")"

        cat > "$claude_code_config" << EOF
{
  "mcpServers": {
    "claude-voice-tts": {
      "command": "$mcp_command",
      "args": [
        "--directory",
        "$INSTALL_DIR",
        "run",
        "claude-voice-mcp"
      ],
      "env": {
        "KOKORO_BASE_URL": "http://localhost:$TTS_PORT"
      }
    }
  }
}
EOF
        print_success "Claude Code configured"
    else
        print_warning "Claude Code config exists - manual update needed"
        print_info "Add to $claude_code_config:"
        cat << EOF
  "claude-voice-tts": {
    "command": "$mcp_command",
    "args": ["--directory", "$INSTALL_DIR", "run", "claude-voice-mcp"],
    "env": {"KOKORO_BASE_URL": "http://localhost:$TTS_PORT"}
  }
EOF
    fi

    echo
    print_success "MCP server configured for both Claude Desktop and Claude Code"
    print_info "Restart Claude Desktop/Code to activate"
}

################################################################################
# Start service
################################################################################

start_service() {
    print_header "Starting Service"

    print_info "Starting Kokoro TTS service..."

    if [[ "$OS_TYPE" == "macos" ]]; then
        # macOS: Start Docker container directly
        print_info "Starting Docker container..."
        docker run -d --name claude-voice-tts -p $TTS_PORT:8880 "$DOCKER_IMAGE"

        if [ $? -eq 0 ]; then
            print_success "Docker container started"
        else
            print_error "Failed to start Docker container"
            return 1
        fi
    else
        # Linux: Use systemd
        if systemctl --user start claude-voice-tts.service; then
            print_success "Service started"
        else
            print_error "Failed to start service"
            return 1
        fi
    fi

    # Wait for service to be ready (both platforms)
    print_info "Waiting for service to be ready..."
    for i in {1..30}; do
        if curl -s -f http://localhost:$TTS_PORT/v1/audio/voices > /dev/null 2>&1; then
            print_success "Service is ready!"
            return 0
        fi
        sleep 1
    done

    print_warning "Service started but not responding yet. Check: tts logs"
}

################################################################################
# Enable auto-start
################################################################################

enable_autostart() {
    print_header "Auto-Start Configuration"

    if [[ "$OS_TYPE" == "macos" ]]; then
        print_info "macOS: Auto-start not configured (no systemd)"
        print_info "Use 'tts start' manually or configure Docker Desktop to start container on boot"
        return 0
    fi

    if prompt_yes_no "Enable auto-start on login?" "y"; then
        systemctl --user enable claude-voice-tts.service
        print_success "Auto-start enabled"
    fi
}

################################################################################
# Run tests
################################################################################

run_tests() {
    print_header "Testing Installation"

    if prompt_yes_no "Run installation test (will play audio)?" "y"; then
        print_info "Testing Kokoro TTS service..."
        echo

        # Check/install audio player first
        local player=""
        if check_command ffplay; then
            player="ffplay"
        elif check_command mpg123; then
            player="mpg123"
        else
            print_warning "No audio player found (ffplay or mpg123)"
            if prompt_yes_no "Install ffmpeg for audio playback?" "y"; then
                case "$PKG_MANAGER" in
                    apt)
                        sudo apt-get install -y ffmpeg
                        ;;
                    dnf|yum)
                        sudo $PKG_MANAGER install -y ffmpeg
                        ;;
                    pacman)
                        sudo pacman -S --noconfirm ffmpeg
                        ;;
                    zypper)
                        sudo zypper install -y ffmpeg
                        ;;
                    brew)
                        brew install ffmpeg
                        ;;
                esac

                if check_command ffplay; then
                    player="ffplay"
                    print_success "ffmpeg installed"
                fi
            fi
        fi

        # Test API endpoint
        print_info "Checking API endpoint..."
        if curl -s -f http://localhost:$TTS_PORT/v1/audio/voices > /dev/null 2>&1; then
            print_success "API endpoint is accessible"
            echo

            # Generate test speech
            print_info "Generating test speech with voice 'af_bella'..."
            local test_output="/tmp/kokoro-test-$(date +%s).mp3"
            local test_text="Hello! This is Kokoro Text to Speech. The installation was successful, and I am now running on your system with GPU acceleration. Enjoy high quality speech synthesis!"

            if curl -s -X POST http://localhost:$TTS_PORT/v1/audio/speech \
                -H "Content-Type: application/json" \
                -d "{\"model\":\"kokoro\",\"input\":\"$test_text\",\"voice\":\"af_bella\",\"speed\":1.0,\"response_format\":\"mp3\"}" \
                -o "$test_output" 2>&1; then

                if [ -f "$test_output" ] && [ -s "$test_output" ]; then
                    local size=$(du -h "$test_output" | cut -f1)
                    print_success "Test audio generated ($size)"
                    echo

                    # Play audio automatically
                    if [ -n "$player" ]; then
                        print_info "Playing audio through speakers..."
                        echo -e "${CYAN}♪ Listen for the test message...${NC}"
                        echo

                        if [[ "$player" == "ffplay" ]]; then
                            ffplay -nodisp -autoexit "$test_output" 2>/dev/null
                        else
                            mpg123 -q "$test_output" 2>/dev/null
                        fi

                        echo
                        print_success "Audio playback complete!"
                        print_info "Test file saved: $test_output"
                    else
                        print_warning "No audio player available"
                        print_info "Test file saved: $test_output"
                        print_info "Play manually with: ffplay $test_output"
                    fi
                else
                    print_error "Test audio file is empty or missing"
                    return 1
                fi
            else
                print_error "Failed to generate test speech"
                return 1
            fi
        else
            print_error "API endpoint not accessible"
            print_info "Check service status: tts logs"
            return 1
        fi

        echo
        print_success "Installation test completed successfully!"
    fi
}

################################################################################
# Show completion
################################################################################

show_completion() {
    print_header "Installation Complete"

    cat << EOF
${GREEN}✓ Kokoro TTS MCP Server installation complete!${NC}

${PURPLE}Quick Start:${NC}

  1. Control the service:
     ${CYAN}tts start${NC}     - Start TTS service
     ${CYAN}tts stop${NC}      - Stop TTS service
     ${CYAN}tts status${NC}    - Check service status
     ${CYAN}tts test${NC}      - Test service

  2. Use with Claude Desktop:
     - Restart Claude Desktop
     - The MCP server will auto-connect
     - Use tools: generate_speech, list_voices, check_status

  3. Direct API access:
     ${CYAN}curl -X POST http://localhost:$TTS_PORT/v1/audio/speech \\
       -H "Content-Type: application/json" \\
       -d '{"model":"kokoro","input":"Hello!","voice":"af_bella"}' \\
       -o output.mp3${NC}

${PURPLE}Configuration:${NC}
  • Service URL: ${CYAN}http://localhost:$TTS_PORT${NC}
  • Config: ${CYAN}$CONFIG_DIR/config.json${NC}
  • MCP server: ${CYAN}$INSTALL_DIR${NC}
  • Logs: ${CYAN}journalctl --user -u claude-voice-tts.service${NC}

${PURPLE}Voice Blending:${NC}
  Use syntax: ${CYAN}af_bella(2)+af_sky(1)${NC}
  Example: 2 parts Bella + 1 part Sky

${PURPLE}Documentation:${NC}
  • README: ${CYAN}$INSTALL_DIR/README.md${NC}
  • Installation log: ${CYAN}$LOG_FILE${NC}

EOF

    if [ "${NEEDS_RELOGIN:-false}" = true ]; then
        print_warning "Please log out and back in to complete Docker setup"
    fi

    print_success "Enjoy your high-quality text-to-speech!"
    echo
}

################################################################################
# Main installation flow
################################################################################

main() {
    show_welcome
    check_system
    install_dependencies
    setup_python_env
    pull_docker_image
    install_files
    configure_claude
    start_service
    enable_autostart
    run_tests
    show_completion
}

# Run main installation
main
