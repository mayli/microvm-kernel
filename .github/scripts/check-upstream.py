#!/usr/bin/env python3
"""Decide whether the microvm PPA needs a new source upload.

The workflow runs this on a schedule.  It compares the newest stable Ubuntu
`linux` source in the resolute archive with the source versions already
published in the PPA.  The kernel package itself is always built by
Launchpad; this script only gates the source upload.
"""

import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

SERIES = os.environ.get("UBUNTU_SERIES", "resolute")
PPA = os.environ.get("PPA", "")
FORCE = os.environ.get("FORCE", "").lower() == "true"
RUN = os.environ.get("GITHUB_RUN_NUMBER", "1")
ATTEMPT = os.environ.get("GITHUB_RUN_ATTEMPT", "1")
STABLE_POCKETS = {"Release", "Updates", "Security"}


def api(url):
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "ubuntu-mini-microvm-kernel-ci"},
    )
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


def ppa_versions():
    if not PPA.startswith("ppa:") or "/" not in PPA[4:]:
        raise SystemExit("PPA must be set to ppa:OWNER/ARCHIVE")

    owner, archive = PPA[4:].split("/", 1)
    url = (
        "https://api.launchpad.net/1.0/"
        f"~{urllib.parse.quote(owner, safe='')}/+archive/ubuntu/"
        f"{urllib.parse.quote(archive, safe='')}"
    )
    query = urllib.parse.urlencode(
        {
            "ws.op": "getPublishedSources",
            "ws.size": "300",
            "source_name": "linux",
            "exact_match": "true",
        }
    )

    try:
        data = api(url + "?" + query)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            print(f"PPA {PPA} does not exist yet; treating as empty", file=sys.stderr)
            return []
        raise

    return [
        entry.get("source_package_version", "")
        for entry in data.get("entries", [])
        if entry.get("source_package_version")
    ]


def output(key, value):
    print(f"{key}={value}")
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(f"{key}={value}\n")


def main():
    if not PPA:
        raise SystemExit("PPA is not set; configure a repository variable")

    upstream = latest_upstream()
    versions = ppa_versions()
    prefix = f"{upstream}microvm"
    already_published = any(version.startswith(prefix) for version in versions)
    changed = FORCE or not already_published
    version = f"{upstream}microvm{RUN}.{ATTEMPT}"
    source_upload = "sd" if versions else "sa"

    output("upstream", upstream)
    output("version", version)
    output("changed", str(changed).lower())
    output("source_upload", source_upload)

    summary = (
        f"Upstream linux: `{upstream}`\n\n"
        f"PPA: `{PPA}`\n\n"
        f"Already published: `{already_published}`\n\n"
        f"Force: `{FORCE}`\n\n"
        f"Next source version: `{version}`\n\n"
        f"Source upload mode: `{source_upload}`\n"
    )
    print(summary)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a", encoding="utf-8") as handle:
            handle.write(summary + "\n")


if __name__ == "__main__":
    main()
