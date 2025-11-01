#!/bin/bash

# API testing script for Kokoro TTS

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

BASE_URL="http://localhost:8880"
OUTPUT_DIR="/tmp/kokoro-api-test-$(date +%s)"
mkdir -p "$OUTPUT_DIR"

FAILED=0

fail_test() {
    print_error "$1"
    FAILED=$((FAILED + 1))
}

print_header "Kokoro TTS API Test Suite"

# Test 1: List voices
print_info "Test 1: List voices endpoint..."
if response=$(curl -s -w "%{http_code}" "$BASE_URL/v1/audio/voices"); then
    http_code="${response: -3}"
    body="${response:0:${#response}-3}"

    if [ "$http_code" = "200" ]; then
        print_success "GET /v1/audio/voices returned 200"

        voice_count=$(echo "$body" | jq '. | length' 2>/dev/null || echo "0")
        if [ "$voice_count" -gt 0 ]; then
            print_success "Found $voice_count voices"
            echo "$body" | jq -r '.[] | "  - \(.name): \(.description)"' 2>/dev/null || echo "$body"
        else
            fail_test "No voices returned"
        fi
    else
        fail_test "Expected 200, got $http_code"
    fi
else
    fail_test "Failed to connect to API"
fi

echo

# Test 2: Generate simple speech
print_info "Test 2: Generate simple speech (af_bella)..."
test_file="$OUTPUT_DIR/test_simple.mp3"

if curl -s -X POST "$BASE_URL/v1/audio/speech" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "kokoro",
        "input": "This is a test of the Kokoro text to speech system.",
        "voice": "af_bella",
        "speed": 1.0,
        "response_format": "mp3"
    }' \
    -o "$test_file" -w "%{http_code}" | grep -q "200"; then

    if [ -f "$test_file" ] && [ -s "$test_file" ]; then
        size=$(du -h "$test_file" | cut -f1)
        print_success "Generated speech file ($size)"
    else
        fail_test "Speech file is empty or missing"
    fi
else
    fail_test "Failed to generate speech"
fi

echo

# Test 3: Voice blending
print_info "Test 3: Generate speech with voice blending..."
test_file="$OUTPUT_DIR/test_blended.mp3"

if curl -s -X POST "$BASE_URL/v1/audio/speech" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "kokoro",
        "input": "This is a test with voice blending.",
        "voice": "af_bella(2)+af_sky(1)",
        "speed": 1.0,
        "response_format": "mp3"
    }' \
    -o "$test_file" -w "%{http_code}" | grep -q "200"; then

    if [ -f "$test_file" ] && [ -s "$test_file" ]; then
        size=$(du -h "$test_file" | cut -f1)
        print_success "Generated blended speech ($size)"
    else
        fail_test "Blended speech file is empty or missing"
    fi
else
    fail_test "Failed to generate blended speech"
fi

echo

# Test 4: Different speeds
print_info "Test 4: Generate speech at different speeds..."

for speed in 0.5 1.0 1.5; do
    test_file="$OUTPUT_DIR/test_speed_${speed}.mp3"

    if curl -s -X POST "$BASE_URL/v1/audio/speech" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"kokoro\",
            \"input\": \"Testing speech at speed $speed\",
            \"voice\": \"af_bella\",
            \"speed\": $speed,
            \"response_format\": \"mp3\"
        }" \
        -o "$test_file" -w "%{http_code}" | grep -q "200"; then

        if [ -f "$test_file" ] && [ -s "$test_file" ]; then
            print_success "Speed $speed: OK"
        else
            fail_test "Speed $speed: Empty file"
        fi
    else
        fail_test "Speed $speed: Request failed"
    fi
done

echo

# Test 5: Different formats
print_info "Test 5: Generate speech in different formats..."

for format in mp3 wav opus; do
    test_file="$OUTPUT_DIR/test_format.$format"

    if curl -s -X POST "$BASE_URL/v1/audio/speech" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"kokoro\",
            \"input\": \"Testing $format format\",
            \"voice\": \"af_bella\",
            \"speed\": 1.0,
            \"response_format\": \"$format\"
        }" \
        -o "$test_file" -w "%{http_code}" | grep -q "200"; then

        if [ -f "$test_file" ] && [ -s "$test_file" ]; then
            print_success "Format $format: OK"
        else
            fail_test "Format $format: Empty file"
        fi
    else
        fail_test "Format $format: Request failed"
    fi
done

echo

# Test 6: Error handling - invalid voice
print_info "Test 6: Error handling (invalid voice)..."

if response=$(curl -s -w "%{http_code}" -X POST "$BASE_URL/v1/audio/speech" \
    -H "Content-Type: application/json" \
    -d '{
        "model": "kokoro",
        "input": "Test",
        "voice": "invalid_voice_name",
        "speed": 1.0
    }' \
    -o /dev/null); then

    http_code="${response: -3}"
    if [ "$http_code" != "200" ]; then
        print_success "Invalid voice correctly rejected (HTTP $http_code)"
    else
        fail_test "Invalid voice accepted (should fail)"
    fi
else
    print_success "Invalid voice correctly rejected"
fi

echo

# Test 7: Long text
print_info "Test 7: Generate speech from long text..."
test_file="$OUTPUT_DIR/test_long.mp3"

long_text="The quick brown fox jumps over the lazy dog. This is a longer piece of text to test the text-to-speech system's ability to handle multiple sentences and maintain natural intonation throughout. The Kokoro model is designed to produce high-quality, natural-sounding speech that rivals human voice actors in many scenarios."

if curl -s -X POST "$BASE_URL/v1/audio/speech" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"kokoro\",
        \"input\": \"$long_text\",
        \"voice\": \"af_bella\",
        \"speed\": 1.0,
        \"response_format\": \"mp3\"
    }" \
    -o "$test_file" -w "%{http_code}" | grep -q "200"; then

    if [ -f "$test_file" ] && [ -s "$test_file" ]; then
        size=$(du -h "$test_file" | cut -f1)
        print_success "Long text generated ($size)"
    else
        fail_test "Long text file is empty or missing"
    fi
else
    fail_test "Failed to generate long text speech"
fi

echo

# Summary
print_header "Test Summary"

print_info "Test files saved to: $OUTPUT_DIR"
echo

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All API tests passed! ✓${NC}"
    echo
    print_info "Generated test files:"
    ls -lh "$OUTPUT_DIR"
    echo

    # Automatically play test audio
    if command -v ffplay &> /dev/null || command -v mpg123 &> /dev/null; then
        if read -p "Play test audio? [Y/n]: " -n 1 -r; then
            echo
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                print_info "Playing test audio..."
                if command -v ffplay &> /dev/null; then
                    ffplay -nodisp -autoexit "$OUTPUT_DIR/test_simple.mp3" 2>/dev/null
                elif command -v mpg123 &> /dev/null; then
                    mpg123 -q "$OUTPUT_DIR/test_simple.mp3"
                fi
                print_success "Playback complete!"
            fi
        fi
    else
        print_info "Install ffplay or mpg123 to play audio"
        print_info "Play manually: ffplay $OUTPUT_DIR/test_simple.mp3"
    fi

    echo
    exit 0
else
    echo -e "${RED}$FAILED test(s) failed ✗${NC}"
    echo
    print_info "Check the errors above for details."
    echo
    exit 1
fi
