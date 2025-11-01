# Contributing to Kokoro TTS MCP Server

Thank you for your interest in contributing! This project aims to provide a high-quality, easy-to-use TTS system with Claude MCP integration.

## Getting Started

### Prerequisites

- Python 3.10+
- Docker and Docker Compose
- NVIDIA GPU (optional, for GPU acceleration)
- NVIDIA Container Toolkit (for GPU support)

### Development Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/claude-code-voice-mcp-server.git
cd claude-code-voice-mcp-server
```

2. Install dependencies:
```bash
uv pip install -e ".[dev]"
```

3. Run tests:
```bash
pytest tests/
```

## How to Contribute

### Reporting Bugs

- Use the GitHub issue tracker
- Include system information (OS, Docker version, GPU model if applicable)
- Provide reproduction steps
- Include relevant logs from `tts logs`

### Suggesting Features

- Open an issue with the `enhancement` label
- Describe the use case and expected behavior
- Explain why this feature would benefit users

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature-name`
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass: `pytest`
6. Run linter: `ruff check .`
7. Format code: `ruff format .`
8. Commit with descriptive messages
9. Push to your fork
10. Submit a pull request

### Code Style

- Follow PEP 8 guidelines
- Use type hints for function signatures
- Maximum line length: 100 characters
- Run `ruff check .` and `ruff format .` before committing

### Testing

- Add tests for all new features
- Maintain or improve code coverage
- Test both CPU and GPU paths where applicable
- Include integration tests for installer changes

### Documentation

- Update README.md for user-facing changes
- Update CLAUDE.md for developer-facing changes
- Add docstrings for new functions/classes
- Update installation guide if dependencies change

## Project Structure

```
├── src/              # MCP server source code
├── bin/              # CLI scripts (tts, tts-voice-mode, tts-auto-speak)
├── config/           # Configuration templates
├── tests/            # Test suite
├── install.sh        # Main installer script
└── docker-compose.yml # Docker Compose configuration
```

## Commit Message Guidelines

- Use present tense: "Add feature" not "Added feature"
- Use imperative mood: "Fix bug" not "Fixes bug"
- First line max 72 characters
- Reference issues: "Fix #123: Description"

Examples:
```
Add voice blending support for multiple voices
Fix GPU detection on NVIDIA Container Toolkit 1.14+
Update installer to support Fedora and Arch Linux
```

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Questions?

- Open a discussion on GitHub
- Check existing issues and documentation
- Read CLAUDE.md for technical architecture details

Thank you for contributing!
