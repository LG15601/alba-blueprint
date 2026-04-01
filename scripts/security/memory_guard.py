#!/usr/bin/env python3
"""
Memory Guard — Injection & Exfiltration Scanner for Agent Memory Files

Ported from Hermes Agent (NousResearch) + custom patterns for Alba/Middleman.
Scans .md memory files for prompt injection, exfiltration, and security threats.

Usage:
    python memory_guard.py                          # Scan default ~/.middleman/memory/
    python memory_guard.py /path/to/memory/dir      # Scan specific directory
    python memory_guard.py --file /path/to/file.md  # Scan single file
"""

import json
import os
import re
import sys
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Optional, Dict

# ─── Threat Patterns ────────────────────────────────────────────────────────

# From Hermes Agent + custom Alba patterns
THREAT_PATTERNS = [
    # === Prompt Injection (from Hermes) ===
    (r'ignore\s+(previous|all|above|prior)\s+instructions', "prompt_injection", "HIGH"),
    (r'you\s+are\s+now\s+', "role_hijack", "HIGH"),
    (r'do\s+not\s+tell\s+the\s+user', "deception_hide", "HIGH"),
    (r'system\s+prompt\s+override', "sys_prompt_override", "CRITICAL"),
    (r'disregard\s+(your|all|any)\s+(instructions|rules|guidelines)', "disregard_rules", "HIGH"),
    (r'act\s+as\s+(if|though)\s+you\s+(have\s+no|don\'t\s+have)\s+(restrictions|limits|rules)', "bypass_restrictions", "HIGH"),

    # === Exfiltration (from Hermes) ===
    (r'curl\s+[^\n]*\$\{?\w*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|API)', "exfil_curl", "CRITICAL"),
    (r'wget\s+[^\n]*\$\{?\w*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|API)', "exfil_wget", "CRITICAL"),
    (r'cat\s+[^\n]*(\.env|credentials|\.netrc|\.pgpass|\.npmrc|\.pypirc)', "read_secrets", "HIGH"),
    (r'authorized_keys', "ssh_backdoor", "CRITICAL"),
    (r'\$HOME/\.ssh|\~/\.ssh', "ssh_access", "MEDIUM"),

    # === Custom Alba Patterns ===
    # API keys / tokens in memory (should never be stored)
    (r'(sk-[a-zA-Z0-9]{20,})', "api_key_anthropic", "CRITICAL"),
    (r'(sk-proj-[a-zA-Z0-9]{20,})', "api_key_openai", "CRITICAL"),
    (r'(xoxb-[0-9]{10,})', "slack_bot_token", "CRITICAL"),
    (r'(ghp_[a-zA-Z0-9]{36})', "github_pat", "CRITICAL"),
    (r'(gho_[a-zA-Z0-9]{36})', "github_oauth", "CRITICAL"),
    (r'(Bearer\s+[a-zA-Z0-9_\-\.]{20,})', "bearer_token", "HIGH"),
    (r'(AKIA[0-9A-Z]{16})', "aws_access_key", "CRITICAL"),
    (r'(eyJ[a-zA-Z0-9_\-]{50,}\.eyJ[a-zA-Z0-9_\-]{50,})', "jwt_token", "HIGH"),

    # Telegram secrets
    (r'(\d{10}:[A-Za-z0-9_-]{35})', "telegram_bot_token", "CRITICAL"),

    # Base64 blobs (possible hidden payloads)
    (r'[A-Za-z0-9+/]{100,}={0,2}', "base64_blob", "LOW"),

    # Destructive commands
    (r'rm\s+-rf\s+/', "destructive_rm_root", "CRITICAL"),
    (r'rm\s+-rf\s+~', "destructive_rm_home", "HIGH"),
    (r'mkfs\.\w+', "format_disk", "CRITICAL"),
    (r'dd\s+if=.*of=/dev/', "dd_overwrite", "CRITICAL"),

    # Sensitive file paths
    (r'/etc/passwd', "etc_passwd", "MEDIUM"),
    (r'/etc/shadow', "etc_shadow", "HIGH"),
    (r'\.ssh/id_rsa', "ssh_private_key", "HIGH"),
    (r'\.ssh/id_ed25519', "ssh_private_key_ed25519", "HIGH"),

    # Password patterns
    (r'password\s*[=:]\s*["\'][^"\']{8,}["\']', "hardcoded_password", "HIGH"),
    (r'passwd\s*[=:]\s*["\'][^"\']{8,}["\']', "hardcoded_passwd", "HIGH"),

    # Crypto private keys
    (r'-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----', "private_key_pem", "CRITICAL"),
    (r'0x[0-9a-fA-F]{64}', "possible_crypto_private_key", "MEDIUM"),
]

# Invisible unicode characters (injection vectors)
INVISIBLE_CHARS = {
    '\u200b': 'ZERO WIDTH SPACE',
    '\u200c': 'ZERO WIDTH NON-JOINER',
    '\u200d': 'ZERO WIDTH JOINER',
    '\u2060': 'WORD JOINER',
    '\ufeff': 'BOM / ZERO WIDTH NO-BREAK SPACE',
    '\u202a': 'LEFT-TO-RIGHT EMBEDDING',
    '\u202b': 'RIGHT-TO-LEFT EMBEDDING',
    '\u202c': 'POP DIRECTIONAL FORMATTING',
    '\u202d': 'LEFT-TO-RIGHT OVERRIDE',
    '\u202e': 'RIGHT-TO-LEFT OVERRIDE',
    '\u2066': 'LEFT-TO-RIGHT ISOLATE',
    '\u2067': 'RIGHT-TO-LEFT ISOLATE',
    '\u2068': 'FIRST STRONG ISOLATE',
    '\u2069': 'POP DIRECTIONAL ISOLATE',
}


@dataclass
class Finding:
    file: str
    line_num: int
    pattern_id: str
    severity: str
    context: str  # truncated line content
    description: str = ""


def scan_content(content: str, filename: str = "<unknown>") -> List[Finding]:
    """Scan text content for security threats."""
    findings = []
    lines = content.split('\n')

    for line_num, line in enumerate(lines, 1):
        # Check invisible unicode
        for char, name in INVISIBLE_CHARS.items():
            if char in line:
                findings.append(Finding(
                    file=filename,
                    line_num=line_num,
                    pattern_id="invisible_unicode",
                    severity="HIGH",
                    context=repr(line[:80]),
                    description=f"Invisible char: {name} (U+{ord(char):04X})"
                ))

        # Check threat patterns
        for pattern, pid, severity in THREAT_PATTERNS:
            if re.search(pattern, line, re.IGNORECASE):
                # Truncate context to avoid leaking secrets
                ctx = line.strip()[:60]
                if len(line.strip()) > 60:
                    ctx += "..."
                findings.append(Finding(
                    file=filename,
                    line_num=line_num,
                    pattern_id=pid,
                    severity=severity,
                    context=ctx,
                ))

    return findings


def scan_file(filepath: Path) -> List[Finding]:
    """Scan a single memory file."""
    try:
        content = filepath.read_text(encoding='utf-8')
    except Exception as e:
        return [Finding(
            file=str(filepath),
            line_num=0,
            pattern_id="read_error",
            severity="ERROR",
            context=str(e),
        )]
    return scan_content(content, str(filepath))


def scan_directory(dirpath: Path) -> Dict[str, List[Finding]]:
    """Scan all .md files in a directory."""
    results = {}
    if not dirpath.exists():
        print(f"⚠️  Directory not found: {dirpath}")
        return results

    for filepath in sorted(dirpath.glob("**/*.md")):
        findings = scan_file(filepath)
        if findings:
            results[str(filepath)] = findings
    return results


def print_report(results: Dict[str, List[Finding]], show_all: bool = True):
    """Print a formatted security report."""
    total = sum(len(f) for f in results.values())
    critical = sum(1 for fs in results.values() for f in fs if f.severity == "CRITICAL")
    high = sum(1 for fs in results.values() for f in fs if f.severity == "HIGH")
    medium = sum(1 for fs in results.values() for f in fs if f.severity == "MEDIUM")
    low = sum(1 for fs in results.values() for f in fs if f.severity == "LOW")

    print("=" * 60)
    print("🛡️  MEMORY GUARD — Security Scan Report")
    print("=" * 60)
    print(f"Files scanned: {len(results) if results else 'all clean'}")
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

    for filepath, findings in results.items():
        print(f"\n📄 {filepath}")
        sorted_findings = sorted(findings, key=lambda f: severity_order.get(f.severity, 5))
        for f in sorted_findings:
            if not show_all and f.severity == "LOW":
                continue
            icon = {"CRITICAL": "🔴", "HIGH": "🟠", "MEDIUM": "🟡", "LOW": "⚪"}.get(f.severity, "❓")
            desc = f.description or f.pattern_id
            print(f"  {icon} L{f.line_num}: [{f.severity}] {desc}")
            if f.context and f.severity != "LOW":
                print(f"     → {f.context}")


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Memory Guard — Security Scanner")
    parser.add_argument("directory", nargs="?", default=os.path.expanduser("~/.middleman/memory"),
                        help="Directory to scan (default: ~/.middleman/memory)")
    parser.add_argument("--file", "-f", help="Scan a single file instead")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--all", action="store_true", help="Show LOW severity too")
    args = parser.parse_args()

    if args.file:
        findings = scan_file(Path(args.file))
        results = {args.file: findings} if findings else {}
    else:
        results = scan_directory(Path(args.directory))

    if args.json:
        output = {}
        for fp, findings in results.items():
            output[fp] = [
                {"line": f.line_num, "pattern": f.pattern_id, "severity": f.severity,
                 "context": f.context, "description": f.description}
                for f in findings
            ]
        print(json.dumps(output, indent=2, ensure_ascii=False))
    else:
        print_report(results, show_all=args.all)

    # Exit code: 2 for CRITICAL, 1 for HIGH, 0 for clean
    has_critical = any(f.severity == "CRITICAL" for fs in results.values() for f in fs)
    has_high = any(f.severity == "HIGH" for fs in results.values() for f in fs)
    sys.exit(2 if has_critical else 1 if has_high else 0)


if __name__ == "__main__":
    main()
