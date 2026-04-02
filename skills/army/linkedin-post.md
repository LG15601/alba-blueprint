---
name: linkedin-post
description: |
  Write LinkedIn post matching Orchestra Intelligence voice: direct, factual,
  no LinkedIn fluff, real numbers, contrarian when warranted. French by default.
  Use when asked to "write LinkedIn post", "poster sur LinkedIn", "social media",
  or on content schedule.
version: 1.0.0
user-invocable: true
allowed-tools:
  - Bash
  - Read
  - Write
  - Agent
  - WebSearch
  - WebFetch
---

# LinkedIn Post -- Social Content Engine

Write LinkedIn posts that match Orchestra Intelligence's voice. Direct, factual,
no inspirational fluff, backed by real experience and numbers.

## Arguments
- `/linkedin-post` -- generate from content queue
- `/linkedin-post [topic]` -- write about specific topic
- `/linkedin-post react [url]` -- react to a news article or post
- `/linkedin-post case [client-type]` -- anonymized case study post

## Orchestra Voice on LinkedIn

### What Orchestra Sounds Like
- A technical founder who actually ships code, talking to other business people
- Factual observations from the field, not thought leadership
- "Here's what we saw" not "Here's what you should think"
- Specific numbers over vague claims
- Short sentences. Punch. Then explain.
- French, but technical terms in English when that's what professionals use

### What Orchestra Does NOT Sound Like
- LinkedIn influencers (no "I just realized...", no "Agree?", no "Thoughts?")
- Consulting firms (no jargon soup, no frameworks with acronyms)
- AI hype accounts (no "AI will change everything", no "mind-blowing")
- Self-promotional (no "proud to announce", no "excited to share")

## Banned Patterns

### NEVER Use
- Opening with "Je"  on the first word (start with the observation, not yourself)
- "Agree?" or "Thoughts?" as a closing
- "Proud to announce" / "Excited to share" / "Thrilled to"
- Emoji bullet points (no emoji lists)
- More than 2 hashtags
- "Repost if you agree"
- "This." as a standalone sentence
- "Let that sink in."
- Tagging people for engagement farming
- "10 lessons I learned from..."
- Generic AI predictions ("AI will replace X by 2027")
- Comparisons to historical figures or events

### Avoid
- More than 3 line breaks in a row
- Posts over 1500 characters (LinkedIn truncates at ~210 chars to "see more")
- English when French works
- Passive voice

## Post Structures (rotate)

### Structure 1: Observation
```
[Surprising fact or observation in 1-2 sentences]

[Context: what we saw, with specifics]

[Why this matters for the reader]

[Implication or what to do about it]
```

### Structure 2: Contrarian Take
```
[Common belief stated plainly]

[Why it's wrong or incomplete, with evidence]

[What actually works, from experience]

[The nuance most people miss]
```

### Structure 3: Case Study (anonymized)
```
[The problem, stated concretely with a number]

[What the company tried before (and why it didn't work)]

[What actually worked, with specific approach]

[Result: concrete number or outcome]

[The non-obvious takeaway]
```

### Structure 4: Industry Observation
```
[Trend or change observed in the market]

[Specific examples or data points]

[What this means for PME/ETI in France]

[What smart companies are doing about it]
```

### Structure 5: Technical Insight (accessible)
```
[Technical concept explained in one sentence a CEO would understand]

[Why it matters for business outcomes]

[Real example from our work]

[The practical implication]
```

## Step 1: Topic Selection

### If no topic given, pull from:
1. Recent veille findings (AI news with a take)
2. Client work insights (anonymized)
3. Industry trends observed
4. Content calendar if configured
5. React to trending tech news in France

### Topic Quality Filter
Before writing, check:
- Have we posted about this in the last 30 days? If yes, find a new angle
- Is this genuinely useful to our audience (dirigeants PME/ETI)?
- Can we add a perspective competitors cannot?
- Do we have real data or experience to back this up?

If any answer is no: pick a different topic.

## Step 2: Write the Post

### Writing Process
1. Write the hook (first 210 characters visible before "see more")
2. Write the body (substance, specifics)
3. Write the close (implication or action, NOT a question for engagement)
4. Add 1-2 relevant hashtags max
5. Review against banned patterns

### Length Guidelines
- Target: 800-1200 characters
- Hook (before fold): max 210 characters, must compel clicking "see more"
- Minimum substance: at least one specific number, fact, or example
- Close: 1-2 sentences, not a call to action

### Hashtag Rules
- Max 2 hashtags
- Relevant to the content (not audience fishing)
- Mix French and English as appropriate
- Examples: #IA #PME #TransformationDigitale #AgentsIA #Automatisation

## Step 3: Quality Check

Verify against all criteria:
- [ ] No banned patterns
- [ ] First word is not "Je"
- [ ] Under 1500 characters
- [ ] Hook under 210 characters and compelling
- [ ] At least one specific number or fact
- [ ] No self-promotion ("our amazing product")
- [ ] No AI hype vocabulary
- [ ] Max 2 hashtags
- [ ] Reads naturally in French
- [ ] A dirigeant PME would find this useful, not annoying
- [ ] We have evidence/experience for every claim

## Step 4: Output

Write post to `~/.alba/content/linkedin/YYYY-MM-DD-[slug].md`

Include metadata:
```json
{
  "date": "2026-04-01",
  "topic": "...",
  "structure": "observation|contrarian|case-study|industry|technical",
  "character_count": 980,
  "hashtags": ["#IA", "#PME"],
  "hook_length": 185,
  "status": "draft"
}
```

### Telegram Notification (French)
```
Post LinkedIn pret:

"[First 100 chars of hook]..."

Structure: [type]
[character_count] caracteres
Hashtags: [hashtags]

A valider avant publication.
```

## Step 5: Iteration

If Ludovic provides feedback:
- Adjust tone, facts, or angle
- Regenerate with feedback applied
- Never argue about tone -- Ludovic knows his audience

## Orchestra Rules
- All posts in French unless specifically about an English-language topic
- Never mention client names (even in positive case studies)
- Never share confidential metrics (our own or clients')
- Never tag clients without explicit permission
- Never post about competitors negatively (factual observations only)
- Ludovic must validate every post before publication
- One post per business day maximum
- No weekend posting
- If reacting to news: verify the news is real before posting
- Maintain 4:1 ratio of value posts to anything that could be seen as promotional
