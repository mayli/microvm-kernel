#!/usr/bin/env python3
"""Decide whether to build and publish a new microvm kernel release.

The scheduled workflow compares the newest stable Ubuntu `linux` source for
resolute with existing GitHub Releases.  It does not run for a pull request.
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

SERIES = os.environ.get("UBUNTU_SERIES", "resolute")
REPO = os.environ.get("GITHUB_REPOSITORY", "")
TOKEN = os.environ.get("GITHUB_TOKEN", "")
FORCE = os.environ.get("FORCE", "").lower() == "true"
RUN = os.environ.get("GITHUB_RUN_NUMBER", "1")
ATTEMPT = os.environ.get("GITHUB_RUN_ATTEMPT", "1")
STABLE_POCKETS = {"Release", "Updates", "Security"}


def api(url):
    headers = {
        "User-Agent": "ubuntu-mini-microvm-kernel-ci",
        "Accept": "application/vnd.github+json",
    }
    if TOKEN:
        headers["Authorization"] = f"Bearer {TOKEN}"
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def deb_gt(a, b):
    result = subprocess.run(
        ["dpkg", "--compare-versions", a, "gt", b],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def latest_upstream():
    series = f"https://api.launchpad.net/1.0/ubuntu/{SERIES}"
    query = urllib.parse.urlencode(
        {
            "ws.op": "getPublishedSources",
            "ws.size": "300",
            "source_name": "linux",
            "exact_match": "true",
            "distro_series": series,
            "status": "Published",
        }
    )
    data = api("https://api.launchpad.net/1.0/ubuntu/+archive/primary?" + query)

    versions = []
    for entry in data.get("entries", []):
        if entry.get("pocket") not in STABLE_POCKETS:
            continue
        version = entry.get("source_package_version")
        if version and version not in versions:
            versions.append(version)

    if not versions:
        raise SystemExit(
            f"no Published linux source in pockets {sorted(STABLE_POCKETS)}"
        )

    best = versions[0]
    for version in versions[1:]:
        if deb_gt(version, best):
            best = version
    return best


def existing_release(prefix):
    if not REPO:
        raise SystemExit("GITHUB_REPOSITORY is not set")
    query = urllib.parse.urlencode({"per_page": "100"})
    url = f"https://api.github.com/repos/{REPO}/releases?{query}"
    for release in api(url):
        if release.get("draft"):
            continue
        if release.get("tag_name", "").startswith(prefix):
            return release.get("tag_name")
    return None


def output(key, value):
    print(f"{key}={value}")
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(f"{key}={value}\n")


def main():
    upstream = latest_upstream()
    tag_prefix = f"kernel-{upstream}-"
    existing = existing_release(tag_prefix)
    changed = FORCE or existing is None
    tag = f"{tag_prefix}{RUN}.{ATTEMPT}"
    version = f"{upstream}microvm{RUN}.{ATTEMPT}"

    output("upstream", upstream)
    output("version", version)
    output("tag", tag)
    output("changed", str(changed).lower())

    summary = (
        f"Upstream linux: `{upstream}`\n\n"
        f"Existing release: `{existing or 'none'}`\n\n"
        f"Force: `{FORCE}`\n\n"
        f"Next release tag: `{tag}`\n\n"
        f"Source version: `{version}`\n"
    )
    print(summary)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(summary + "\n")


if __name__ == "__main__":
    main()
