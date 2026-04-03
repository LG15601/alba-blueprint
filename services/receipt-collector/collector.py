#!/usr/bin/env python3
"""
Receipt Collector — Automated SaaS invoice/receipt downloader
Uses browser-use + Gemini + 1Password SDK + persistent Chrome profile

Usage:
    python3 collector.py setup          # One-time: create persistent profile + login
    python3 collector.py collect        # Run collection on all portals
    python3 collector.py collect --portal openai   # Single portal
    python3 collector.py check-session  # Verify session is still valid
"""

import asyncio
import json
import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime

# Paths
AGENT_PROFILE_DIR = os.path.expanduser("~/.browser-agent-profile")
STATE_FILE = os.path.expanduser("~/.browser-agent-state.json")
OUTPUT_DIR = os.path.expanduser("~/Desktop/compta-q1-2026/portal-receipts")
CHROME_PATH = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ENV_FILE = os.path.expanduser("~/.alba/.env")

# Load env
def load_env():
    if os.path.exists(ENV_FILE):
        with open(ENV_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, val = line.split('=', 1)
                    # Handle ${VAR} references
                    if '${' not in val:
                        os.environ.setdefault(key.strip(), val.strip())

load_env()

# Portal definitions
PORTALS = {
    "openai_api": {
        "name": "OpenAI API (sales@)",
        "url": "https://platform.openai.com/settings/organization/billing/overview",
        "account": "sales@orchestraintelligence.fr",
        "auth_method": "google_sso",
        "task": """Navigate to the billing page. Find all invoices from January, February, March 2026.
        For each invoice, click to download the PDF receipt.
        Report all invoices found with dates and amounts.""",
    },
    "openai_chatgpt": {
        "name": "OpenAI ChatGPT (ludovic@)",
        "url": "https://chatgpt.com/account/manage",
        "account": "ludovic@orchestraintelligence.fr",
        "auth_method": "google_sso",
        "task": """Navigate to billing/subscription. Find invoices or receipts from January, February, March 2026.
        Especially looking for ChatGPT Pro 229 EUR (March 3) and ChatGPT Plus 23 EUR x3.
        Download any available invoice PDFs.
        Report all invoices found with dates and amounts.""",
    },
    "fnac": {
        "name": "FNAC",
        "url": "https://secure.fnac.com/identity/server/gateway/1/id/commandes",
        "account": "ludovic@orchestraintelligence.fr",
        "auth_method": "google_sso",
        "task": """Find orders from March 2026, especially around 1479 EUR.
        Download the invoice/facture if available.
        Report all orders found with dates and amounts.""",
    },
    "hostinger": {
        "name": "Hostinger",
        "url": "https://hpanel.hostinger.com/billing/invoices",
        "account": "ludovic.goutel@gmail.com",
        "auth_method": "google_sso",
        "task": """Find all invoices from January, February, March 2026.
        Download each invoice PDF.
        Report all invoices with dates and amounts.""",
    },
    "notion": {
        "name": "Notion",
        "url": "https://www.notion.so/settings/billing",
        "account": "sales@orchestraintelligence.fr",
        "auth_method": "google_sso",
        "task": """Find billing history. Download invoices for January and February 2026 (84.60 EUR each).
        Report what you find.""",
    },
    "ageo": {
        "name": "Ageo (Mutuelle)",
        "url": "https://www.ageo.fr",
        "account": "ludovic.goutel@gmail.com",
        "auth_method": "direct",
        "task": """Login to the Ageo member portal. Find receipts/attestations for January, February, March 2026.
        Download any available documents. Report what you find.""",
    },
    "free_mobile": {
        "name": "Free Mobile",
        "url": "https://mobile.free.fr/account/",
        "account": "43993233",
        "auth_method": "direct",
        "op_item": "mobile.free.fr",
        "task": """Login with the provided credentials. Navigate to invoices/factures.
        Find and download the January 2026 invoice (12 EUR).
        Report what you find.""",
    },
    "cursor": {
        "name": "Cursor",
        "url": "https://www.cursor.com/settings",
        "account": "sales@orchestraintelligence.fr",
        "auth_method": "google_sso",
        "task": """Navigate to billing/invoices. Download invoices for January and March 2026 (~20 EUR each).
        Report what you find.""",
    },
    "perplexity": {
        "name": "Perplexity",
        "url": "https://www.perplexity.ai/settings/billing",
        "account": "sales@orchestraintelligence.fr",
        "auth_method": "google_sso",
        "task": """Navigate to billing history. Download invoices for January and February 2026 (~20 EUR each).
        Report what you find.""",
    },
    "google_one": {
        "name": "Google One",
        "url": "https://one.google.com/u/0/storage",
        "account": "ludovic.goutel@gmail.com",
        "auth_method": "google_sso",
        "task": """Navigate to payment history/receipts. Find receipts for January, February, March 2026 (21.99 EUR each).
        Report what you find.""",
    },
}


def get_credential_from_1password(item_name: str, field: str = "password") -> str:
    """Get a credential from 1Password using the CLI."""
    token = os.environ.get("OP_SERVICE_ACCOUNT_TOKEN", "")
    if not token:
        print("ERROR: OP_SERVICE_ACCOUNT_TOKEN not set")
        return ""

    result = subprocess.run(
        ["op", "item", "get", item_name, "--vault", "CSV importé", "--fields", field, "--reveal"],
        capture_output=True, text=True,
        env={**os.environ, "OP_SERVICE_ACCOUNT_TOKEN": token}
    )
    return result.stdout.strip()


async def setup_profile():
    """One-time setup: create persistent Chrome profile and login to Google."""
    print("=== Browser Agent Profile Setup ===")
    print(f"Profile dir: {AGENT_PROFILE_DIR}")

    os.makedirs(AGENT_PROFILE_DIR, exist_ok=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("\nLaunching Chrome with dedicated agent profile...")
    print("LOGIN INSTRUCTIONS:")
    print("  1. Login to Google with sales@orchestraintelligence.fr")
    print("  2. Also login with ludovic@orchestraintelligence.fr (for FNAC/OpenAI)")
    print("  3. Close Chrome when done")
    print("")

    proc = subprocess.Popen([
        CHROME_PATH,
        f"--user-data-dir={AGENT_PROFILE_DIR}",
        "--no-first-run",
        "--no-default-browser-check",
        "https://accounts.google.com/signin",
    ])

    input("Press Enter when you've logged in and closed Chrome...")

    try:
        proc.terminate()
    except:
        pass

    print("\n✅ Profile setup complete!")
    print(f"Profile saved at: {AGENT_PROFILE_DIR}")
    print("You can now run: python3 collector.py collect")


async def check_session():
    """Check if the Google session in the persistent profile is still valid."""
    from browser_use import BrowserProfile, BrowserSession

    profile = BrowserProfile(
        chrome_path=CHROME_PATH,
        user_data_dir=AGENT_PROFILE_DIR,
        headless=True,
        keep_alive=False,
    )
    session = BrowserSession(browser_profile=profile)
    await session.start()

    page = await session.browser.get_current_page()
    await page.goto("https://myaccount.google.com/")
    await page.wait_for_load_state("networkidle")

    title = await page.title()
    url = page.url

    if "sign" in url.lower() or "login" in url.lower():
        print("❌ Session expired — run: python3 collector.py setup")
    else:
        print(f"✅ Session active — Google account page: {title}")

    await session.stop()


async def collect_portal(portal_key: str):
    """Collect receipts from a single portal."""
    from browser_use import Agent, BrowserProfile, BrowserSession
    from browser_use.llm.models import ChatGoogle

    portal = PORTALS[portal_key]
    print(f"\n{'='*60}")
    print(f"Collecting: {portal['name']} ({portal['url']})")
    print(f"{'='*60}")

    llm = ChatGoogle(model="gemini-2.5-flash")

    profile = BrowserProfile(
        chrome_path=CHROME_PATH,
        user_data_dir=AGENT_PROFILE_DIR,
        headless=False,
        keep_alive=False,
    )
    session = BrowserSession(browser_profile=profile)

    # Build task with auth instructions
    auth_instruction = ""
    if portal["auth_method"] == "google_sso":
        auth_instruction = f"""If asked to login, use Google SSO with {portal['account']}.
        The browser should already be logged into Google — just click the Google login button and select the account."""
    elif portal["auth_method"] == "direct":
        if "op_item" in portal:
            password = get_credential_from_1password(portal["op_item"])
            auth_instruction = f"Login with username {portal['account']} and the provided password."
        else:
            auth_instruction = f"Login with {portal['account']}."

    full_task = f"""Go to {portal['url']}
    If there's a cookie consent popup, accept all cookies.
    {auth_instruction}
    {portal['task']}
    Save any downloaded files to {OUTPUT_DIR}/"""

    sensitive = {}
    if portal["auth_method"] == "direct" and "op_item" in portal:
        password = get_credential_from_1password(portal["op_item"])
        if password:
            sensitive["login_password"] = password

    agent = Agent(
        task=full_task,
        llm=llm,
        browser_session=session,
        sensitive_data=sensitive if sensitive else None,
        max_actions_per_step=5,
    )

    history = await agent.run(max_steps=25)

    # Extract result
    result_text = "No result"
    try:
        for item in history.all_results:
            if hasattr(item, 'is_done') and item.is_done and item.extracted_content:
                result_text = item.extracted_content
    except AttributeError:
        # Fallback: try string representation
        result_text = str(history)[-500:]

    print(f"\nResult: {result_text}")

    try:
        await session.stop()
    except:
        pass

    return {
        "portal": portal_key,
        "name": portal["name"],
        "success": "success" in result_text.lower() or "invoice" in result_text.lower() or "facture" in result_text.lower(),
        "result": result_text,
        "timestamp": datetime.now().isoformat(),
    }


async def collect_all(portal_filter: str = None):
    """Collect receipts from all portals (or a specific one)."""
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    if portal_filter:
        if portal_filter not in PORTALS:
            print(f"Unknown portal: {portal_filter}")
            print(f"Available: {', '.join(PORTALS.keys())}")
            return
        portals_to_run = [portal_filter]
    else:
        portals_to_run = list(PORTALS.keys())

    results = []
    for key in portals_to_run:
        try:
            result = await collect_portal(key)
            results.append(result)
        except Exception as e:
            print(f"ERROR on {key}: {e}")
            results.append({"portal": key, "success": False, "result": str(e)})

    # Save results
    report_path = os.path.join(OUTPUT_DIR, f"collection-report-{datetime.now().strftime('%Y%m%d-%H%M')}.json")
    with open(report_path, 'w') as f:
        json.dump(results, f, indent=2, ensure_ascii=False)

    print(f"\n{'='*60}")
    print("COLLECTION SUMMARY")
    print(f"{'='*60}")
    success = sum(1 for r in results if r.get("success"))
    print(f"Success: {success}/{len(results)}")
    for r in results:
        status = "✅" if r.get("success") else "❌"
        print(f"  {status} {r.get('name', r['portal'])}")
    print(f"\nReport: {report_path}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    command = sys.argv[1]

    if command == "setup":
        asyncio.run(setup_profile())
    elif command == "check-session":
        asyncio.run(check_session())
    elif command == "collect":
        portal = sys.argv[2].replace("--portal=", "").replace("--portal", "").strip() if len(sys.argv) > 2 else None
        if portal and portal.startswith("--"):
            portal = None
        asyncio.run(collect_all(portal))
    else:
        print(f"Unknown command: {command}")
        print(__doc__)


if __name__ == "__main__":
    main()
