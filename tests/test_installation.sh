#!/bin/bash

# Test script for Kokoro TTS MCP installation

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_header() {
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
}

FAILED=0

fail_test() {
    print_error "$1"
    FAILED=$((FAILED + 1))
}

print_header "Kokoro TTS MCP Installation Test"

# Test 1: Check files exist
print_info "Testing file installation..."

FILES=(
    "$HOME/.local/bin/tts"
    "$HOME/.local/share/claude-code-voice-mcp-server/src/claude_voice_mcp.py"
    "$HOME/.local/share/claude-code-voice-mcp-server/pyproject.toml"
    "$HOME/.config/tts-service/config.json"
    "$HOME/.config/systemd/user/claude-voice-tts.service"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        print_success "Found: $file"
    else
        fail_test "Missing: $file"
    fi
done

# Test 2: Check tts command is executable
print_info "Testing tts command..."
if command -v tts &> /dev/null; then
    print_success "tts command is in PATH"
else
    fail_test "tts command not found in PATH"
fi

# Test 3: Check systemd service
print_info "Testing systemd service..."
if systemctl --user list-unit-files | grep -q "claude-voice-tts.service"; then
    print_success "Systemd service registered"

    if systemctl --user is-active --quiet claude-voice-tts.service; then
        print_success "Service is running"
    else
        fail_test "Service is not running"
    fi
else
    fail_test "Systemd service not registered"
fi

# Test 4: Check Docker container
print_info "Testing Docker container..."
if docker ps | grep -q "claude-voice-tts"; then
    print_success "Docker container is running"
else
    fail_test "Docker container is not running"
fi

# Test 5: Check API endpoint
print_info "Testing API endpoint..."
if curl -s -f http://localhost:8880/v1/audio/voices > /dev/null 2>&1; then
    print_success "API endpoint is accessible"

    # Get voice count
    voice_count=$(curl -s http://localhost:8880/v1/audio/voices | jq '. | length' 2>/dev/null || echo "?")
    print_info "Available voices: $voice_count"
else
    fail_test "API endpoint is not accessible"
fi

# Test 6: Check Python environment
print_info "Testing Python environment..."
if conda env list 2>/dev/null | grep -q "tts-mcp"; then
    print_success "Conda environment 'tts-mcp' exists"
elif [ -d "$HOME/.local/share/tts-mcp-env" ]; then
    print_success "Python venv exists"
else
    fail_test "No Python environment found"
fi

# Test 7: Check MCP server can import
print_info "Testing MCP server import..."
if cd "$HOME/.local/share/claude-code-voice-mcp-server" && python3 -c "from src.claude_voice_mcp import mcp" 2>/dev/null; then
    print_success "MCP server imports successfully"
else
    fail_test "MCP server import failed"
fi

# Test 8: Check Claude Desktop config
print_info "Testing Claude Desktop configuration..."
if [ -f "$HOME/.config/claude/claude_desktop_config.json" ]; then
    print_success "Claude Desktop config exists"

    if grep -q "claude-voice-tts" "$HOME/.config/claude/claude_desktop_config.json" 2>/dev/null; then
        print_success "Kokoro TTS MCP configured in Claude Desktop"
    else
        fail_test "Kokoro TTS MCP not found in Claude Desktop config"
    fi
else
    fail_test "Claude Desktop config not found"
fi

# Summary
print_header "Test Summary"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    echo
    print_info "Installation is complete and working correctly."
    echo
    exit 0
else
    echo -e "${RED}$FAILED test(s) failed ✗${NC}"
    echo
    print_info "Some components may need attention. Check the errors above."
    echo
    exit 1
fi
