---
name: seo-writer
description: |
  Write daily SEO article in French for Orchestra Intelligence blog. Follows strict
  style rules: no bold, no em-dashes, no italic, includes stats/tables/FAQ, targets
  long-tail keywords. Use when asked to "write article", "SEO", "blog post",
  "contenu", or on daily content cron.
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

# SEO Writer -- French Content Engine

Production content pipeline that writes SEO-optimized articles in French for
Orchestra Intelligence's blog. One article per day, targeting long-tail keywords
in the AI/automation/PME space.

## Arguments
- `/seo-writer` -- generate article from content calendar
- `/seo-writer [topic]` -- write about specific topic
- `/seo-writer [keyword]` -- target specific keyword
- `/seo-writer audit [url]` -- audit existing article for SEO improvements

## Step 1: Topic Selection

### 1a. Check Content Calendar
```bash
cat ~/.alba/content/calendar.json 2>/dev/null || echo "No calendar -- generate topic"
```

### 1b. Keyword Research
If no calendar or manual topic, research keywords:

Target keyword profile:
- Language: French
- Monthly volume: 100-2000 (long-tail, achievable)
- Competition: low to medium
- Intent: informational or commercial investigation
- Relevant to Orchestra's services

Keyword clusters to rotate:
1. "automatisation [process] PME" (e.g., automatisation facturation PME)
2. "IA pour [sector]" (e.g., IA pour industrie manufacturiere)
3. "agent IA [use case]" (e.g., agent IA service client)
4. "transformation digitale [sector]" (e.g., transformation digitale BTP)
5. "optimiser [business process]" (e.g., optimiser gestion des stocks)
6. "cout [problem]" (e.g., cout erreurs manuelles entreprise)
7. "[tool] vs [tool] entreprise" (comparison articles)

### 1c. Competitor Content Gap
Search what French competitors have NOT covered:
```bash
# Search top 10 results for target keyword
# Identify gaps in existing content
# Find questions without good French answers
```

## Step 2: Research Phase

### 2a. Gather Data
For every article, collect:
- 3-5 statistics with sources (prefer French sources: INSEE, BPI, Statista FR)
- 2-3 case study references (anonymized Orchestra clients or public examples)
- Current state of the topic (what's changed in 2025-2026)
- Common objections or misconceptions

### 2b. SERP Analysis
Analyze the top 5 results for the target keyword:
- What structure do they use?
- What do they miss?
- What questions do they leave unanswered?
- How long are they? (target 10-20% longer than average)

### 2c. People Also Ask
Extract "People Also Ask" questions from Google for the keyword.
These become the FAQ section.

## Step 3: Write the Article

### Strict Style Rules -- NEVER VIOLATE

1. **NO BOLD TEXT** -- zero occurrences of `**text**` or `<b>` or `<strong>`
2. **NO ITALIC** -- zero occurrences of `*text*` or `<i>` or `<em>`
3. **NO EM-DASHES** -- use commas, periods, or "..." instead of "--" or the em-dash character
4. **NO EXCLAMATION MARKS** -- calm, factual tone
5. **NO "DECOUVREZ"** -- banned word in titles/headers
6. **NO AI VOCABULARY**: revolutionner, transformer, game-changer, disruptif, booster
7. **NO ENGLISH WORDS** when a French equivalent exists
8. Accents are required: e with accent where appropriate (use proper French typography)
9. Numbers: spell out one through ten, digits for 11+
10. Paragraphs: 2-4 sentences max, no walls of text

### Article Structure

```markdown
# [Title with target keyword, max 60 chars]

[Meta description: 150-160 chars, includes keyword, ends with actionable hook]

[Introduction: 3-4 sentences. State the problem. Give a number. Preview the answer.
No throat-clearing. No "Dans cet article, nous allons..."]

## [H2 with keyword variation]

[2-3 paragraphs of substance. Each paragraph adds new information.
No filler. No repetition of the introduction.]

[TABLE: comparison, data, or feature matrix -- at least 1 per article]

| Critere | Option A | Option B | Option C |
|---------|----------|----------|----------|
| ...     | ...      | ...      | ...      |

## [H2 with related keyword]

[Substance. Stats with sources. Real examples.]

[STAT CALLOUT]
> Selon [source], [specific statistic]. (Source: [name], [year])

## [H2 -- practical/how-to section]

[Numbered steps or actionable advice. Concrete, not generic.]

## [H2 -- costs or ROI section if applicable]

[Real numbers. Ranges acceptable. "Entre X et Y EUR" not "ca depend".]

## FAQ

### [Question from People Also Ask]
[Answer in 2-3 sentences. Direct, starts with the answer.]

### [Question 2]
[Answer]

### [Question 3]
[Answer]

### [Question 4]
[Answer]

## Conclusion

[3-4 sentences. Summarize the key takeaway. End with what to do next.
No "N'hesitez pas a nous contacter". Instead: state what the reader should
do differently starting tomorrow.]
```

### Word Count
- Minimum: 1500 words
- Target: 2000-2500 words
- Maximum: 3000 words
- FAQ answers: 50-100 words each

### Internal Linking
Include 2-3 internal links to other Orchestra content:
- Link text must be natural (not "cliquez ici")
- Link to relevant service pages or other articles
- One link in first 200 words, others distributed

### SEO Metadata
Generate alongside the article:
```json
{
  "title": "...",
  "meta_description": "...",
  "target_keyword": "...",
  "secondary_keywords": ["...", "..."],
  "slug": "...",
  "estimated_volume": "...",
  "word_count": 2200,
  "tables": 2,
  "faq_count": 4,
  "internal_links": 3,
  "stats_cited": 4
}
```

## Step 4: Quality Check

Before finalizing, verify:
- [ ] No bold, italic, or em-dashes anywhere
- [ ] No exclamation marks
- [ ] No banned vocabulary
- [ ] At least 1 table
- [ ] At least 3 stats with sources
- [ ] At least 4 FAQ items
- [ ] Word count in range
- [ ] Target keyword in H1, first H2, first paragraph, conclusion
- [ ] Meta description under 160 chars and includes keyword
- [ ] All French accents correct
- [ ] No orphan paragraphs (1 sentence alone)
- [ ] Internal links present and natural

### Automated Check
```bash
ARTICLE="$1"
# Check for banned patterns
grep -c '\*\*' "$ARTICLE" && echo "FAIL: Bold text found"
grep -c '\*[^*]' "$ARTICLE" && echo "FAIL: Italic text found"
grep -cP '\x{2014}' "$ARTICLE" && echo "FAIL: Em-dash found"
grep -c '!' "$ARTICLE" && echo "FAIL: Exclamation mark found"
grep -ci 'decouvrez\|revolutionner\|game-changer\|disruptif\|booster' "$ARTICLE" && echo "FAIL: Banned words"
wc -w "$ARTICLE"
```

## Step 5: Output

Write article to `~/.alba/content/articles/YYYY-MM-DD-[slug].md`
Write metadata to `~/.alba/content/articles/YYYY-MM-DD-[slug]-meta.json`

Notify via Telegram (French):
```
Article SEO pret: "[title]"
Mot-cle cible: [keyword] ([volume] rech/mois)
[word_count] mots, [table_count] tableaux, [faq_count] FAQ
Statut: pret pour publication
```

## Orchestra Rules
- All content in French with proper typography
- Never mention specific client names in public content
- Use "une entreprise du secteur [X]" for case studies
- RGPD compliant: no personal data in articles
- Link to orchestraintelligence.fr pages, not external competitors
- Source all statistics (no invented numbers)
- Date all stats (reject anything older than 3 years unless historical)
- No AI-generated images without explicit approval
- Tone: expert but accessible, like a knowledgeable colleague explaining over coffee
