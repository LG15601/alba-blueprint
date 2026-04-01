---
name: simulate
description: "Run MiroFish social simulation to test public reaction before strategic decisions. Use when evaluating announcements, PR, product launches, or policy changes."
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - WebFetch
  - Agent
---

# Strategic Simulation (MiroFish)

Simulate public reaction to a document/announcement using 100+ AI personas.

## Prerequisites
- MiroFish-Offline running: `docker compose up -d` in ~/Projects/MiroFish-Offline
- Ollama with qwen2.5:14b model loaded

## Workflow

### 1. Prepare Document
Get or write the document to test (press release, announcement, policy change).
Save to /tmp/mirofish-input.md

### 2. Start Simulation
```bash
# Check MiroFish is running
curl -s http://localhost:3000 > /dev/null && echo "MiroFish OK" || echo "MiroFish DOWN"
curl -s http://localhost:5001/health > /dev/null && echo "API OK" || echo "API DOWN"
```

### 3. Upload & Configure
Upload the document via the MiroFish web UI or API:
```bash
curl -X POST http://localhost:5001/api/upload \
  -F "file=@/tmp/mirofish-input.md"
```

### 4. Run Pipeline
1. Build knowledge graph (extract entities and relationships)
2. Generate personas (100+ with diverse demographics, opinions, influence levels)
3. Run simulation (social media interactions over simulated hours)
4. Generate report (sentiment analysis, key arguments, influence dynamics)

### 5. Analyze Results
- Overall sentiment: positive / negative / mixed
- Key arguments for and against
- Which demographics support/oppose
- Potential backlash vectors
- Influencer dynamics
- Recommendations for messaging adjustments

### 6. Present to Ludovic
Format findings as a concise decision brief:
- GO / ADJUST / ABORT recommendation
- Top 3 risks identified
- Suggested messaging changes
- Confidence level

## Rules
- Always run simulation BEFORE publishing anything
- Present both positive and negative findings honestly
- Include confidence level based on persona diversity
- If MiroFish is down, offer manual analysis as fallback
