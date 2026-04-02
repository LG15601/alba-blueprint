---
name: drive-organizer
description: "Organize Google Drive with clean folder structure, naming conventions, project templates, and archival. Use when asked about Drive, files, folders, organization, or cleanup."
user-invocable: true
version: "1.0"
allowed-tools:
  - Bash
  - Read
  - Write
  - Glob
---

# Drive Organizer — Google Drive Structure Manager

Maintains a clean, consistent Google Drive structure for Orchestra Intelligence. Creates folders, enforces naming conventions, moves scattered files, archives old projects, and creates templates for new ones.

## Tool

- **CLI**: `gog drive` (Google Drive operations)
- **Account**: sales@orchestraintelligence.fr (primary Drive)

## Master Folder Structure

```
Orchestra Intelligence/
├── Comptabilite/
│   └── 2026/
│       ├── 01-Janvier/
│       ├── 02-Fevrier/
│       ├── 03-Mars/
│       ├── 04-Avril/
│       ├── 05-Mai/
│       ├── 06-Juin/
│       ├── 07-Juillet/
│       ├── 08-Aout/
│       ├── 09-Septembre/
│       ├── 10-Octobre/
│       ├── 11-Novembre/
│       └── 12-Decembre/
├── Clients/
│   └── [ClientName]/
│       ├── Contrats/
│       ├── Propositions/
│       ├── Livrables/
│       ├── Communication/
│       └── Facturation/
├── Projets/
│   └── [ProjectName]/
│       ├── Specs/
│       ├── Design/
│       ├── Dev/
│       ├── QA/
│       └── Docs/
├── Admin/
│   ├── Contrats/
│   ├── Legal/
│   ├── Assurances/
│   └── RH/
├── Marketing/
│   ├── Branding/
│   ├── Campagnes/
│   ├── Contenu/
│   └── Analytics/
├── Templates/
│   ├── Proposition-commerciale/
│   ├── Contrat-type/
│   ├── Brief-client/
│   └── Rapport-mensuel/
└── Archives/
    └── [Year]/
```

## Step-by-step Workflow

### 1. Verify master structure exists

```bash
# List current top-level folders
gog drive list --path "Orchestra Intelligence/" --format json > /tmp/drive_structure.json

# Create any missing top-level folders
for folder in Comptabilite Clients Projets Admin Marketing Templates Archives; do
  gog drive mkdir --parents "Orchestra Intelligence/${folder}"
done
```

### 2. Create monthly comptabilite folders

```bash
YEAR=$(date +%Y)
MONTHS=("01-Janvier" "02-Fevrier" "03-Mars" "04-Avril" "05-Mai" "06-Juin" "07-Juillet" "08-Aout" "09-Septembre" "10-Octobre" "11-Novembre" "12-Decembre")

for month in "${MONTHS[@]}"; do
  gog drive mkdir --parents "Orchestra Intelligence/Comptabilite/${YEAR}/${month}"
done
```

### 3. Scan for misplaced files

Check root and common dump locations for unfiled documents:

```bash
# List files in root (should be empty — everything goes in folders)
gog drive list --path "/" --files-only --format json > /tmp/root_files.json

# List files in shared drives that should be in client folders
gog drive list --path "Orchestra Intelligence/" --files-only --format json > /tmp/toplevel_files.json
```

For each misplaced file:
1. Identify type from filename and content
2. Determine correct folder based on naming convention
3. Move to appropriate location
4. Log the move

### 4. Enforce naming conventions

File naming standard: `YYYY-MM-DD_type_description_v[N].ext`

Types:
- `proposition` — commercial proposals
- `contrat` — contracts and agreements
- `facture` — invoices sent
- `brief` — client or project briefs
- `spec` — technical specifications
- `rapport` — reports and analyses
- `presentation` — slide decks
- `design` — design assets
- `pv` — proces-verbaux (meeting minutes)

```bash
# Scan for files not matching convention
# Flag files with:
# - Spaces instead of hyphens
# - Missing date prefix
# - Missing type prefix
# - "Copy of" or "(1)" duplicates
# - Generic names like "Document1", "Sans titre"
```

Generate a naming violation report:

```
## Naming Violations Found

| Current Name | Suggested Name | Location | Action |
|-------------|---------------|----------|--------|
| Proposition Wella.pdf | 2026-03-15_proposition_wella-ia-agent_v1.pdf | Clients/Wella/ | Rename |
| Copy of contrat.docx | (duplicate — archive or delete) | Root/ | Move to Archives |
```

### 5. Create new project folder

When a new project starts:

```bash
PROJECT_NAME="$1"  # e.g., "Wella-IA-Agent"

SUBFOLDERS=("Specs" "Design" "Dev" "QA" "Docs")
for sub in "${SUBFOLDERS[@]}"; do
  gog drive mkdir --parents "Orchestra Intelligence/Projets/${PROJECT_NAME}/${sub}"
done
```

### 6. Create new client folder

When a new client is onboarded:

```bash
CLIENT_NAME="$1"  # e.g., "Wella"

SUBFOLDERS=("Contrats" "Propositions" "Livrables" "Communication" "Facturation")
for sub in "${SUBFOLDERS[@]}"; do
  gog drive mkdir --parents "Orchestra Intelligence/Clients/${CLIENT_NAME}/${sub}"
done
```

### 7. Archive old projects

Projects with no file modifications in 6+ months:

```bash
# List projects and check last modified dates
gog drive list --path "Orchestra Intelligence/Projets/" --recursive --format json > /tmp/projects.json

# For each project with all files older than 6 months:
# Move to Archives/YYYY/ProjectName/
YEAR=$(date +%Y)
gog drive move "Orchestra Intelligence/Projets/OldProject" "Orchestra Intelligence/Archives/${YEAR}/OldProject"
```

### 8. Storage audit

```bash
# Check total storage usage
gog drive quota --format json

# List largest files
gog drive list --recursive --sort-by size --limit 20 --format json > /tmp/large_files.json

# List duplicate files (same name, same size)
# Flag for review
```

## Weekly Audit Report

Generated every Sunday:

```
## Drive Audit — Semaine du 30 Mars 2026

### Structure
- Top-level folders: OK (7/7 present)
- Comptabilite months: OK (12/12 created for 2026)
- Client folders: 8 active
- Project folders: 5 active, 2 candidates for archival

### Naming
- Files checked: 234
- Violations found: 3 (see details)
- Auto-renamed: 0 (requires approval)

### Storage
- Total used: 12.3 GB / 30 GB
- Largest folder: Clients/Wella (3.2 GB)
- Duplicate candidates: 2 files

### Actions Taken
- Created April comptabilite folder
- Moved 2 root files to proper folders
- Flagged 3 naming violations for review
```

## Output

- Weekly audit report (markdown)
- Naming violation alerts
- Storage usage summary
- Archival recommendations

## Integration

- **receipt-collector skill**: uses Comptabilite folder structure
- **expense-tracker skill**: uploads reports to Comptabilite folders
- **file-organizer agent**: delegates detailed organization tasks
- **morning-admin skill**: triggers daily quick-scan for misplaced files

## Rules

- NEVER delete files — always archive or flag for manual deletion
- Ask before renaming if unsure about the intended name
- Maintain French naming for all folder names
- Client folder names match CRM names exactly
- Archive moves preserve internal folder structure
