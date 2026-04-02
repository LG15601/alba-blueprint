---
name: pitch-deck
description: |
  Generate and update client presentations, proposals, and pitch decks.
  Creates tailored content based on the prospect/client's sector, pain points,
  and stage in the pipeline. Use when asked to "create proposal", "pitch deck",
  "presentation client", "proposition commerciale", or before sales meetings.
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
  - Grep
---

# Pitch Deck -- Client Presentation Generator

Creates tailored presentations, proposals, and pitch decks for Orchestra
Intelligence's sales process. Adapts content to the prospect's sector,
size, pain points, and stage in the pipeline.

## Arguments
- `/pitch-deck [company]` -- create proposal for specific prospect
- `/pitch-deck template [type]` -- generate template (intro, proposal, case-study)
- `/pitch-deck update [file]` -- update existing presentation with latest data
- `/pitch-deck slides [topic]` -- generate specific slide content

## Presentation Types

### 1. Introduction Deck (first meeting)
- 8-12 slides
- Focus: who we are, what we do, relevant case studies
- Goal: establish credibility, understand their needs

### 2. Proposal (post-qualification)
- 15-20 slides
- Focus: their problem, our solution, approach, timeline, pricing
- Goal: win the project

### 3. Case Study Presentation
- 5-8 slides
- Focus: similar client story, problem-solution-result
- Goal: build trust through proof

### 4. Quarterly Business Review (existing client)
- 10-15 slides
- Focus: what we delivered, metrics, next quarter plan
- Goal: retain and expand

## Step 1: Gather Context

### 1a. Lead/Client Data
```bash
# From qualification or CRM
cat ~/.alba/leads/*[company-slug]*.json 2>/dev/null
cat /Users/alba/AZW/alba-blueprint/data/clients.json 2>/dev/null
cat /Users/alba/AZW/alba-blueprint/data/pipeline.json 2>/dev/null
```

### 1b. Company Research
```
WebSearch: "[company name]" annual report OR rapport annuel
WebSearch: "[company name]" challenges OR strategy OR digital
WebFetch: [company website] -- extract positioning, key messages, tech stack
```

### 1c. Sector Intelligence
```bash
# Load sector-specific data
cat ~/.alba/competitive/sector-[sector].json 2>/dev/null
```

Research sector pain points, benchmarks, and trends.

### 1d. Similar Case Studies
```bash
# Find similar clients in our portfolio
cat /Users/alba/AZW/alba-blueprint/data/clients.json 2>/dev/null
# Filter by similar sector, size, or pain point
```

## Step 2: Build Slide Content

### Introduction Deck Structure

**Slide 1: Title**
- Orchestra Intelligence
- Subtitle: [Relevant value proposition for their sector]
- Date and meeting context

**Slide 2: Le Probleme**
- Specific to their sector/situation
- 1 stat that quantifies the pain
- Make them nod ("yes, that's exactly our problem")

**Slide 3: Pourquoi Ca Persiste**
- Why traditional solutions don't work
- Cost of status quo (in EUR or time)
- 1 visual: before/after comparison

**Slide 4: Notre Approche**
- Agents IA autonomes, pas des chatbots
- 3 pillars max, each in 1 sentence
- Differentiation from competitors (without naming them)

**Slide 5: Comment Ca Marche**
- 4-step process, visual
- Emphasize: pas besoin de changer vos outils existants
- Timeline: resultats en semaines, pas en mois

**Slide 6-7: Cas Concret**
- Anonymized but specific: "Une ETI industrielle de 200 personnes"
- Probleme, solution, resultat
- Real numbers: "40% de gain sur le temps de traitement"
- Before/after comparison

**Slide 8: Resultats Clients**
- 3-4 metrics across clients
- MRR saved, hours recovered, errors reduced
- Social proof without naming names

**Slide 9: Equipe**
- Ludovic's background (briefly)
- Team capabilities
- Technology partners (Anthropic, etc.)

**Slide 10: Prochaines Etapes**
- Clear next step (not vague "let's discuss")
- Proposed timeline for getting started
- What they need to provide
- What we do first

### Proposal Structure (post-qualification)

All intro deck slides PLUS:

**Slide 11: Votre Situation**
- Mirror back what we learned in qualification
- Show we understood their specific pain
- 1-2 quotes from their own words (from email/meeting notes)

**Slide 12: Solution Proposee**
- Specific to their needs (not generic)
- Which agents/automations we'd deploy
- Integration points with their existing tools

**Slide 13: Plan de Deploiement**
- Phase 1: [2 weeks] Discovery + setup
- Phase 2: [4 weeks] Build + test
- Phase 3: [2 weeks] Deploy + train
- Phase 4: [ongoing] Monitor + optimize
- Clear milestones and deliverables per phase

**Slide 14: Investissement**
- Pricing in clear terms
- ROI calculation: cost vs expected gains
- Comparison: cost of doing nothing vs cost of solution
- Payment terms

**Slide 15: Garanties**
- SLA commitments
- Data security (RGPD compliance)
- Exit clause (no lock-in)

**Slide 16: FAQ**
- 4-5 common objections, pre-answered
- Tailored to their likely concerns

## Step 3: Writing Rules

### Content Rules
- French by default (English available on request)
- No jargon: explain technical concepts in business terms
- No superlatives: "le meilleur", "revolutionnaire" are banned
- Every claim backed by a number or example
- Keep text per slide under 50 words (visual > text)
- Use their language: mirror terms they used in emails/meetings

### Tone
- Confident but not arrogant
- Expert but accessible
- Direct: "We will do X" not "We could potentially explore X"
- Honest about limitations: "This works best for X, less suited for Y"

### Design Notes
- Clean, minimal design (specify for whoever creates the visual version)
- Orchestra brand colors: [specify if known]
- No stock photos of people pointing at screens
- Real screenshots or diagrams preferred over illustrations
- Data visualizations over bullet point lists

## Step 4: Output

### Markdown Document
```bash
mkdir -p ~/.alba/pitches
echo '[presentation content]' > ~/.alba/pitches/YYYY-MM-DD-[company]-[type].md
```

### Slide-Ready Format
Output each slide as a structured block:
```markdown
---
## SLIDE [N]: [Title]

[Content: max 50 words]

[Speaker Notes: what to say, talking points, 100-200 words]

[Visual Direction: what the slide should look like]
---
```

### JSON Structure (for automated deck generation)
```json
{
  "deck_type": "proposal",
  "client": "Acme Industries",
  "date": "2026-04-01",
  "slides": [
    {
      "number": 1,
      "title": "...",
      "content": "...",
      "speaker_notes": "...",
      "visual_direction": "...",
      "data_points": []
    }
  ],
  "metadata": {
    "total_slides": 16,
    "estimated_duration": "30 minutes",
    "key_objections_addressed": 4,
    "case_studies_included": 2
  }
}
```

### Telegram Notification (French)
```
PRESENTATION PRETE -- [Company Name]

Type: [introduction/proposal/case-study/QBR]
[N] slides, ~[M] minutes
Cas concrets inclus: [N]
Chiffres cles: [list key numbers used]

Fichier: [path]
A personnaliser: [any gaps that need Ludovic's input]
```

## Step 5: Version Tracking

```bash
# Track all deck versions per client
mkdir -p ~/.alba/pitches/[company-slug]
# v1, v2, etc. after Ludovic's feedback rounds
```

## Orchestra Rules
- Never share client names in pitch decks (anonymize: "Une ETI industrielle")
- Never fabricate case study numbers. Use only verified results
- Never promise specific ROI without documented basis
- Pricing must match current rate card
- RGPD: mention data protection proactively in proposals
- Include "Conditions generales" reference in proposals
- All proposals valid for 30 days (mention expiry date)
- Competitor mentions: never name them, only differentiate on our strengths
- Update rate card reference monthly
- Ludovic must review every proposal before sending
- Track win/loss rate per deck type for continuous improvement
- If client requests English version: translate but keep French as canonical
