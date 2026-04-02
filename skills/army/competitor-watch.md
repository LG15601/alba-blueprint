---
name: competitor-watch
description: |
  Monitor AI agent competitors in France and globally. Track pricing changes,
  product launches, funding rounds, hiring, and strategic moves. Alert on
  important developments. Use when asked about "competitors", "concurrence",
  "veille concurrentielle", or on weekly cron.
version: 1.0.0
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - WebSearch
  - WebFetch
  - Glob
---

# Competitor Watch -- Competitive Intelligence

Systematic monitoring of AI agent competitors in France and globally.
Tracks product launches, pricing changes, funding, hiring, and strategic moves.

## Arguments
- `/competitor-watch` -- full weekly scan
- `/competitor-watch [competitor]` -- deep dive on specific competitor
- `/competitor-watch alert` -- check for breaking competitor news
- `/competitor-watch compare [competitor]` -- feature/pricing comparison

## Competitor Roster

### Tier 1: Direct Competitors (France, AI agents for PME/ETI)
Monitor weekly with deep analysis:

| Competitor      | Focus              | Why We Watch                        |
|-----------------|--------------------|-------------------------------------|
| Dust.tt         | AI assistants      | YC-backed, French, enterprise focus |
| Mistral AI      | LLM platform       | French champion, platform play      |
| LightOn         | Enterprise AI      | French, B2B, similar target market  |
| Hugging Face    | ML platform        | French unicorn, ecosystem influence  |
| Nabla           | Healthcare AI      | French, vertical AI approach        |

### Tier 2: Indirect Competitors (France, adjacent services)
Monitor bi-weekly:

| Competitor      | Focus              | Overlap                             |
|-----------------|--------------------|-------------------------------------|
| Automation ESN  | Consulting + dev   | Same clients, different approach    |
| No-code agencies| Bubble/Zapier      | Simpler use cases, lower price      |
| Big 4 digital   | Accenture/Cap etc  | Enterprise overlap, way more expensive |

### Tier 3: Global AI Agent Players
Monitor monthly for trends:

| Competitor      | Focus              | Why                                 |
|-----------------|--------------------|-------------------------------------|
| Anthropic       | Claude/Agents      | Our technology provider             |
| OpenAI          | ChatGPT/Agents     | Market leader, sets expectations    |
| Cognition (Devin)| AI software eng   | Agent archetype, media attention    |
| Relevance AI    | AI agents platform | Platform approach                   |
| CrewAI          | Multi-agent        | Open source, developer mindshare    |

## Step 1: Automated Scanning

### 1a. News Search
For each Tier 1 competitor:
```
WebSearch: "[competitor name] 2026" OR "[competitor] levee de fonds" OR "[competitor] lancement"
WebSearch: "[competitor name] pricing" OR "[competitor] new feature" OR "[competitor] partnership"
```

### 1b. Social Media Signals
```
WebSearch: site:linkedin.com "[competitor]" "rejoint" OR "recrute" OR "lance"
WebSearch: site:twitter.com "[competitor]" announcement OR launch
```

### 1c. Funding / M&A
```
WebSearch: "[competitor]" "serie" OR "seed" OR "leve" OR "acquisition" site:techcrunch.com OR site:maddyness.com OR site:frenchweb.fr
```

### 1d. Product Changes
For competitors with public products:
```
WebSearch: "[competitor]" changelog OR "what's new" OR "mise a jour"
```

Check their website for pricing page changes:
```
WebFetch: [competitor pricing URL] -- extract current pricing tiers
```

### 1e. Hiring Signals
```
WebSearch: site:welcometothejungle.com "[competitor]"
WebSearch: site:linkedin.com/jobs "[competitor]"
```

What they're hiring for reveals strategy:
- Sales team expansion = go-to-market push
- ML engineers = product investment
- Enterprise AE = upmarket move
- Vertical specialists = niche strategy

## Step 2: Analyze Findings

### Impact Assessment
For each finding, evaluate:

| Dimension        | Question                                    | Score 1-5 |
|------------------|---------------------------------------------|-----------|
| Threat level     | Does this directly affect our market?       | ...       |
| Timing           | Is this imminent or 6+ months out?          | ...       |
| Response needed  | Do we need to react?                        | ...       |
| Opportunity      | Does this create an opening for us?         | ...       |

### Classification
- **CRITICAL**: Direct threat to current clients or pipeline (respond this week)
- **IMPORTANT**: Strategic move that shifts the market (analyze and plan)
- **NOTABLE**: Interesting development worth tracking (log and monitor)
- **NOISE**: Press release theater, no substance (archive)

## Step 3: Feature/Pricing Comparison

Maintain a living comparison matrix:

```json
{
  "last_updated": "2026-04-01",
  "competitors": {
    "dust.tt": {
      "pricing": {
        "entry": "29 EUR/user/month",
        "pro": "89 EUR/user/month",
        "enterprise": "custom"
      },
      "key_features": ["Assistants", "Data connectors", "Custom apps"],
      "target_market": "Enterprise, 100+ employees",
      "strengths": ["YC network", "Product polish", "Developer community"],
      "weaknesses": ["Self-serve focus", "Less hands-on", "No French PME focus"],
      "recent_moves": []
    }
  }
}
```

```bash
mkdir -p ~/.alba/competitive
# Save/update comparison matrix
echo '[matrix]' > ~/.alba/competitive/comparison-matrix.json
```

## Step 4: Strategic Implications

For each CRITICAL or IMPORTANT finding, generate:

### Implication Analysis
```
FINDING: [what happened]
COMPETITOR: [who]
IMPACT SUR ORCHESTRA:
- [direct impact on our business]
- [impact on our positioning]
- [impact on our clients]

REPONSE SUGGEREE:
- Court terme (cette semaine): [action]
- Moyen terme (ce mois): [action]
- Long terme (ce trimestre): [action]

OPPORTUNITE CACHEE:
- [silver lining or opening this creates for us]
```

## Step 5: Output

### Weekly Report
```bash
mkdir -p ~/.alba/competitive/reports
echo '[report]' > ~/.alba/competitive/reports/YYYY-MM-DD-weekly.md
```

### Telegram Summary (French)
```
VEILLE CONCURRENTIELLE -- Semaine du [DATE]

ALERTES CRITIQUES: [N]
[If any: brief description of critical findings]

MOUVEMENTS CLES:
- [Competitor]: [action] -> Impact: [assessment]
- [Competitor]: [action] -> Impact: [assessment]

FINANCEMENTS:
- [Any funding announcements]

RECRUTEMENTS NOTABLES:
- [Competitor] recrute [X roles] -> Signal: [interpretation]

POSITIONNEMENT ORCHESTRA:
- Forces relatives: [what we do better]
- Points de vigilance: [where we're exposed]
- Opportunite de la semaine: [actionable opportunity]

Rapport complet: [file path]
```

## Step 6: Update Positioning

If competitor moves suggest we need to adjust:
- Update pitch deck talking points
- Adjust prospect-hunt targeting if market shifts
- Flag for Ludovic if pricing strategy needs review
- Update battle cards for sales conversations

## Orchestra Rules
- Competitive intelligence is strictly internal. Never share externally
- Never disparage competitors publicly (LinkedIn, website, client conversations)
- In client conversations: position on our strengths, not competitor weaknesses
- All data from public sources only (no industrial espionage, no fake accounts)
- If we discover a vulnerability in a competitor's product: do NOT exploit or disclose
- RGPD applies to competitor employee data too: only public professional profiles
- French sources preferred for France market analysis
- Global analysis in English for broader context
- Always verify funding/pricing claims from at least 2 sources before alerting
- Distinguish between press releases (often exaggerated) and actual product evidence
