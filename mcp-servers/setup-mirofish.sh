#!/bin/bash
# Setup MiroFish-Offline for strategic decision simulation

set -e

PROJECTS_DIR="$HOME/Projects"
mkdir -p "$PROJECTS_DIR"

echo "=== Setting up MiroFish-Offline ==="

# Check Docker
if ! command -v docker &>/dev/null; then
    echo "Docker is required. Install Docker Desktop for Mac."
    exit 1
fi

# Clone
cd "$PROJECTS_DIR"
if [ ! -d "MiroFish-Offline" ]; then
    git clone https://github.com/nikmcfly/MiroFish-Offline.git
else
    echo "MiroFish already cloned, updating..."
    cd MiroFish-Offline && git pull && cd ..
fi

cd MiroFish-Offline

# Setup env
if [ ! -f .env ]; then
    cp .env.example .env
    echo "Created .env from example"
fi

# Remove NVIDIA GPU reservation for Apple Silicon
if grep -q "nvidia" docker-compose.yml 2>/dev/null; then
    echo "NOTE: You may need to remove/comment NVIDIA GPU reservation"
    echo "from docker-compose.yml for Apple Silicon (M1/M2/M3/M4)"
fi

# Start
echo "Starting MiroFish containers..."
docker compose up -d

# Pull models
echo "Pulling Ollama models (this may take a while)..."
docker exec mirofish-ollama ollama pull qwen2.5:14b 2>/dev/null || \
    echo "Model pull failed — try manually: docker exec mirofish-ollama ollama pull qwen2.5:14b"
docker exec mirofish-ollama ollama pull nomic-embed-text 2>/dev/null || \
    echo "Embedding model pull failed"

echo ""
echo "MiroFish-Offline setup complete."
echo "Access UI: http://localhost:3000"
echo "API: http://localhost:5001"
echo ""
echo "For 16GB Mac M4: Use qwen2.5:14b (recommended)"
echo "For 24GB+ Mac: Use qwen2.5:32b for better quality"
