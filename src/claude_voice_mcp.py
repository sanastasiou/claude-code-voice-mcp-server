#!/usr/bin/env python3
"""
Claude Voice TTS MCP Server

MCP server providing text-to-speech capabilities using Kokoro-82M model.
Supports voice blending and high-quality speech generation.
"""

import base64
import logging
import os
from pathlib import Path
from typing import Any

import httpx
from dotenv import load_dotenv
from fastmcp import FastMCP
from pydantic import BaseModel, Field

# Load environment variables
load_dotenv()

# Configuration
KOKORO_BASE_URL = os.getenv("KOKORO_BASE_URL", "http://localhost:8880")
DEFAULT_VOICE = os.getenv("DEFAULT_VOICE", "af_bella")
DEFAULT_SPEED = float(os.getenv("DEFAULT_SPEED", "1.0"))
OUTPUT_DIR = Path(os.getenv("OUTPUT_DIR", str(Path.home() / "tts_output")))
TIMEOUT = int(os.getenv("TIMEOUT", "30"))

# Ensure output directory exists
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Initialize MCP server
mcp = FastMCP("claude-voice-tts")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger("claude-voice-mcp")


class GenerateSpeechInput(BaseModel):
    """Input schema for generate_speech tool"""

    text: str = Field(..., description="Text to convert to speech")
    voice: str = Field(
        default=DEFAULT_VOICE,
        description=(
            "Voice to use. Single voice (e.g., 'af_bella') or blended "
            "(e.g., 'af_bella(2)+af_sky(1)'). Available: af_bella, af_sky, "
            "af_nicole, am_adam, am_michael, bf_emma, bf_isabella, bm_george, bm_lewis"
        ),
    )
    speed: float = Field(
        default=DEFAULT_SPEED,
        ge=0.5,
        le=2.0,
        description="Speech speed multiplier (0.5-2.0)",
    )
    output_format: str = Field(
        default="mp3",
        description="Audio format: mp3, wav, or opus",
    )
    save_to_file: bool = Field(
        default=True,
        description="Whether to save audio to file (returns path) or return base64 data",
    )


class ListVoicesOutput(BaseModel):
    """Output schema for list_voices tool"""

    voices: list[dict[str, str]]
    blending_info: str


@mcp.tool()
async def generate_speech(
    text: str,
    voice: str = DEFAULT_VOICE,
    speed: float = DEFAULT_SPEED,
    output_format: str = "mp3",
    save_to_file: bool = True,
) -> dict[str, Any]:
    """
    Generate speech from text using Kokoro TTS.

    Args:
        text: Text to convert to speech
        voice: Voice name or blended voice (e.g., 'af_bella(2)+af_sky(1)')
        speed: Speech speed multiplier (0.5-2.0)
        output_format: Audio format (mp3, wav, opus)
        save_to_file: Save to file (returns path) or return base64 data

    Returns:
        Dictionary with either 'file_path' or 'audio_data' (base64) and metadata
    """
    logger.info(f"Generating speech: voice={voice}, speed={speed}, format={output_format}")

    try:
        # Prepare request payload (OpenAI-compatible format)
        payload = {
            "model": "kokoro",
            "input": text,
            "voice": voice,
            "speed": speed,
            "response_format": output_format,
        }

        # Call Kokoro API
        async with httpx.AsyncClient(timeout=TIMEOUT) as client:
            response = await client.post(
                f"{KOKORO_BASE_URL}/v1/audio/speech",
                json=payload,
            )
            response.raise_for_status()
            audio_data = response.content

        logger.info(f"Generated {len(audio_data)} bytes of audio")

        if save_to_file:
            # Generate filename
            safe_text = "".join(c for c in text[:30] if c.isalnum() or c in (" ", "_"))
            safe_text = safe_text.replace(" ", "_")
            filename = f"{safe_text}_{voice.replace('+', '_')}.{output_format}"
            file_path = OUTPUT_DIR / filename

            # Save audio file
            file_path.write_bytes(audio_data)
            logger.info(f"Saved audio to {file_path}")

            return {
                "status": "success",
                "file_path": str(file_path),
                "size_bytes": len(audio_data),
                "voice": voice,
                "speed": speed,
                "format": output_format,
                "text_preview": text[:100] + ("..." if len(text) > 100 else ""),
            }
        else:
            # Return base64-encoded audio
            audio_base64 = base64.b64encode(audio_data).decode("utf-8")
            return {
                "status": "success",
                "audio_data": audio_base64,
                "size_bytes": len(audio_data),
                "voice": voice,
                "speed": speed,
                "format": output_format,
                "text_preview": text[:100] + ("..." if len(text) > 100 else ""),
            }

    except httpx.HTTPStatusError as e:
        logger.error(f"HTTP error: {e.response.status_code} - {e.response.text}")
        return {
            "status": "error",
            "error": f"HTTP {e.response.status_code}: {e.response.text}",
        }
    except httpx.TimeoutException:
        logger.error(f"Request timed out after {TIMEOUT}s")
        return {
            "status": "error",
            "error": f"Request timed out after {TIMEOUT}s",
        }
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}", exc_info=True)
        return {
            "status": "error",
            "error": str(e),
        }


@mcp.tool()
async def list_voices() -> dict[str, Any]:
    """
    List available voices and voice blending information.

    Returns:
        Dictionary with available voices and blending instructions
    """
    logger.info("Listing available voices")

    try:
        # Try to fetch voices from API
        async with httpx.AsyncClient(timeout=5) as client:
            response = await client.get(f"{KOKORO_BASE_URL}/v1/audio/voices")
            if response.status_code == 200:
                api_voices = response.json()
                logger.info(f"Retrieved {len(api_voices)} voices from API")
                return {
                    "status": "success",
                    "voices": api_voices,
                    "blending_info": (
                        "Blend voices using syntax: 'voice1(weight1)+voice2(weight2)'. "
                        "Example: 'af_bella(2)+af_sky(1)' creates a voice that is "
                        "2 parts af_bella and 1 part af_sky."
                    ),
                }
    except Exception as e:
        logger.warning(f"Could not fetch voices from API: {e}")

    # Fallback to hardcoded voice list
    default_voices = [
        {"name": "af_bella", "gender": "female", "language": "en", "description": "Bella (American Female)"},
        {"name": "af_sky", "gender": "female", "language": "en", "description": "Sky (American Female)"},
        {"name": "af_nicole", "gender": "female", "language": "en", "description": "Nicole (American Female)"},
        {"name": "am_adam", "gender": "male", "language": "en", "description": "Adam (American Male)"},
        {"name": "am_michael", "gender": "male", "language": "en", "description": "Michael (American Male)"},
        {"name": "bf_emma", "gender": "female", "language": "en", "description": "Emma (British Female)"},
        {"name": "bf_isabella", "gender": "female", "language": "en", "description": "Isabella (British Female)"},
        {"name": "bm_george", "gender": "male", "language": "en", "description": "George (British Male)"},
        {"name": "bm_lewis", "gender": "male", "language": "en", "description": "Lewis (British Male)"},
    ]

    return {
        "status": "success",
        "voices": default_voices,
        "blending_info": (
            "Blend voices using syntax: 'voice1(weight1)+voice2(weight2)'. "
            "Example: 'af_bella(2)+af_sky(1)' creates a voice that is "
            "2 parts af_bella and 1 part af_sky."
        ),
        "note": "Using default voice list (API not available)",
    }


@mcp.tool()
async def check_status() -> dict[str, Any]:
    """
    Check if Kokoro TTS service is running and accessible.

    Returns:
        Service status and connection information
    """
    logger.info("Checking Kokoro TTS service status")

    try:
        async with httpx.AsyncClient(timeout=5) as client:
            # Try to fetch voices as a health check
            response = await client.get(f"{KOKORO_BASE_URL}/v1/audio/voices")
            response.raise_for_status()

            return {
                "status": "success",
                "service": "online",
                "base_url": KOKORO_BASE_URL,
                "message": "Kokoro TTS service is running and accessible",
            }
    except httpx.ConnectError:
        return {
            "status": "error",
            "service": "offline",
            "base_url": KOKORO_BASE_URL,
            "message": (
                "Cannot connect to Kokoro TTS service. "
                "Ensure Docker container is running: 'systemctl --user status claude-voice-tts'"
            ),
        }
    except Exception as e:
        return {
            "status": "error",
            "service": "unknown",
            "base_url": KOKORO_BASE_URL,
            "message": f"Error checking service: {str(e)}",
        }


def main():
    """Entry point for the MCP server"""
    logger.info(f"Starting Claude Voice TTS MCP server (base URL: {KOKORO_BASE_URL})")
    logger.info(f"Output directory: {OUTPUT_DIR}")
    logger.info(f"Default voice: {DEFAULT_VOICE}, speed: {DEFAULT_SPEED}")

    # Run the server
    mcp.run()


if __name__ == "__main__":
    main()
