# Claude Voice TTS MCP Server

High-quality text-to-speech MCP server using the **Kokoro-82M** model (#1 ranked in TTS Arena) with voice blending support and Claude Desktop integration.

## Features

- **Best-in-Class Quality**: Kokoro-82M outperforms XTTS v2, MetaVoice, Fish Speech in blind tests
- **Fast**: 100-300ms latency with GPU acceleration (35-100x real-time)
- **Voice Blending**: Mix multiple voices with custom ratios (e.g., `af_bella(2)+af_sky(1)`)
- **MCP Integration**: Seamless integration with Claude Desktop/Code
- **GPU Accelerated**: NVIDIA CUDA support with automatic CPU fallback
- **One-Command Install**: Automated installer handles everything

## Quick Start

```bash
# Clone or download this repository
git clone https://github.com/your-username/claude-code-voice-mcp-server.git
cd claude-code-voice-mcp-server

# Run the installer (handles everything automatically)
./install.sh

# Start the service
tts start

# Test it's working
tts test
```

That's it! The MCP server is now available in Claude Desktop.

## Requirements

- **OS**: Linux (Ubuntu, Debian, Fedora, RHEL, Arch, SUSE) or macOS
- **GPU**: NVIDIA GPU with CUDA 12.3+ (recommended, CPU fallback available)
  - Note: macOS does not support NVIDIA GPUs, will use CPU automatically
- **Docker**: Will be installed automatically if missing
- **Disk**: ~4GB for Docker image and models
- **RAM**: 4GB minimum, 8GB recommended

## Installation

The installer (`install.sh`) automatically:

1. Checks system requirements (GPU, Docker, etc.)
2. Installs all dependencies (Docker, NVIDIA Container Toolkit, Python packages)
3. Sets up Python environment with conda/venv
4. Pulls Docker image for Kokoro TTS
5. Creates systemd service for auto-start
6. Installs MCP server and CLI tools
7. Configures Claude Desktop
8. Tests the installation

### Manual Installation (Advanced)

If you prefer manual control:

```bash
# 1. Install dependencies (Debian/Ubuntu)
sudo apt-get update && sudo apt-get install -y docker.io python3 python3-pip

# Or Fedora/RHEL
# sudo dnf install -y docker python3 python3-pip

# Or Arch
# sudo pacman -Sy docker python python-pip

# Or macOS
# brew install docker python

# 2. Install NVIDIA Container Toolkit (Linux with NVIDIA GPU only)
# Debian/Ubuntu:
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://nvidia.github.io/libnvidia-container/stable/deb/\$(ARCH) /" | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker

# Fedora/RHEL:
# curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
# sudo dnf install -y nvidia-container-toolkit
# sudo systemctl restart docker

# 3. Pull Docker image
docker pull ghcr.io/remsky/kokoro-fastapi-gpu:latest  # GPU
# docker pull ghcr.io/remsky/kokoro-fastapi-cpu:latest  # CPU

# 4. Start container
docker run -d --name claude-voice-tts --gpus all -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-gpu:latest  # GPU
# docker run -d --name claude-voice-tts -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-cpu:latest  # CPU

# 5. Install MCP server
pip install uv
uv pip install -e .

# 6. Configure Claude Desktop
# Edit ~/.config/claude/claude_desktop_config.json
# Add claude-voice-tts MCP server configuration (see Configuration section)
```

## Usage

### Service Control

```bash
# Start/stop service
tts start
tts stop
tts restart

# Check status
tts status

# View logs
tts logs           # Last 50 lines
tts logs -f        # Follow logs

# Enable/disable auto-start
tts enable         # Start on login
tts disable        # Don't start on login

# Test service
tts test
```

### Claude Desktop Integration

After installation, restart Claude Desktop. The MCP server automatically provides these tools:

#### `generate_speech`
Generate speech from text with optional voice blending.

**Parameters:**
- `text` (required): Text to convert to speech
- `voice` (optional): Voice name or blended voice (default: `af_bella`)
- `speed` (optional): Speech speed 0.5-2.0 (default: `1.0`)
- `output_format` (optional): Audio format: mp3, wav, opus (default: `mp3`)
- `save_to_file` (optional): Save to file or return base64 (default: `true`)

**Example:**
```
Claude, generate speech saying "Hello, this is a test of voice blending" using a blend of af_bella and af_sky voices.
```

#### `list_voices`
List all available voices and voice blending information.

**Example:**
```
Claude, what voices are available?
```

#### `check_status`
Check if Kokoro TTS service is running and accessible.

**Example:**
```
Claude, check if the TTS service is working.
```

### Direct API Usage

The Kokoro TTS backend exposes an OpenAI-compatible API on port 8880:

```bash
# List voices
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

# Voice blending (2 parts Bella + 1 part Sky)
curl -X POST http://localhost:8880/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "kokoro",
    "input": "Testing voice blending.",
    "voice": "af_bella(2)+af_sky(1)",
    "speed": 1.0
  }' \
  -o blended.mp3

# Play the audio
mpg123 output.mp3  # or ffplay output.mp3
```

## Available Voices

| Voice | Gender | Accent | Description |
|-------|--------|--------|-------------|
| `af_bella` | Female | American | Bella |
| `af_sky` | Female | American | Sky |
| `af_nicole` | Female | American | Nicole |
| `am_adam` | Male | American | Adam |
| `am_michael` | Male | American | Michael |
| `bf_emma` | Female | British | Emma |
| `bf_isabella` | Female | British | Isabella |
| `bm_george` | Male | British | George |
| `bm_lewis` | Male | British | Lewis |

### Voice Blending

Create custom voices by blending multiple voices:

```
# Syntax: voice1(weight1)+voice2(weight2)+...

af_bella(2)+af_sky(1)          # 2 parts Bella, 1 part Sky
am_adam(3)+am_michael(1)       # 3 parts Adam, 1 part Michael
bf_emma(1)+bf_isabella(1)      # Equal mix of Emma and Isabella
```

## Configuration

### Environment Variables

Create a `.env` file in the installation directory (`~/.local/share/claude-code-voice-mcp-server/`):

```bash
KOKORO_BASE_URL=http://localhost:8880
DEFAULT_VOICE=af_bella
DEFAULT_SPEED=1.0
OUTPUT_DIR=~/tts_output
TIMEOUT=30
LOG_LEVEL=INFO
```

### Claude Desktop Configuration

The installer automatically configures Claude Desktop, but you can manually edit `~/.config/claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "claude-voice-tts": {
      "command": "uv",
      "args": [
        "--directory",
        "/home/USERNAME/.local/share/claude-code-voice-mcp-server",
        "run",
        "claude-voice-mcp"
      ],
      "env": {
        "KOKORO_BASE_URL": "http://localhost:8880"
      }
    }
  }
}
```

Replace `USERNAME` with your actual username.

## GPU vs CPU Performance

### GPU (NVIDIA with CUDA 12.3+)
- **Latency**: 100-300ms
- **Speed**: 35-100x real-time
- **VRAM**: ~2-3GB
- **Recommended**: RTX 3060 or better

### CPU
- **Latency**: 1-3.5s
- **Speed**: <1x real-time
- **RAM**: ~4GB
- **Works**: Any modern CPU

The installer automatically detects your hardware and uses the appropriate configuration.

## Coexistence with Other Services

Kokoro TTS uses minimal resources and can run alongside other GPU services:

- **VRAM**: ~2-3GB (RTX 3090 has 24GB total)
- **Example**: Run Kokoro TTS + Whisper STT simultaneously
- **Port**: 8880 (configurable)

## Troubleshooting

### Service won't start

```bash
# Check Docker status
docker ps
systemctl --user status claude-voice-tts

# Check logs
tts logs

# Restart Docker
sudo systemctl restart docker
tts restart
```

### API not responding

```bash
# Test connection
curl http://localhost:8880/v1/audio/voices

# Check if port is in use
netstat -tulpn | grep 8880

# Restart service
tts restart
```

### GPU not detected

```bash
# Check NVIDIA driver
nvidia-smi

# Test NVIDIA Container Toolkit
docker run --rm --gpus all nvidia/cuda:12.3.0-base-ubuntu22.04 nvidia-smi

# Reinstall toolkit
sudo apt-get install --reinstall nvidia-container-toolkit
sudo systemctl restart docker
```

### Claude Desktop not showing MCP tools

1. Check MCP server is configured: `cat ~/.config/claude/claude_desktop_config.json`
2. Restart Claude Desktop completely
3. Check Claude Desktop logs for errors
4. Test MCP server directly: `uv run claude-voice-mcp` (should start without errors)

### Audio files not playing

```bash
# Install audio player
sudo apt-get install mpg123 ffmpeg

# Test playback
mpg123 ~/tts_output/your-file.mp3
ffplay ~/tts_output/your-file.mp3
```

## Development

### Run MCP server in debug mode

```bash
cd ~/.local/share/claude-code-voice-mcp-server
LOG_LEVEL=DEBUG uv run claude-voice-mcp
```

### Run tests

```bash
# Full test suite
pytest tests/

# Specific tests
pytest tests/test_mcp.py -v

# Coverage
pytest --cov=src tests/
```

### Modify and reload

```bash
# Edit MCP server
vim ~/.local/share/claude-code-voice-mcp-server/src/claude_voice_mcp.py

# Restart Claude Desktop to reload MCP server
# Or test directly:
uv run claude-voice-mcp
```

## Architecture

```
┌─────────────────┐
│ Claude Desktop  │
│   (MCP Client)  │
└────────┬────────┘
         │ stdio
         ▼
┌─────────────────┐
│  MCP Server     │
│ (claude_voice_mcp.py) │
└────────┬────────┘
         │ HTTP
         ▼
┌─────────────────┐       ┌──────────────┐
│ Docker Container│◄──────┤   systemd    │
│  Kokoro-FastAPI │       │   service    │
│   (port 8880)   │       └──────────────┘
└────────┬────────┘
         │ GPU
         ▼
┌─────────────────┐
│  Kokoro-82M     │
│  TTS Model      │
│  (~2-3GB VRAM)  │
└─────────────────┘
```

## Performance Benchmarks

| Configuration | Latency | VRAM | Speed |
|--------------|---------|------|-------|
| RTX 4090 GPU | 100ms | 2.5GB | 100x RT |
| RTX 3090 GPU | 150ms | 2.8GB | 70x RT |
| RTX 3060 GPU | 250ms | 3.0GB | 40x RT |
| CPU (i7-12700) | 3.5s | N/A | 0.3x RT |
| CPU (M3 Pro) | 1.0s | N/A | 1.0x RT |

RT = Real-time (1x = same duration as audio length)

## License

MIT License - See LICENSE file for details.

## Credits

- **Kokoro TTS**: [github.com/remsky/Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI)
- **Original Kokoro Model**: [Style-Bert-VITS2](https://github.com/litagin02/Style-Bert-VITS2)
- **MCP Framework**: [FastMCP](https://github.com/jlowin/fastmcp)

## Support

For issues, questions, or contributions:
- GitHub Issues: [your-repo-url/issues]
- Documentation: See CLAUDE.md for developer guidance

## Roadmap

- [ ] Add streaming audio support
- [ ] Support for additional languages (Japanese, Chinese)
- [ ] Voice cloning from audio samples
- [ ] Web UI for voice testing
- [ ] Real-time voice morphing
- [ ] Integration with more MCP clients
