#!/usr/bin/env python3
"""Create Uptime Kuma's admin account by driving its first-run wizard.

This is the ONLY part of Kuma's setup that is not done declaratively. The push
monitors are written straight into Kuma's SQLite DB by the
uptime-kuma-monitor-sync unit (see modules/nixos/unit-heartbeat.nix) — but the
admin account cannot be, because Kuma stores a bcrypt hash and getting that
format subtly wrong locks you out of the UI with no way to tell from the DB.
The wizard is the one authority on it, so this drives the wizard.

Run once per fresh install:  sudo nix run .#provision-uptime-kuma

Idempotent: if an admin account already exists it reports that and exits 0.

Env:
  KUMA_URL        base URL, default http://127.0.0.1:3010
  KUMA_CRED_FILE  env-file with UPTIME_KUMA_USER / UPTIME_KUMA_PASSWORD
                  (default /run/agenix/uptime-kuma-admin)
"""

import os
import sys

from playwright.sync_api import sync_playwright

BASE = os.environ.get("KUMA_URL", "http://127.0.0.1:3010")
CRED_FILE = os.environ.get("KUMA_CRED_FILE", "/run/agenix/uptime-kuma-admin")


def read_env_file(path):
    out = {}
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


def main():
    try:
        creds = read_env_file(CRED_FILE)
    except PermissionError:
        sys.exit(f"cannot read {CRED_FILE} — run this with sudo")
    user = creds.get("UPTIME_KUMA_USER")
    password = creds.get("UPTIME_KUMA_PASSWORD")
    if not user or not password:
        sys.exit(f"no UPTIME_KUMA_USER / UPTIME_KUMA_PASSWORD in {CRED_FILE}")

    with sync_playwright() as p:
        browser = p.chromium.launch()
        pg = browser.new_page()
        try:
            pg.goto(BASE, wait_until="networkidle")

            # The wizard is identified by its confirm-password field; the login
            # form has the same username/password ids but no #repeat.
            if not pg.query_selector("#repeat"):
                print("uptime-kuma: admin account already exists, nothing to do")
                return

            pg.fill("#floatingInput", user)
            pg.fill("#floatingPassword", password)
            pg.fill("#repeat", password)
            pg.click("button[type=submit]")

            # Kuma is an SPA: this re-renders client-side rather than
            # navigating, so waiting on a load event would time out.
            for _ in range(100):
                pg.wait_for_timeout(300)
                if "/dashboard" in pg.url:
                    print(f"uptime-kuma: created admin account '{user}'")
                    # Let the socket flush the account creation before the
                    # browser goes away; the DB write happens server-side and
                    # closing too early has lost it.
                    pg.wait_for_timeout(3000)
                    return
            sys.exit("uptime-kuma: setup did not reach the dashboard")
        finally:
            browser.close()


if __name__ == "__main__":
    main()
