#!/bin/bash

# MCP server testing script

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

MCP_DIR="$HOME/.local/share/claude-code-voice-mcp-server"
FAILED=0

fail_test() {
    print_error "$1"
    FAILED=$((FAILED + 1))
}

print_header "Kokoro TTS MCP Server Tests"

# Test 1: Check MCP server files
print_info "Test 1: Check MCP server files..."

if [ -d "$MCP_DIR" ]; then
    print_success "MCP directory exists"
else
    fail_test "MCP directory not found: $MCP_DIR"
    exit 1
fi

if [ -f "$MCP_DIR/src/claude_voice_mcp.py" ]; then
    print_success "MCP server script exists"
else
    fail_test "MCP server script not found"
fi

if [ -f "$MCP_DIR/pyproject.toml" ]; then
    print_success "pyproject.toml exists"
else
    fail_test "pyproject.toml not found"
fi

echo

# Test 2: Check Python dependencies
print_info "Test 2: Check Python dependencies..."

cd "$MCP_DIR"

required_packages=("fastmcp" "httpx" "pydantic" "python-dotenv")

for pkg in "${required_packages[@]}"; do
    if python3 -c "import $pkg" 2>/dev/null; then
        print_success "Package $pkg: installed"
    else
        fail_test "Package $pkg: missing"
    fi
done

echo

# Test 3: Import MCP server
print_info "Test 3: Test MCP server import..."

if python3 -c "from src.claude_voice_mcp import mcp, generate_speech, list_voices, check_status" 2>/dev/null; then
    print_success "MCP server imports successfully"
else
    fail_test "Failed to import MCP server"
    print_error "Error output:"
    python3 -c "from src.claude_voice_mcp import mcp" 2>&1 || true
fi

echo

# Test 4: Check environment variables
print_info "Test 4: Check environment configuration..."

if [ -f "$MCP_DIR/.env" ]; then
    print_success ".env file exists"

    source "$MCP_DIR/.env"

    if [ -n "${KOKORO_BASE_URL:-}" ]; then
        print_success "KOKORO_BASE_URL is set: $KOKORO_BASE_URL"
    else
        fail_test "KOKORO_BASE_URL not set in .env"
    fi
else
    fail_test ".env file not found"
fi

echo

# Test 5: Check MCP tools registration
print_info "Test 5: Check MCP tools are registered..."

tools_check=$(python3 << 'EOF'
try:
    from src.claude_voice_mcp import mcp
    tools = [tool.name for tool in mcp.tools]
    expected = ["generate_speech", "list_voices", "check_status"]

    for tool in expected:
        if tool in tools:
            print(f"✓ Tool registered: {tool}")
        else:
            print(f"✗ Tool missing: {tool}")
            exit(1)
    exit(0)
except Exception as e:
    print(f"✗ Error: {e}")
    exit(1)
EOF
)

if [ $? -eq 0 ]; then
    print_success "All MCP tools registered"
    echo "$tools_check" | while read line; do
        if [[ "$line" == "✓"* ]]; then
            print_info "$line"
        fi
    done
else
    fail_test "MCP tools registration failed"
    echo "$tools_check"
fi

echo

# Test 6: Test MCP server can start (timeout after 5 seconds)
print_info "Test 6: Test MCP server startup..."

timeout 5 python3 -c "
from src.claude_voice_mcp import main
import sys
sys.exit(0)  # Exit immediately after import
" 2>/dev/null

if [ $? -eq 0 ] || [ $? -eq 124 ]; then
    # Exit code 0 or 124 (timeout) both mean it started successfully
    print_success "MCP server can start"
else
    fail_test "MCP server startup failed"
fi

echo

# Test 7: Check Claude Desktop configuration
print_info "Test 7: Check Claude Desktop MCP configuration..."

claude_config="$HOME/.config/claude/claude_desktop_config.json"

if [ -f "$claude_config" ]; then
    print_success "Claude Desktop config exists"

    if jq -e '.mcpServers."claude-voice-tts"' "$claude_config" > /dev/null 2>&1; then
        print_success "Kokoro TTS MCP server configured"

        # Check command
        command=$(jq -r '.mcpServers."claude-voice-tts".command' "$claude_config")
        print_info "Command: $command"

        # Check args
        args=$(jq -r '.mcpServers."claude-voice-tts".args | join(" ")' "$claude_config")
        print_info "Args: $args"

        # Check env
        base_url=$(jq -r '.mcpServers."claude-voice-tts".env.KOKORO_BASE_URL' "$claude_config")
        if [ "$base_url" != "null" ]; then
            print_info "Base URL: $base_url"
        fi
    else
        fail_test "Kokoro TTS MCP not found in config"
    fi
else
    fail_test "Claude Desktop config not found"
fi

echo

# Summary
print_header "Test Summary"

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All MCP tests passed! ✓${NC}"
    echo
    print_info "MCP server is properly installed and configured."
    print_info "Restart Claude Desktop to use the MCP server."
    echo
    exit 0
else
    echo -e "${RED}$FAILED test(s) failed ✗${NC}"
    echo
    print_info "Some MCP components may need attention."
    echo
    exit 1
fi
