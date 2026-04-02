---
name: prospect-hunt
description: |
  Find PME/ETI leads matching Orchestra Intelligence targeting rules. Searches
  LinkedIn, company databases, and web sources for companies with 10-500 employees,
  operational pain points, no AI companies, B2B focus. Use when asked to "find leads",
  "prospect", "cherche des clients", or on weekly cron schedule.
version: 1.0.0
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - WebSearch
  - WebFetch
  - Grep
  - Glob
---

# Prospect Hunt -- Lead Generation Engine

Automated prospecting engine that finds companies matching Orchestra Intelligence's
ideal client profile (ICP) and prepares outreach context.

## Arguments
- `/prospect-hunt` -- default: find 10 new leads
- `/prospect-hunt [sector]` -- target specific sector (e.g., "industrie", "sante", "immobilier")
- `/prospect-hunt [N]` -- find N leads (max 50 per run)
- `/prospect-hunt enrich [company]` -- deep research on a specific company

## Ideal Client Profile (ICP)

### Hard Filters (must ALL match)
- **Location**: France (prioritize Ile-de-France, then grandes metropoles)
- **Size**: 10-500 employees (PME/ETI sweet spot)
- **Type**: B2B companies (not B2C consumer brands)
- **Revenue**: 1M-100M EUR annual (estimated)
- **NOT**: AI companies, pure-play tech startups, GAFAM subsidiaries
- **NOT**: Companies already in clients.json or pipeline.json

### Soft Scoring Criteria (weighted)
| Criterion                    | Weight | Description                                      |
|------------------------------|--------|--------------------------------------------------|
| Operational pain signals     | 25%    | Manual processes, scaling issues, hiring pain     |
| Digital maturity gap         | 20%    | Has website but poor automation, legacy tools     |
| Growth trajectory            | 15%    | Recent fundraise, new offices, hiring spree       |
| Decision-maker accessibility | 15%    | CEO/DG/DAF visible on LinkedIn, company blog      |
| Sector fit                   | 15%    | Sectors where OI has case studies or expertise    |
| Timing signals               | 10%    | New CTO hire, digital transformation mentions     |

### Priority Sectors (in order)
1. Industrie / Manufacturing -- strong pain, high budgets
2. Immobilier / Construction -- digitalization wave
3. Sante / Pharma (hors startups) -- regulatory + process pain
4. Services B2B / Conseil -- understand the value proposition
5. Distribution / Logistics -- operational complexity
6. Energie / Environnement -- transition digitale

## Step 1: Source Leads

### 1a. Web Search
Search for companies matching ICP using targeted queries:
```
"[sector] PME France" site:societe.com
"directeur general" "[sector]" "transformation digitale" site:linkedin.com
"[sector]" "recrute" "process" OR "operations" site:welcometothejungle.com
```

### 1b. Company Databases
```bash
# Check Societe.com, Pappers, or similar via web search
# Look for: SIREN, effectif, CA, secteur NAF
```

### 1c. Job Board Signals
Search for companies hiring roles that signal operational pain:
- "Responsable des operations"
- "Chef de projet digitalisation"
- "Responsable SI" (small company = pain)
- "Office manager" hiring (scaling pain)

### 1d. Event/Conference Attendees
Search recent French business events:
- BPI France events
- CCI conferences
- Sector-specific salons

### 1e. Existing Network Expansion
```bash
# Load current clients and find similar companies
cat /Users/alba/AZW/alba-blueprint/data/clients.json.example 2>/dev/null
# Look for companies in same sector, similar size, same region
```

## Step 2: Research Each Lead

For each potential lead, gather:
- **Company name** and legal form (SAS, SARL, SA)
- **SIREN/SIRET** if available
- **Employee count** (from Societe.com or LinkedIn)
- **Revenue estimate** (from public filings or estimates)
- **Sector** (NAF code + plain text)
- **Website** and quality assessment
- **Key decision-maker**: Name, title, LinkedIn URL
- **Pain signals**: What suggests they need Orchestra's help
- **Recent news**: Fundraise, expansion, hiring, digital projects
- **Competitive landscape**: Are they already working with a competitor?

## Step 3: Score and Rank

Apply the scoring criteria from Step 1. Each lead gets a score 0-100:
- 80+: HOT -- immediate outreach
- 60-79: WARM -- add to nurture queue
- 40-59: COOL -- monitor for signals
- Below 40: DISCARD -- doesn't match ICP

## Step 4: Prepare Outreach Context

For each HOT and WARM lead, generate:

### Approach Angle
Identify the specific pain point to lead with:
- NOT "we do AI" (too generic)
- NOT "we automate everything" (too vague)
- YES "Vous recrutez un responsable SI, ca veut dire que vos process internes bloquent votre croissance. On a aide [similar company type] a diviser par 3 le temps de [specific process]."

### Personalization Elements
- Reference something specific about their company
- Connect to a real result from a similar client (anonymized)
- Show understanding of their sector's challenges
- Mention a mutual connection if one exists

## Step 5: Output

### Lead Report
Write to `~/.alba/prospects/YYYY-MM-DD-prospects.json`:

```json
{
  "date": "2026-04-01",
  "sector_focus": "industrie",
  "leads_found": 15,
  "leads_qualified": 8,
  "leads": [
    {
      "company": "Acme Industries SAS",
      "siren": "123456789",
      "sector": "Industrie manufacturiere",
      "employees": 85,
      "revenue_estimate": "12M EUR",
      "location": "Lyon",
      "website": "https://acme-industries.fr",
      "decision_maker": {
        "name": "Jean Dupont",
        "title": "Directeur General",
        "linkedin": "https://linkedin.com/in/jeandupont"
      },
      "score": 82,
      "category": "HOT",
      "pain_signals": [
        "Recrute un responsable digitalisation",
        "Site web date de 2019",
        "Croissance 30% mais equipe IT = 1 personne"
      ],
      "approach_angle": "Scaling ops pain -- growing fast with no tech team",
      "outreach_draft": "..."
    }
  ]
}
```

### Summary for Telegram (French)
```
Prospection [SECTOR] -- [DATE]

[N] leads qualifies sur [M] analyses

HOT ([X]):
- [Company] ([size] pers, [city]) -- [pain signal]
  -> Angle: [approach]

WARM ([Y]):
- [Company] ([size] pers, [city]) -- [signal]

Prochaine etape: valider les HOT pour lancement outreach?
```

## Orchestra Rules
- RGPD: Store only professional/public data (company info, public LinkedIn profiles)
- Never scrape personal emails -- use company contact forms or LinkedIn
- Never mention specific client names in outreach templates (use "une entreprise du secteur")
- All prospect data stored locally, never sent to external APIs without anonymization
- Outreach tone: direct, factual, no marketing fluff, no "revolutionner votre business"
- Always verify leads are not already in CRM before adding
- Respect LinkedIn's terms: no automated scraping, manual research only
- If a lead is flagged as competitor's client: note it, do not approach aggressively
