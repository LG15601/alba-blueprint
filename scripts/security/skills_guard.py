#!/usr/bin/env python3
"""
Skills Guard — Security Scanner for Agent Skill Files

Scans skill directories (.md, .sh, .py, .json, etc.) for security threats
using memory_guard's scan_content() engine, with trust matrix support for
known false positives.

Trust matrix: a JSON config mapping path globs to lists of allowed pattern_ids
so that known-safe patterns in specific skills don't generate noise.

Exit codes match memory_guard convention:
    2 = CRITICAL findings
    1 = HIGH findings
    0 = clean (or all findings exempted by trust matrix)

Usage:
    python skills_guard.py --dir skills/
    python skills_guard.py --file skills/health-check/SKILL.md
    python skills_guard.py --dir skills/ --trust-matrix config/trust-matrix.json
    python skills_guard.py --dir skills/ --trust-matrix config/trust-matrix.json --json
"""

import argparse
import fnmatch
import json
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional

# Import scan_content and Finding from memory_guard in the same directory
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from memory_guard import scan_content, Finding


# ─── Trust Matrix ───────────────────────────────────────────────────────────

def load_trust_matrix(path: str) -> List[dict]:
    """Load trust matrix from JSON config.

    Returns a list of rules, each with:
        glob: str — path glob pattern
        allow: List[str] — pattern_ids to exempt
    """
    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"⚠️  Trust matrix not found: {path}", file=sys.stderr)
        return []
    except json.JSONDecodeError as e:
        print(f"⚠️  Trust matrix parse error: {e}", file=sys.stderr)
        return []

    rules = data.get("rules", [])
    valid = []
    for rule in rules:
        if "glob" in rule and "allow" in rule:
            valid.append({"glob": rule["glob"], "allow": rule["allow"]})
        else:
            print(f"⚠️  Skipping malformed trust rule: {rule}", file=sys.stderr)
    return valid


def get_allowed_patterns(filepath: str, trust_matrix: List[dict]) -> set:
    """Return set of pattern_ids that are exempted for this filepath."""
    allowed = set()
    for rule in trust_matrix:
        if fnmatch.fnmatch(filepath, rule["glob"]):
            allowed.update(rule["allow"])
    return allowed


# ─── Scanning ───────────────────────────────────────────────────────────────

# File extensions to scan in skill directories
SCAN_EXTENSIONS = {'.md', '.sh', '.py', '.json', '.yaml', '.yml', '.toml', '.txt', '.cfg', '.ini', '.conf'}


def scan_skill_file(filepath: str, trust_matrix: Optional[List[dict]] = None) -> List[Finding]:
    """Scan a single skill file, applying trust matrix exemptions.

    Args:
        filepath: Path to the file to scan
        trust_matrix: List of trust rules (from load_trust_matrix)

    Returns:
        List of non-exempted findings
    """
    path = Path(filepath)
    if not path.exists():
        return [Finding(
            file=str(filepath),
            line_num=0,
            pattern_id="read_error",
            severity="ERROR",
            context=f"File not found: {filepath}",
        )]

    try:
        content = path.read_text(encoding='utf-8')
    except UnicodeDecodeError:
        # Binary file — skip silently
        return []
    except Exception as e:
        return [Finding(
            file=str(filepath),
            line_num=0,
            pattern_id="read_error",
            severity="ERROR",
            context=str(e),
        )]

    findings = scan_content(content, str(filepath))

    # Apply trust matrix exemptions
    if trust_matrix:
        allowed = get_allowed_patterns(str(filepath), trust_matrix)
        if allowed:
            original_count = len(findings)
            findings = [f for f in findings if f.pattern_id not in allowed]
            exempted = original_count - len(findings)
            if exempted > 0:
                print(f"  ℹ️  {filepath}: {exempted} finding(s) exempted by trust matrix",
                      file=sys.stderr)

    return findings


def scan_skill_directory(dirpath: str, trust_matrix: Optional[List[dict]] = None) -> Dict[str, List[Finding]]:
    """Scan all scannable files in a skill directory tree.

    Traverses all subdirectories and scans files with known extensions.

    Args:
        dirpath: Root directory to scan
        trust_matrix: List of trust rules

    Returns:
        Dict mapping filepath → list of findings (only files with findings)
    """
    results = {}
    root = Path(dirpath)

    if not root.exists():
        print(f"⚠️  Directory not found: {dirpath}", file=sys.stderr)
        return results

    if not root.is_dir():
        print(f"⚠️  Not a directory: {dirpath}", file=sys.stderr)
        return results

    scanned = 0
    for filepath in sorted(root.rglob("*")):
        if not filepath.is_file():
            continue
        if filepath.suffix.lower() not in SCAN_EXTENSIONS:
            continue

        scanned += 1
        findings = scan_skill_file(str(filepath), trust_matrix)
        if findings:
            results[str(filepath)] = findings

    print(f"  📂 Scanned {scanned} files in {dirpath}", file=sys.stderr)
    return results


# ─── Reporting ──────────────────────────────────────────────────────────────

def build_json_output(results: Dict[str, List[Finding]], trust_matrix_path: Optional[str] = None) -> dict:
    """Build structured JSON output."""
    all_findings = []
    for fp, findings in results.items():
        for f in findings:
            all_findings.append({
                "file": f.file,
                "line": f.line_num,
                "pattern_id": f.pattern_id,
                "severity": f.severity,
                "category": f.category,
                "context": f.context,
                "description": f.description,
            })

    severity_counts = {}
    for f in all_findings:
        sev = f["severity"]
        severity_counts[sev] = severity_counts.get(sev, 0) + 1

    return {
        "scanner": "skills_guard",
        "trust_matrix": trust_matrix_path,
        "files_with_findings": len(results),
        "total_findings": len(all_findings),
        "severity_counts": severity_counts,
        "findings": all_findings,
    }


def print_report(results: Dict[str, List[Finding]], show_all: bool = False):
    """Print a formatted security report."""
    total = sum(len(f) for f in results.values())
    critical = sum(1 for fs in results.values() for f in fs if f.severity == "CRITICAL")
    high = sum(1 for fs in results.values() for f in fs if f.severity == "HIGH")
    medium = sum(1 for fs in results.values() for f in fs if f.severity == "MEDIUM")
    low = sum(1 for fs in results.values() for f in fs if f.severity == "LOW")

    print("=" * 60)
    print("🛡️  SKILLS GUARD — Security Scan Report")
    print("=" * 60)
    print(f"Files with findings: {len(results)}")
    print(f"Total findings: {total}")
    if total > 0:
        print(f"  🔴 CRITICAL: {critical}")
        print(f"  🟠 HIGH:     {high}")
        print(f"  🟡 MEDIUM:   {medium}")
        print(f"  ⚪ LOW:      {low}")
    print("-" * 60)

    if not results:
        print("✅ No security issues found!")
        return

    severity_order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "ERROR": 4}

    for filepath, findings in sorted(results.items()):
        print(f"\n📄 {filepath}")
        sorted_findings = sorted(findings, key=lambda f: severity_order.get(f.severity, 5))
        for f in sorted_findings:
            if not show_all and f.severity == "LOW":
                continue
            icon = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "⚪"}.get(f.severity, "❓")
            desc = f.description or f.pattern_id
            cat_label = f" [{f.category}]" if f.category else ""
            print(f"  {icon} L{f.line_num}: [{f.severity}]{cat_label} {desc}")
            if f.context and f.severity != "LOW":
                print(f"     → {f.context}")


# ─── CLI ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Skills Guard — Security Scanner for Agent Skill Files",
        epilog="Exit codes: 2=CRITICAL, 1=HIGH, 0=clean"
    )
    parser.add_argument("--file", "-f", help="Scan a single file")
    parser.add_argument("--dir", "-d", help="Scan a skill directory tree")
    parser.add_argument("--trust-matrix", "-t",
                        help="Path to trust-matrix.json for false-positive exemptions")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--all", action="store_true", help="Show LOW severity findings too")
    args = parser.parse_args()

    if not args.file and not args.dir:
        parser.error("Either --file or --dir is required")

    # Load trust matrix if provided
    trust_matrix = None
    if args.trust_matrix:
        trust_matrix = load_trust_matrix(args.trust_matrix)
        if trust_matrix:
            print(f"  🔐 Loaded {len(trust_matrix)} trust matrix rules from {args.trust_matrix}",
                  file=sys.stderr)

    # Scan
    results = {}
    if args.file:
        findings = scan_skill_file(args.file, trust_matrix)
        if findings:
            results[args.file] = findings
    elif args.dir:
        results = scan_skill_directory(args.dir, trust_matrix)

    # Output
    if args.json:
        output = build_json_output(results, args.trust_matrix)
        print(json.dumps(output, indent=2, ensure_ascii=False))
    else:
        print_report(results, show_all=args.all)

    # Exit code: 2 for CRITICAL, 1 for HIGH, 0 for clean
    has_critical = any(f.severity == "CRITICAL" for fs in results.values() for f in fs)
    has_high = any(f.severity == "HIGH" for fs in results.values() for f in fs)
    sys.exit(2 if has_critical else 1 if has_high else 0)


if __name__ == "__main__":
    main()
