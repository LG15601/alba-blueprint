#!/usr/bin/env python3
"""
Memory Guard — Injection & Exfiltration Scanner for Agent Memory Files

Scans .md memory files for prompt injection, exfiltration, obfuscation,
supply-chain, persistence, network, and credential-exposure threats.

Ported from Hermes Agent (NousResearch) + custom patterns for Alba.
98+ threat patterns across 8 categories + 17 invisible Unicode codepoints.

Usage:
    python memory_guard.py                          # Scan default ~/.claude/projects/
    python memory_guard.py /path/to/memory/dir      # Scan specific directory
    python memory_guard.py --file /path/to/file.md  # Scan single file
    python memory_guard.py --stdin                  # Scan text from stdin
"""

import json
import os
import re
import sys
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Optional, Dict

# ─── Threat Patterns ────────────────────────────────────────────────────────
# (regex, pattern_id, severity, category)
#
# Categories:
#   prompt_injection  – attempts to hijack the agent's behavior
#   exfiltration      – leaking secrets, env vars, credentials
#   destructive       – file/disk destruction
#   persistence       – crontab, launchd, shell rc, systemd, login items
#   network           – reverse shells, tunnels, DNS exfil, external sockets
#   obfuscation       – base64, hex, eval, chr(), unicode escapes, rot13
#   supply_chain      – curl|bash, pip from URL, npm from git, postinstall
#   credential_exposure – hardcoded keys, passwords, tokens, .env reads

THREAT_PATTERNS = [
    # ═══════════════════════════════════════════════════════════════════════
    # PROMPT INJECTION (12 patterns)
    # ═══════════════════════════════════════════════════════════════════════
    (r'ignore\s+(previous|all|above|prior)\s+instructions',
     "prompt_injection", "HIGH", "prompt_injection"),
    (r'you\s+are\s+now\s+',
     "role_hijack", "HIGH", "prompt_injection"),
    (r'do\s+not\s+tell\s+the\s+user',
     "deception_hide", "HIGH", "prompt_injection"),
    (r'system\s+prompt\s+override',
     "sys_prompt_override", "CRITICAL", "prompt_injection"),
    (r'disregard\s+(your|all|any)\s+(instructions|rules|guidelines)',
     "disregard_rules", "HIGH", "prompt_injection"),
    (r'act\s+as\s+(if|though)\s+you\s+(have\s+no|don\'t\s+have)\s+(restrictions|limits|rules)',
     "bypass_restrictions", "HIGH", "prompt_injection"),
    (r'pretend\s+(?:\w+\s+)*(you\s+are|to\s+be)\s+',
     "role_pretend", "HIGH", "prompt_injection"),
    (r'output\s+(?:\w+\s+)*(system|initial)\s+prompt',
     "leak_system_prompt", "HIGH", "prompt_injection"),
    (r'(when|if)\s+no\s*one\s+is\s+(watching|looking)',
     "conditional_deception", "HIGH", "prompt_injection"),
    (r'\bDAN\s+mode\b|Do\s+Anything\s+Now',
     "jailbreak_dan", "CRITICAL", "prompt_injection"),
    (r'\bdeveloper\s+mode\b.*\benabled?\b',
     "jailbreak_dev_mode", "CRITICAL", "prompt_injection"),
    (r'(respond|answer|reply)\s+without\s+(?:\w+\s+)*(restrictions|limitations|filters|safety)',
     "remove_filters", "CRITICAL", "prompt_injection"),

    # ═══════════════════════════════════════════════════════════════════════
    # EXFILTRATION (18 patterns)
    # ═══════════════════════════════════════════════════════════════════════
    (r'curl\s+[^\n]*\$\{?\w*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|API)',
     "exfil_curl", "CRITICAL", "exfiltration"),
    (r'wget\s+[^\n]*\$\{?\w*(KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|API)',
     "exfil_wget", "CRITICAL", "exfiltration"),
    (r'cat\s+[^\n]*(\.env|credentials|\.netrc|\.pgpass|\.npmrc|\.pypirc)',
     "read_secrets", "HIGH", "exfiltration"),
    (r'\$HOME/\.ssh|\~/\.ssh',
     "ssh_access", "MEDIUM", "exfiltration"),
    (r'\$HOME/\.aws|\~/\.aws',
     "aws_dir_access", "HIGH", "exfiltration"),
    (r'\$HOME/\.gnupg|\~/\.gnupg',
     "gpg_dir_access", "HIGH", "exfiltration"),
    (r'\$HOME/\.kube|\~/\.kube',
     "kube_dir_access", "HIGH", "exfiltration"),
    (r'\$HOME/\.docker|\~/\.docker',
     "docker_dir_access", "HIGH", "exfiltration"),
    (r'printenv|env\s*\|',
     "dump_all_env", "HIGH", "exfiltration"),
    (r'os\.environ\b',
     "python_os_environ", "HIGH", "exfiltration"),
    (r'os\.getenv\s*\(\s*[^\)]*(?:KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL)',
     "python_getenv_secret", "CRITICAL", "exfiltration"),
    (r'process\.env\[',
     "node_process_env", "HIGH", "exfiltration"),
    (r'\b(dig|nslookup|host)\s+[^\n]*\$',
     "dns_exfil", "CRITICAL", "exfiltration"),
    (r'>\s*/tmp/[^\s]*\s*&&\s*(curl|wget|nc|python)',
     "tmp_staging_exfil", "CRITICAL", "exfiltration"),
    (r'!\[.*\]\(https?://[^\)]*\$\{?',
     "md_image_exfil", "HIGH", "exfiltration"),
    (r'\[.*\]\(https?://[^\)]*\$\{?',
     "md_link_exfil", "HIGH", "exfiltration"),
    (r'(include|output|print|send|share)\s+(?:\w+\s+)*(conversation|chat\s+history|previous\s+messages|context)',
     "context_exfil", "HIGH", "exfiltration"),
    (r'(send|post|upload|transmit)\s+.*\s+(to|at)\s+https?://',
     "send_to_url", "HIGH", "exfiltration"),

    # ═══════════════════════════════════════════════════════════════════════
    # CREDENTIAL EXPOSURE (14 patterns)
    # ═══════════════════════════════════════════════════════════════════════
    (r'(sk-[a-zA-Z0-9]{20,})',
     "api_key_anthropic", "CRITICAL", "credential_exposure"),
    (r'(sk-proj-[a-zA-Z0-9]{20,})',
     "api_key_openai", "CRITICAL", "credential_exposure"),
    (r'(xoxb-[0-9]{10,})',
     "slack_bot_token", "CRITICAL", "credential_exposure"),
    (r'(ghp_[a-zA-Z0-9]{36})',
     "github_pat", "CRITICAL", "credential_exposure"),
    (r'(gho_[a-zA-Z0-9]{36})',
     "github_oauth", "CRITICAL", "credential_exposure"),
    (r'(Bearer\s+[a-zA-Z0-9_\-\.]{20,})',
     "bearer_token", "HIGH", "credential_exposure"),
    (r'(AKIA[0-9A-Z]{16})',
     "aws_access_key", "CRITICAL", "credential_exposure"),
    (r'(eyJ[a-zA-Z0-9_\-]{50,}\.eyJ[a-zA-Z0-9_\-]{50,})',
     "jwt_token", "HIGH", "credential_exposure"),
    (r'(\d{10}:[A-Za-z0-9_-]{35})',
     "telegram_bot_token", "CRITICAL", "credential_exposure"),
    (r'-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----',
     "private_key_pem", "CRITICAL", "credential_exposure"),
    (r'password\s*[=:]\s*["\'][^"\']{8,}["\']',
     "hardcoded_password", "HIGH", "credential_exposure"),
    (r'passwd\s*[=:]\s*["\'][^"\']{8,}["\']',
     "hardcoded_passwd", "HIGH", "credential_exposure"),
    (r'(?:api[_-]?key|token|secret)\s*[=:]\s*["\'][A-Za-z0-9+/=_-]{20,}',
     "hardcoded_secret", "CRITICAL", "credential_exposure"),
    (r'0x[0-9a-fA-F]{64}',
     "possible_crypto_private_key", "MEDIUM", "credential_exposure"),

    # ═══════════════════════════════════════════════════════════════════════
    # DESTRUCTIVE (8 patterns)
    # ═══════════════════════════════════════════════════════════════════════
    (r'rm\s+-rf\s+/',
     "destructive_rm_root", "CRITICAL", "destructive"),
    (r'rm\s+-rf\s+~',
     "destructive_rm_home", "HIGH", "destructive"),
    (r'rm\s+(-[^\s]*)?r.*\$HOME',
     "destructive_rm_home_var", "CRITICAL", "destructive"),
    (r'mkfs\.\w+',
     "format_disk", "CRITICAL", "destructive"),
    (r'dd\s+if=.*of=/dev/',
     "dd_overwrite", "CRITICAL", "destructive"),
    (r'chmod\s+777',
     "insecure_perms", "MEDIUM", "destructive"),
    (r'>\s*/etc/',
     "system_overwrite", "CRITICAL", "destructive"),
    (r'truncate\s+-s\s*0\s+/',
     "truncate_system", "CRITICAL", "destructive"),

    # ═══════════════════════════════════════════════════════════════════════
    # PERSISTENCE (12 patterns)
    # ═══════════════════════════════════════════════════════════════════════
    (r'authorized_keys',
     "ssh_backdoor", "CRITICAL", "persistence"),
    (r'\bcrontab\b',
     "persistence_cron", "MEDIUM", "persistence"),
    (r'\.(bashrc|zshrc|profile|bash_profile|bash_login|zprofile|zlogin)\b',
     "shell_rc_mod", "MEDIUM", "persistence"),
    (r'launchctl\s+load|LaunchAgents|LaunchDaemons',
     "macos_launchd", "MEDIUM", "persistence"),
    (r'systemd.*\.service|systemctl\s+(enable|start)',
     "systemd_service", "MEDIUM", "persistence"),
    (r'/etc/init\.d/',
     "init_script", "MEDIUM", "persistence"),
    (r'/etc/sudoers|visudo',
     "sudoers_mod", "CRITICAL", "persistence"),
    (r'git\s+config\s+--global\s+',
     "git_config_global", "MEDIUM", "persistence"),
    (r'ssh-keygen',
     "ssh_keygen", "MEDIUM", "persistence"),
    (r'AGENTS\.md|CLAUDE\.md|\.cursorrules|\.clinerules',
     "agent_config_mod", "HIGH", "persistence"),
    (r'\.claude/settings|\.codex/config',
     "other_agent_config", "HIGH", "persistence"),
    (r'osascript\s+.*login\s+item|defaults\s+write.*LoginItems',
     "macos_login_item", "MEDIUM", "persistence"),

    # ═══════════════════════════════════════════════════════════════════════
    # NETWORK (12 patterns)
    # ═══════════════════════════════════════════════════════════════════════
    (r'\bnc\s+-[lp]|ncat\s+-[lp]|\bsocat\b',
     "reverse_shell", "CRITICAL", "network"),
    (r'/bin/(ba)?sh\s+-i\s+.*>/dev/tcp/',
     "bash_reverse_shell", "CRITICAL", "network"),
    (r'python[23]?\s+-c\s+["\']import\s+socket',
     "python_socket_oneliner", "CRITICAL", "network"),
    (r'socket\.connect\s*\(\s*\(',
     "python_socket_connect", "HIGH", "network"),
    (r'\bngrok\b|\blocaltunnel\b|\bserveo\b|\bcloudflared\b',
     "tunnel_service", "HIGH", "network"),
    (r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}:\d{2,5}',
     "hardcoded_ip_port", "MEDIUM", "network"),
    (r'0\.0\.0\.0:\d+|INADDR_ANY',
     "bind_all_interfaces", "HIGH", "network"),
    (r'webhook\.site|requestbin\.com|pipedream\.net|hookbin\.com',
     "exfil_service", "HIGH", "network"),
    (r'pastebin\.com|hastebin\.com|ghostbin\.',
     "paste_service", "MEDIUM", "network"),
    (r'httpx?\.(get|post|put|patch)\s*\([^\n]*(KEY|TOKEN|SECRET|PASSWORD)',
     "http_lib_secret", "CRITICAL", "network"),
    (r'requests\.(get|post|put|patch)\s*\([^\n]*(KEY|TOKEN|SECRET|PASSWORD)',
     "requests_lib_secret", "CRITICAL", "network"),
    (r'fetch\s*\([^\n]*\$\{?\w*(KEY|TOKEN|SECRET|PASSWORD|API)',
     "fetch_secret", "CRITICAL", "network"),

    # ═══════════════════════════════════════════════════════════════════════
    # OBFUSCATION (16 patterns)
    # ═══════════════════════════════════════════════════════════════════════
    (r'[A-Za-z0-9+/]{100,}={0,2}',
     "base64_blob", "LOW", "obfuscation"),
    (r'base64\s+(-d|--decode)\s*\|',
     "base64_decode_pipe", "HIGH", "obfuscation"),
    (r'base64[^\n]*env',
     "encoded_exfil", "HIGH", "obfuscation"),
    (r'\\x[0-9a-fA-F]{2}.*\\x[0-9a-fA-F]{2}.*\\x[0-9a-fA-F]{2}',
     "hex_encoded_string", "MEDIUM", "obfuscation"),
    (r'\beval\s*\(\s*["\']',
     "eval_string", "HIGH", "obfuscation"),
    (r'\bexec\s*\(\s*["\']',
     "exec_string", "HIGH", "obfuscation"),
    (r'echo\s+[^\n]*\|\s*(bash|sh|python|perl|ruby|node)',
     "echo_pipe_exec", "CRITICAL", "obfuscation"),
    (r'compile\s*\(\s*[^\)]+,\s*["\'].*["\']\s*,\s*["\']exec["\']\s*\)',
     "python_compile_exec", "HIGH", "obfuscation"),
    (r'getattr\s*\(\s*__builtins__',
     "python_getattr_builtins", "HIGH", "obfuscation"),
    (r'__import__\s*\(\s*["\']os["\']\s*\)',
     "python_import_os", "HIGH", "obfuscation"),
    (r'codecs\.decode\s*\(\s*["\']',
     "python_codecs_decode", "MEDIUM", "obfuscation"),
    (r'String\.fromCharCode|charCodeAt',
     "js_char_code", "MEDIUM", "obfuscation"),
    (r'atob\s*\(|btoa\s*\(',
     "js_base64", "MEDIUM", "obfuscation"),
    (r'\[::-1\]',
     "string_reversal", "LOW", "obfuscation"),
    (r'chr\s*\(\s*\d+\s*\)\s*\+\s*chr\s*\(\s*\d+',
     "chr_building", "HIGH", "obfuscation"),
    (r'\\u[0-9a-fA-F]{4}.*\\u[0-9a-fA-F]{4}.*\\u[0-9a-fA-F]{4}',
     "unicode_escape_chain", "MEDIUM", "obfuscation"),

    # ═══════════════════════════════════════════════════════════════════════
    # SUPPLY CHAIN (10 patterns)
    # ═══════════════════════════════════════════════════════════════════════
    (r'curl\s+[^\n]*\|\s*(ba)?sh',
     "curl_pipe_shell", "CRITICAL", "supply_chain"),
    (r'wget\s+[^\n]*-O\s*-\s*\|\s*(ba)?sh',
     "wget_pipe_shell", "CRITICAL", "supply_chain"),
    (r'curl\s+[^\n]*\|\s*python',
     "curl_pipe_python", "CRITICAL", "supply_chain"),
    (r'pip\s+install\s+(?!-r\s)(?!.*==).*https?://',
     "pip_install_url", "HIGH", "supply_chain"),
    (r'npm\s+install\s+.*(?:git\+|github:)',
     "npm_install_git", "HIGH", "supply_chain"),
    (r'"(?:pre|post)install"\s*:\s*"',
     "postinstall_script", "HIGH", "supply_chain"),
    (r'pip\s+install\s+(?!-r\s)(?!.*==)',
     "unpinned_pip_install", "MEDIUM", "supply_chain"),
    (r'npm\s+install\s+(?!.*@\d)',
     "unpinned_npm_install", "MEDIUM", "supply_chain"),
    (r'git\s+clone\s+',
     "git_clone_runtime", "MEDIUM", "supply_chain"),
    (r'docker\s+pull\s+',
     "docker_pull_runtime", "MEDIUM", "supply_chain"),

    # ═══════════════════════════════════════════════════════════════════════
    # SENSITIVE FILE ACCESS (6 patterns)
    # ═══════════════════════════════════════════════════════════════════════
    (r'/etc/passwd',
     "etc_passwd", "MEDIUM", "sensitive_files"),
    (r'/etc/shadow',
     "etc_shadow", "HIGH", "sensitive_files"),
    (r'\.ssh/id_rsa',
     "ssh_private_key", "HIGH", "sensitive_files"),
    (r'\.ssh/id_ed25519',
     "ssh_private_key_ed25519", "HIGH", "sensitive_files"),
    (r'/proc/self|/proc/\d+/',
     "proc_access", "HIGH", "sensitive_files"),
    (r'/dev/shm/',
     "dev_shm", "MEDIUM", "sensitive_files"),

    # ═══════════════════════════════════════════════════════════════════════
    # HIDDEN CONTENT (4 patterns)
    # ═══════════════════════════════════════════════════════════════════════
    (r'<!--[^>]*(?:ignore|override|system|secret|hidden)[^>]*-->',
     "html_comment_injection", "HIGH", "hidden_content"),
    (r'<\s*div\s+style\s*=\s*["\'].*display\s*:\s*none',
     "hidden_div", "HIGH", "hidden_content"),
    (r'translate\s+.*\s+into\s+.*\s+and\s+(execute|run|eval)',
     "translate_execute", "CRITICAL", "hidden_content"),
    (r'hypothetical\s+scenario.*(?:ignore|bypass|override)',
     "hypothetical_bypass", "HIGH", "hidden_content"),
]

# Pattern count assertion — enforced at import time
_PATTERN_COUNT = len(THREAT_PATTERNS)
assert _PATTERN_COUNT >= 98, f"Expected 98+ patterns, got {_PATTERN_COUNT}"

# ─── Invisible Unicode Characters (17 codepoints) ───────────────────────────

INVISIBLE_CHARS = {
    '\u200b': 'ZERO WIDTH SPACE',
    '\u200c': 'ZERO WIDTH NON-JOINER',
    '\u200d': 'ZERO WIDTH JOINER',
    '\u2060': 'WORD JOINER',
    '\u2062': 'INVISIBLE TIMES',
    '\u2063': 'INVISIBLE SEPARATOR',
    '\u2064': 'INVISIBLE PLUS',
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


# ─── Data Structures ────────────────────────────────────────────────────────

@dataclass
class Finding:
    file: str
    line_num: int
    pattern_id: str
    severity: str
    context: str  # truncated line content
    category: str = ""
    description: str = ""


# ─── Core Scanning ──────────────────────────────────────────────────────────

def scan_content(content: str, filename: str = "<unknown>") -> List[Finding]:
    """Scan text content for security threats.

    Used by all write paths: observations, session summaries,
    MEMORY.md updates, and consolidation output.
    """
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
                    category="injection",
                    description=f"Invisible char: {name} (U+{ord(char):04X})"
                ))

        # Check threat patterns
        for pattern, pid, severity, category in THREAT_PATTERNS:
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
                    category=category,
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
        print(f"⚠️  Directory not found: {dirpath}", file=sys.stderr)
        return results

    for filepath in sorted(dirpath.glob("**/*.md")):
        findings = scan_file(filepath)
        if findings:
            results[str(filepath)] = findings
    return results


# ─── Reporting ──────────────────────────────────────────────────────────────

def print_report(results: Dict[str, List[Finding]], show_all: bool = True):
    """Print a formatted security report."""
    total = sum(len(f) for f in results.values())
    critical = sum(1 for fs in results.values() for f in fs if f.severity == "CRITICAL")
    high = sum(1 for fs in results.values() for f in fs if f.severity == "HIGH")
    medium = sum(1 for fs in results.values() for f in fs if f.severity == "MEDIUM")
    low = sum(1 for fs in results.values() for f in fs if f.severity == "LOW")

    print("=" * 60)
    print("🛡️  MEMORY GUARD — Security Scan Report")
    print(f"    {_PATTERN_COUNT} patterns | {len(INVISIBLE_CHARS)} invisible-char detectors")
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

    for filepath, findings in results.items():
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


def print_stats():
    """Print pattern coverage statistics."""
    categories = {}
    for _, _, severity, category in THREAT_PATTERNS:
        categories.setdefault(category, {"total": 0, "CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0})
        categories[category]["total"] += 1
        categories[category][severity] += 1

    print(f"\n🛡️  Memory Guard — {_PATTERN_COUNT} patterns across {len(categories)} categories")
    print(f"    + {len(INVISIBLE_CHARS)} invisible Unicode codepoints")
    print("-" * 50)
    for cat, counts in sorted(categories.items()):
        parts = []
        for sev in ("CRITICAL", "HIGH", "MEDIUM", "LOW"):
            if counts[sev]:
                parts.append(f"{counts[sev]} {sev}")
        print(f"  {cat:24s} {counts['total']:3d}  ({', '.join(parts)})")
    print("-" * 50)
    print(f"  {'TOTAL':24s} {_PATTERN_COUNT:3d}")


# ─── CLI ────────────────────────────────────────────────────────────────────

def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="Memory Guard — Security Scanner",
        epilog=f"{_PATTERN_COUNT} threat patterns + {len(INVISIBLE_CHARS)} invisible Unicode detectors"
    )
    parser.add_argument("directory", nargs="?", default=os.path.expanduser("~/.claude/projects"),
                        help="Directory to scan (default: ~/.claude/projects)")
    parser.add_argument("--file", "-f", help="Scan a single file instead")
    parser.add_argument("--stdin", action="store_true", help="Scan text from stdin")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    parser.add_argument("--all", action="store_true", help="Show LOW severity too")
    parser.add_argument("--stats", action="store_true", help="Show pattern statistics")
    args = parser.parse_args()

    if args.stats:
        print_stats()
        sys.exit(0)

    if args.stdin:
        content = sys.stdin.read()
        findings = scan_content(content, "<stdin>")
        results = {"<stdin>": findings} if findings else {}
    elif args.file:
        findings = scan_file(Path(args.file))
        results = {args.file: findings} if findings else {}
    else:
        results = scan_directory(Path(args.directory))

    if args.json:
        output = {}
        for fp, findings in results.items():
            output[fp] = [
                {"line": f.line_num, "pattern": f.pattern_id, "severity": f.severity,
                 "category": f.category, "context": f.context, "description": f.description}
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
