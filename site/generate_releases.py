#!/usr/bin/env python3
"""Build site/releases.json from this repository's GitHub releases.

The releases page is deployed by .github/workflows/pages.yml. Release assets
of a private repository are not downloadable by anonymous visitors, so the
public download button prefers the Gofile mirror that build.sh records in the
release notes.

Usage:
    GH_TOKEN=... GITHUB_REPOSITORY=owner/repo python3 site/generate_releases.py
    python3 site/generate_releases.py --input releases-api.json --out site/releases.json
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.request

API_ROOT = "https://api.github.com"
KERNEL_RE = re.compile(r"\b(\d+\.\d+\.\d+)\b")
COMMIT_RE = re.compile(r"\(([0-9a-f]{7,40})\)")
VERSION_RE = re.compile(r"\[([^\]]+)\]")
SHA_RE = re.compile(r"SHA-?256[^0-9a-f]*([0-9a-f]{64})", re.IGNORECASE)
MIRROR_RE = re.compile(r"https://gofile\.io/(?:d|download)/[A-Za-z0-9_-]+")
ROOTS = ("folkpatch", "apatch", "ksu", "vanilla")


def fetch_releases(repository: str, token: str) -> list[dict]:
    releases: list[dict] = []
    page = 1
    while True:
        url = f"{API_ROOT}/repos/{repository}/releases?per_page=100&page={page}"
        request = urllib.request.Request(
            url,
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {token}",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "pox-kernel-site",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                chunk = json.load(response)
        except urllib.error.HTTPError as error:
            raise SystemExit(f"GitHub API returned {error.code}: {error.read().decode(errors='replace')}")
        if not chunk:
            break
        releases.extend(chunk)
        if len(chunk) < 100:
            break
        page += 1
    return releases


def variant_of(name: str, tag: str) -> str:
    haystack = f"{name} {tag}".lower()
    for root in ROOTS:
        if root in haystack:
            return root
    if "sultan" in haystack:
        return "apatch"
    return "other"


def normalize(raw: dict) -> dict:
    body = raw.get("body") or ""
    title = raw.get("name") or raw.get("tag_name") or ""

    version = VERSION_RE.search(title)
    name = version.group(1).strip() if version else title
    commit = COMMIT_RE.search(title)
    kernel = KERNEL_RE.search(title)

    assets = []
    for asset in raw.get("assets") or []:
        assets.append(
            {
                "name": asset.get("name"),
                "size": asset.get("size") or 0,
                "url": asset.get("browser_download_url"),
            }
        )

    sha = SHA_RE.search(body)
    mirror = MIRROR_RE.search(body)

    return {
        "tag": raw.get("tag_name"),
        "title": title,
        "name": name,
        "variant": variant_of(name, raw.get("tag_name") or ""),
        "kernel": kernel.group(1) if kernel else None,
        "commit": commit.group(1) if commit else None,
        "published_at": raw.get("published_at") or raw.get("created_at"),
        "prerelease": bool(raw.get("prerelease")),
        "draft": bool(raw.get("draft")),
        "html_url": raw.get("html_url"),
        "body": body,
        "sha256": sha.group(1).lower() if sha else None,
        "mirror": mirror.group(0) if mirror else None,
        "assets": assets,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", help="Read a saved GitHub releases API response instead of calling the API")
    parser.add_argument("--out", default="site/releases.json", help="Output path (default: site/releases.json)")
    args = parser.parse_args()

    if args.input:
        with open(args.input, encoding="utf-8") as handle:
            raw = json.load(handle)
    else:
        token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
        repository = os.environ.get("GITHUB_REPOSITORY")
        if not token or not repository:
            print("GH_TOKEN/GITHUB_TOKEN and GITHUB_REPOSITORY are required", file=sys.stderr)
            return 2
        raw = fetch_releases(repository, token)

    releases = [
        normalize(item)
        for item in raw
        if not item.get("draft")
    ]
    releases.sort(key=lambda item: item.get("published_at") or "", reverse=True)

    payload = {
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "releases": releases,
    }

    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, ensure_ascii=False)
        handle.write("\n")

    print(f"Wrote {len(releases)} release(s) to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
