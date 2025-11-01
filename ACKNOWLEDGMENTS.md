# Acknowledgments

This project builds upon excellent open-source software and models. We are grateful to the following projects and their contributors:

## Core Dependencies

### Kokoro-82M TTS Model
- **Project**: [hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M)
- **License**: Apache 2.0
- **Description**: High-quality, efficient text-to-speech model with 82M parameters, trained exclusively on permissive/non-copyrighted audio data
- **Creator**: hexgrad

### Kokoro-FastAPI
- **Project**: [remsky/Kokoro-FastAPI](https://github.com/remsky/Kokoro-FastAPI)
- **License**: Apache 2.0 (wrapper) + MIT (StyleTTS2 inference code)
- **Description**: Dockerized FastAPI wrapper for Kokoro-82M with GPU/CPU support
- **Creator**: remsky

### FastMCP
- **Project**: [jlowin/fastmcp](https://github.com/jlowin/fastmcp)
- **License**: Apache 2.0
- **Description**: Fast, Pythonic way to build MCP servers and clients
- **Creator**: Jeremiah Lowin

## Python Dependencies

### Runtime Dependencies
- **httpx** - BSD-3-Clause - Modern HTTP client
- **pydantic** - MIT - Data validation using Python type hints
- **python-dotenv** - BSD-3-Clause - Environment variable management

### Development Dependencies
- **pytest** - MIT - Testing framework
- **pytest-asyncio** - Apache 2.0 - Async test support
- **pytest-httpx** - MIT - HTTP request mocking
- **ruff** - MIT - Fast Python linter and formatter
- **hatchling** - MIT - Build backend

## System Dependencies

### Docker & Container Runtime
- **Docker** - Apache 2.0 - Container runtime
- **NVIDIA Container Toolkit** - Apache 2.0 - GPU support for containers

### Audio Players
- **ffmpeg** - LGPL 2.1+ / GPL 2+ - Multimedia framework
- **mpg123** - LGPL 2.1 - MPEG audio player

## Model Context Protocol (MCP)
- **Anthropic MCP** - MIT - Model Context Protocol specification
- **Claude Desktop** - Integration point for MCP servers

## Special Thanks

- **hexgrad** for creating and releasing Kokoro-82M under a permissive license
- **remsky** for the excellent FastAPI wrapper with Docker support
- **Jeremiah Lowin** for FastMCP, making MCP server development delightful
- **Anthropic** for Claude and the Model Context Protocol
- The open-source community for all the amazing tools this project builds upon

## License Compatibility

All dependencies use permissive open-source licenses (MIT, Apache 2.0, BSD-3-Clause, LGPL 2.1+) that are compatible with this project's MIT license, allowing free use in both commercial and non-commercial projects.

## Training Data Ethics

Kokoro-82M was trained exclusively on permissive/non-copyrighted audio data and IPA phoneme labels, ensuring ethical use and redistribution.
