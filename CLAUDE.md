# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Kokoro TTS MCP Server: High-quality text-to-speech system using Kokoro-82M model (#1 ranked in TTS Arena) with Claude MCP integration. Supports voice blending, GPU acceleration, and provides ~100-300ms latency.

## Architecture

### Components

1. **Kokoro TTS Backend** (Docker container)
   - Image: `ghcr.io/remsky/kokoro-fastapi-gpu:latest`
   - Port: 8880
   - Managed by systemd user service: `claude-voice-tts.service`
   - OpenAI-compatible API: `/v1/audio/speech`

2. **MCP Server** (`src/claude_voice_mcp.py`)
   - FastMCP-based Python server
   - Calls Kokoro backend HTTP API
   - Exposes tools: `generate_speech`, `list_voices`, `check_status`
   - Launched by Claude Desktop via stdio

3. **Control CLI** (`bin/tts`)
   - Service management: start/stop/status/logs
   - Voice mode control for automatic speech
   - Similar pattern to dictation-service

4. **Voice Mode System** (`bin/tts-voice-mode`, `bin/tts-auto-speak`)
   - Toggle automatic voice generation for Claude responses
   - State managed via `~/.config/tts-service/voice_mode`
   - Auto-plays speech when voice mode is enabled

### Directory Structure

```
.
├── install.sh                    # Main installer
├── pyproject.toml                # Python dependencies
├── src/
│   └── claude_voice_mcp.py             # MCP server implementation
├── bin/
│   ├── tts                       # Control CLI script
│   ├── tts-voice-mode            # Voice mode toggle script
│   └── tts-auto-speak            # Auto-speak helper script
├── config/
│   ├── systemd/
│   │   └── claude-voice-tts.service    # Systemd service for Docker
│   └── tts-service/
│       └── config.json.default    # Default configuration
├── docker-compose.yml            # Docker Compose (alternative)
└── .env.example                  # Environment config template
```

### Installation Locations

```
~/.local/share/claude-code-voice-mcp-server/       # MCP server + Python env
~/.local/bin/tts                     # Control CLI
~/.local/bin/tts-voice-mode          # Voice mode toggle
~/.local/bin/tts-auto-speak          # Auto-speak helper
~/.config/tts-service/config.json    # Configuration
~/.config/tts-service/voice_mode     # Voice mode state (created on enable)
~/.config/systemd/user/              # Systemd service
~/.config/claude/                    # Claude Desktop & Code config
~/tts_output/                        # Generated audio files
```

## Development Commands

### Installation

```bash
# Full automated installation
./install.sh

# Manual installation with Docker Compose
docker-compose up -d
```

### Service Control

```bash
# Start/stop service
tts start
tts stop
tts restart

# Check status
tts status
tts logs
tts logs -f          # Follow logs

# Enable/disable auto-start
tts enable
tts disable

# Test installation
tts test
```

### Voice Mode (Automatic Speech)

Voice mode automatically converts Claude's responses to speech:

```bash
# Enable voice mode (default voice: af_bella)
tts voice-mode on

# Disable voice mode
tts voice-mode off

# Change voice
tts voice-mode voice am_adam      # Use male voice
tts voice-mode voice af_sky       # Use different female voice

# Check status
tts voice-mode status

# Manual testing
echo "This will be spoken" | tts-auto-speak
tts-auto-speak "Direct speech test"
```

**How It Works:**
- When enabled, creates state file: `~/.config/tts-service/voice_mode`
- Claude Code can check this file and automatically call `tts-auto-speak`
- Speech is generated and played through speakers automatically
- No need to type "Generate speech saying..." anymore

**Available Voices:**
- Female: af_bella, af_sky, af_nicole, af_sarah, af_nova, bf_emma, bf_lily, af_jessica, af_river, af_heart
- Male: am_adam, am_michael, am_liam, am_eric, bm_george, bm_lewis, am_onyx, am_echo, bm_daniel, am_fenrir

### Direct API Testing

```bash
# List available voices
curl http://localhost:8880/v1/audio/voices

# Generate speech
curl -X POST http://localhost:8880/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kokoro",
    "input": "Hello, this is a test.",
    "voice": "af_bella",
    "speed": 1.0,
    "response_format": "mp3"
  }' \
  -o output.mp3

# Voice blending
curl -X POST http://localhost:8880/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kokoro",
    "input": "Testing voice blending.",
    "voice": "af_bella(2)+af_sky(1)",
    "speed": 1.0
  }' \
  -o blended.mp3
```

### Development

```bash
# Install in development mode
cd ~/.local/share/claude-code-voice-mcp-server
uv pip install -e .

# Run tests
pytest tests/

# Run MCP server directly (for debugging)
uv run claude-voice-mcp

# Check logs
journalctl --user -u claude-voice-tts.service -f
```

### Claude Desktop Integration

MCP server auto-configured during installation at:
- Config: `~/.config/claude/claude_desktop_config.json`
- Restart Claude Desktop after installation
- Available tools: `generate_speech`, `list_voices`, `check_status`

### Voice Blending Syntax

```python
# Single voice
"voice": "af_bella"

# Blended (2 parts bella + 1 part sky)
"voice": "af_bella(2)+af_sky(1)"

# Available voices:
# af_bella, af_sky, af_nicole        # American Female
# am_adam, am_michael                # American Male
# bf_emma, bf_isabella               # British Female
# bm_george, bm_lewis                # British Male
```

## GPU Considerations

### VRAM Usage
- Kokoro-82M: ~2-3GB VRAM (FP16)
- Can coexist with other services on RTX 3090 (24GB total)
- Example: Kokoro (3GB) + Whisper STT (3GB) = 6GB / 24GB used

### CPU Fallback
- Installer auto-detects GPU availability
- Uses CPU image if no GPU: `ghcr.io/remsky/kokoro-fastapi-cpu:latest`
- Performance: ~1-3.5s latency (vs 100-300ms on GPU)

## Configuration

### Environment Variables (.env)

```bash
KOKORO_BASE_URL=http://localhost:8880
DEFAULT_VOICE=af_bella
DEFAULT_SPEED=1.0
OUTPUT_DIR=~/tts_output
TIMEOUT=30
LOG_LEVEL=INFO
```

### Runtime Config (~/.config/tts-service/config.json)

```json
{
  "kokoro_base_url": "http://localhost:8880",
  "default_voice": "af_bella",
  "default_speed": 1.0,
  "output_dir": "~/tts_output",
  "timeout": 30
}
```

## Troubleshooting

### Service won't start
```bash
# Check Docker
docker ps
systemctl --user status claude-voice-tts

# Check logs
tts logs

# Restart Docker daemon
sudo systemctl restart docker
```

### API not responding
```bash
# Test connection
curl http://localhost:8880/v1/audio/voices

# Check port binding
netstat -tulpn | grep 8880

# Restart service
tts restart
```

### GPU not detected
```bash
# Check NVIDIA driver
nvidia-smi

# Check NVIDIA Container Toolkit
docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi

# Reinstall toolkit if needed
sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

## Testing

Run test scripts:
```bash
# Full installation test
./tests/test_installation.sh

# API test
./tests/test_api.sh

# MCP server test
./tests/test_mcp.sh
```
