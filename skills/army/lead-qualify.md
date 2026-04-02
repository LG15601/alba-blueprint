---
name: lead-qualify
description: |
  Score and qualify inbound leads using Orchestra Intelligence's qualification
  framework. Evaluates fit, budget, timing, and authority to produce a qualified
  lead score and recommended next action. Use when asked to "qualify lead",
  "evaluer prospect", "score lead", or when a new inbound inquiry arrives.
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
  - mcp__claude_ai_Gmail__gmail_search_messages
  - mcp__claude_ai_Gmail__gmail_read_message
---

# Lead Qualify -- Inbound Lead Scoring

Systematic qualification of inbound leads using Orchestra's BANT+P framework
(Budget, Authority, Need, Timeline + Pain). Produces an actionable score and
recommended next step.

## Arguments
- `/lead-qualify [email or company]` -- qualify a specific inbound lead
- `/lead-qualify scan` -- scan inbox for new unqualified leads
- `/lead-qualify batch` -- qualify all pending leads in pipeline

## Step 1: Identify the Lead

### If from email:
```
gmail_search_messages: query="from:[email] is:unread" or search by company domain
gmail_read_message: [message_id]
```

### If from pipeline:
```bash
cat /Users/alba/AZW/alba-blueprint/data/pipeline.json 2>/dev/null
```

### Extract Lead Data
- **Contact**: Name, title, email, phone
- **Company**: Name, domain, sector
- **Source**: How they found us (website form, referral, LinkedIn, event)
- **Initial request**: What they asked for in their first message
- **Attached materials**: Any documents, briefs, RFPs

## Step 2: Research the Company

### 2a. Company Profile
```
WebSearch: "[company name]" site:societe.com OR site:pappers.fr
WebSearch: "[company name]" "[sector]" employees OR effectif
```

Gather:
- Employee count
- Revenue (public or estimated)
- Sector/NAF code
- Year founded
- Recent news
- Website quality (modern vs legacy, signals digital maturity)

### 2b. Contact Research
```
WebSearch: "[contact name]" "[company name]" site:linkedin.com
```

Determine:
- Title and seniority (decision-maker or not?)
- Time in role
- Professional background
- Shared connections

### 2c. Digital Maturity Assessment
Quick check:
- Website technology (modern SPA vs old PHP)
- Online presence (active LinkedIn, Google reviews)
- Tools they use (visible in job postings or website footers)
- Previous digital initiatives mentioned in press

## Step 3: BANT+P Scoring

### Budget (0-25 points)
| Signal                                | Points |
|---------------------------------------|--------|
| Mentioned specific budget             | 25     |
| Budget range compatible (1-10K/month) | 20     |
| Company revenue suggests capacity     | 15     |
| No budget mentioned but company viable| 10     |
| Explicitly said "no budget yet"       | 5      |
| Company too small for our pricing     | 0      |

### Authority (0-20 points)
| Signal                                | Points |
|---------------------------------------|--------|
| CEO/DG/President making the request   | 20     |
| C-level or VP (CTO, DAF, COO)        | 18     |
| Director/Head of department           | 14     |
| Manager with influence                | 10     |
| Junior employee "exploring"           | 5      |
| Unknown / no title                    | 3      |

### Need (0-25 points)
| Signal                                | Points |
|---------------------------------------|--------|
| Specific problem described with detail| 25     |
| Clear use case mentioned              | 20     |
| General automation interest           | 15     |
| "Exploring AI" without specifics      | 10     |
| Vague "tell me about your services"   | 5      |
| Seems like tire-kicking               | 0      |

### Timeline (0-15 points)
| Signal                                | Points |
|---------------------------------------|--------|
| "Need this by [specific date]"        | 15     |
| "This quarter"                        | 12     |
| "This year"                           | 8      |
| "No rush, exploring"                  | 4      |
| No timeline mentioned                 | 2      |

### Pain (0-15 points)
| Signal                                | Points |
|---------------------------------------|--------|
| Described specific costly problem     | 15     |
| Mentioned failed previous attempt     | 13     |
| Losing money/time on manual processes | 10     |
| Growth bottleneck identified          | 8      |
| General dissatisfaction               | 5      |
| No pain articulated                   | 0      |

### Total Score: 0-100

## Step 4: Qualify and Categorize

| Score Range | Category      | Action                                  |
|-------------|---------------|-----------------------------------------|
| 80-100      | HOT LEAD      | Call within 24h, Ludovic personally      |
| 60-79       | QUALIFIED     | Respond within 48h, schedule call        |
| 40-59       | NURTURE       | Send relevant content, monitor           |
| 20-39       | COLD          | Automated response, quarterly check-in   |
| 0-19        | DISQUALIFY    | Polite decline or redirect               |

### Disqualification Criteria (automatic DISQUALIFY)
- AI company or direct competitor
- Student/researcher asking for free help
- Company with fewer than 5 employees
- Clear mismatch with our services
- Blacklisted domain or known spam

### Red Flags (reduce score by 10)
- Uses buzzwords without substance
- Asks for pricing without describing needs
- Previously ghosted us
- Mentions competitors extensively

### Green Flags (add 5 to score)
- Referral from existing client
- Attended our webinar or event
- Downloaded our content
- Second touchpoint (came back after initial visit)

## Step 5: Generate Qualification Report

```json
{
  "lead_id": "L-20260401-001",
  "date": "2026-04-01",
  "contact": {
    "name": "Pierre Martin",
    "title": "Directeur General",
    "email": "p.martin@acme.fr",
    "company": "Acme Industries SAS"
  },
  "company_profile": {
    "employees": 120,
    "revenue_estimate": "15M EUR",
    "sector": "Industrie manufacturiere",
    "location": "Lyon"
  },
  "scores": {
    "budget": 15,
    "authority": 20,
    "need": 20,
    "timeline": 12,
    "pain": 10,
    "total": 77
  },
  "category": "QUALIFIED",
  "source": "website_form",
  "initial_request_summary": "Cherche a automatiser le suivi de production",
  "recommended_action": "Repondre sous 48h, proposer un appel de qualification",
  "talking_points": [
    "Expertise en automatisation industrielle",
    "Case study: entreprise similaire, 40% gain productivite",
    "Integration avec leurs outils existants probable"
  ],
  "risks": [
    "N'a pas mentionne de budget specifique",
    "Secteur ou la vente est souvent longue (3-6 mois)"
  ]
}
```

## Step 6: Draft Response

Based on qualification:

### HOT LEAD (80+):
Draft a personal, warm response from Ludovic with proposed call times.
Invoke `/calendar-ops suggest` for availability.

### QUALIFIED (60-79):
Draft a professional response acknowledging their specific need,
with one relevant example and a meeting proposal.

### NURTURE (40-59):
Draft a response with useful content (article, guide) related to their interest.
No hard sell. Add to nurture drip.

### COLD/DISQUALIFY:
Draft a polite, brief response. If disqualified: redirect to appropriate resources.

## Step 7: Output

### Save to Pipeline
```bash
mkdir -p ~/.alba/leads
echo '[qualification]' > ~/.alba/leads/YYYY-MM-DD-[company-slug].json
```

### Telegram Notification (French)
```
LEAD QUALIFIE -- [Company Name]

Score: [total]/100 ([category])
Contact: [name], [title]
Entreprise: [employees] pers, [sector], [city]
Besoin: [1-line summary]

B:[score] A:[score] N:[score] T:[score] P:[score]

Action: [recommended action]
Brouillon de reponse cree: [oui/non]
```

## Orchestra Rules
- Qualify within 4h of receiving an inbound lead (business hours)
- RGPD: lead data stored locally, consent implied by their reaching out to us
- Never share lead data with third parties
- All qualification judgments must be evidence-based (no gut feelings in scores)
- If lead mentions a competitor: note it but do not badmouth
- If lead is a referral: note the referrer, send them a thank you
- Response drafts always for Ludovic's review before sending
- Track conversion rates per source for ROI analysis
- Re-qualify leads monthly if they haven't converted
- After 3 months without progression: archive unless explicit interest shown
