#!/usr/bin/env python3
"""Fail-closed validation for an ad-hoc 321Doit release candidate."""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
import plistlib
import re
import subprocess
import sys
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
VERSION_ATTR = f"{{{SPARKLE_NS}}}shortVersionString"
BUILD_ATTR = f"{{{SPARKLE_NS}}}version"
SIGNATURE_ATTR = f"{{{SPARKLE_NS}}}edSignature"


class PreflightError(RuntimeError):
    pass


def run(*args: str, allow_failure: bool = False) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(args, text=True, capture_output=True, check=False)
    if result.returncode != 0 and not allow_failure:
        detail = (result.stderr or result.stdout).strip()
        raise PreflightError(f"command failed ({' '.join(args)}): {detail}")
    return result


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PreflightError(message)


def release_key(version: str, build: str) -> tuple[tuple[int, ...], int]:
    numbers = tuple(int(value) for value in re.findall(r"\d+", version))
    require(bool(numbers), f"version has no numeric components: {version}")
    require(build.isdigit(), f"build is not numeric: {build}")
    return numbers, int(build)


def read_item(path: Path) -> tuple[ET.Element, str]:
    item_text = path.read_text(encoding="utf-8").strip()
    wrapped = (
        f'<rss xmlns:sparkle="{SPARKLE_NS}"><channel>'
        f"{item_text}</channel></rss>"
    )
    try:
        root = ET.fromstring(wrapped)
    except ET.ParseError as error:
        raise PreflightError(f"generated appcast item is not valid XML: {error}") from error
    items = root.findall("./channel/item")
    require(len(items) == 1, "generated appcast file must contain exactly one <item>")
    return items[0], item_text


def validate_feed_and_write_candidate(
    feed_path: Path,
    candidate_path: Path,
    item_text: str,
    version: str,
    build: str,
) -> None:
    try:
        tree = ET.parse(feed_path)
    except ET.ParseError as error:
        raise PreflightError(f"current appcast is not valid XML: {error}") from error
    existing: list[tuple[str, str]] = []
    for item in tree.getroot().findall("./channel/item"):
        enclosure = item.find("enclosure")
        if enclosure is None:
            continue
        existing.append((enclosure.attrib.get(VERSION_ATTR, ""), enclosure.attrib.get(BUILD_ATTR, "0")))
    require((version, build) not in existing, f"appcast already contains {version} build {build}; increment the build")
    if existing:
        newest_existing = max(existing, key=lambda value: release_key(*value))
        require(
            release_key(version, build) > release_key(*newest_existing),
            f"release {version} build {build} is not newer than current {newest_existing[0]} build {newest_existing[1]}",
        )

    feed_text = feed_path.read_text(encoding="utf-8")
    marker = "    <!-- Newest release first."
    marker_start = feed_text.find(marker)
    require(marker_start >= 0, "current appcast is missing the newest-release insertion marker")
    marker_end = feed_text.find("\n", marker_start)
    require(marker_end >= 0, "current appcast insertion marker is malformed")
    indented_item = "\n".join(
        line if line.startswith("    ") else f"    {line}" for line in item_text.splitlines()
    )
    candidate = feed_text[: marker_end + 1] + indented_item + "\n" + feed_text[marker_end + 1 :]
    try:
        candidate_root = ET.fromstring(candidate)
    except ET.ParseError as error:
        raise PreflightError(f"candidate appcast is not valid XML: {error}") from error
    candidate_entries = candidate_root.findall("./channel/item")
    require(len(candidate_entries) == len(existing) + 1, "candidate appcast did not preserve all previous releases")
    first = candidate_entries[0].find("enclosure")
    require(first is not None, "candidate appcast first item has no enclosure")
    require(first.attrib.get(VERSION_ATTR) == version, "candidate appcast newest version is wrong")
    require(first.attrib.get(BUILD_ATTR) == build, "candidate appcast newest build is wrong")
    candidate_path.parent.mkdir(parents=True, exist_ok=True)
    candidate_path.write_text(candidate, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--dmg", type=Path, required=True)
    parser.add_argument("--appcast-item", type=Path, required=True)
    parser.add_argument("--public-key", type=Path, required=True)
    parser.add_argument("--signer", type=Path, required=True)
    parser.add_argument("--feed", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    args = parser.parse_args()

    info_path = args.app / "Contents" / "Info.plist"
    executable = args.app / "Contents" / "MacOS" / "321Doit"
    require(info_path.is_file(), f"Info.plist missing: {info_path}")
    require(executable.is_file(), f"app executable missing: {executable}")
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    require(info.get("CFBundleShortVersionString") == args.version, "app version does not match release version")
    require(str(info.get("CFBundleVersion")) == args.build, "app build does not match release build")
    app_icon = args.app / "Contents" / "Resources" / "AppIcon.icns"
    require(app_icon.is_file(), "321Doit application icon is missing")
    require(info.get("CFBundleIconFile") == "AppIcon", "Info.plist does not declare AppIcon as the application icon")
    require(info.get("CFBundleIconName") == "AppIcon", "Info.plist does not declare the modern AppIcon name")
    project_icon = args.app / "Contents" / "Resources" / "ProjectIcon.icns"
    require(project_icon.is_file(), "321Doit project document icon is missing")
    document_types = info.get("CFBundleDocumentTypes", [])
    require(
        any("com.321doit.project" in entry.get("LSItemContentTypes", []) for entry in document_types),
        "Info.plist does not register the 321Doit project document type",
    )
    exported_types = info.get("UTExportedTypeDeclarations", [])
    require(
        any(
            entry.get("UTTypeIdentifier") == "com.321doit.project"
            and "321doit" in entry.get("UTTypeTagSpecification", {}).get("public.filename-extension", [])
            for entry in exported_types
        ),
        "Info.plist does not export the .321doit content type",
    )

    architectures = set(run("/usr/bin/lipo", "-archs", str(executable)).stdout.split())
    require({"arm64", "x86_64"}.issubset(architectures), f"app is not Universal 2: {sorted(architectures)}")
    for tool_name in ("ffmpeg", "ffprobe"):
        tool = args.app / "Contents" / "Resources" / "Tools" / tool_name
        require(tool.is_file(), f"offline dependency missing: {tool}")
        tool_architectures = set(run("/usr/bin/lipo", "-archs", str(tool)).stdout.split())
        require({"arm64", "x86_64"}.issubset(tool_architectures), f"{tool_name} is not Universal 2")

    opencode = args.app / "Contents" / "Resources" / "Tools" / "opencode"
    require(opencode.is_file(), "formal releases must include the OpenCode backend used by Mira")
    opencode_architectures = set(run("/usr/bin/lipo", "-archs", str(opencode)).stdout.split())
    require("arm64" in opencode_architectures, "bundled OpenCode backend has no arm64 slice")
    opencode_build_info = args.app / "Contents" / "Resources" / "ThirdParty" / "OpenCode" / "BUILD-INFO.txt"
    require(opencode_build_info.is_file(), "bundled OpenCode provenance is missing")
    third_party_notice = args.app / "Contents" / "Resources" / "ThirdParty" / "NOTICE.md"
    require(third_party_notice.is_file(), "third-party acknowledgement notice is missing")
    notice_text = third_party_notice.read_text(encoding="utf-8")
    require("Copyright (c) 2025 opencode" in notice_text, "OpenCode copyright notice is missing")
    require("Permission is hereby granted" in notice_text, "OpenCode MIT license text is incomplete")

    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(args.app))
    signature = run("/usr/bin/codesign", "-dvvv", str(args.app), allow_failure=True)
    signature_text = signature.stdout + signature.stderr
    require("Signature=adhoc" in signature_text, "release policy requires an ad-hoc app signature")
    require("runtime" not in signature_text.lower(), "Hardened Runtime must remain off for the ad-hoc release channel")

    public_key = args.public_key.read_text(encoding="utf-8").strip()
    try:
        decoded_key = base64.b64decode(public_key, validate=True)
    except ValueError as error:
        raise PreflightError("Sparkle public key is not valid base64") from error
    require(len(decoded_key) == 32, "Sparkle Ed25519 public key must be 32 bytes")
    require(info.get("SUPublicEDKey") == public_key, "embedded SUPublicEDKey does not match release public key")
    require(bool(info.get("SUFeedURL")), "SUFeedURL is missing from the app")

    expected_name = f"321Doit-{args.version}-build{args.build}-offline-installer.dmg"
    require(args.dmg.name == expected_name, f"DMG filename mismatch; expected {expected_name}")
    require(args.dmg.is_file(), f"DMG missing: {args.dmg}")
    sha_path = args.dmg.with_suffix(args.dmg.suffix + ".sha256")
    require(sha_path.is_file(), f"SHA-256 sidecar missing: {sha_path}")
    expected_sha = sha_path.read_text(encoding="utf-8").split()[0]
    actual_sha = hashlib.sha256(args.dmg.read_bytes()).hexdigest()
    require(actual_sha == expected_sha, "DMG SHA-256 sidecar does not match the artifact")

    item, item_text = read_item(args.appcast_item)
    enclosure = item.find("enclosure")
    require(enclosure is not None, "appcast item has no enclosure")
    require(enclosure.attrib.get(VERSION_ATTR) == args.version, "appcast version does not match")
    require(enclosure.attrib.get(BUILD_ATTR) == args.build, "appcast build does not match")
    require(enclosure.attrib.get("length") == str(args.dmg.stat().st_size), "appcast length does not match DMG")
    download_name = Path(urllib.parse.urlparse(enclosure.attrib.get("url", "")).path).name
    require(download_name == args.dmg.name, "appcast download filename does not match DMG")
    signature_value = enclosure.attrib.get(SIGNATURE_ATTR, "")
    require(bool(signature_value), "appcast enclosure has no Ed25519 signature")
    run(
        "/bin/zsh",
        str(args.signer),
        "verify",
        str(args.dmg),
        "--signature",
        signature_value,
        "--public-key",
        str(args.public_key),
    )

    validate_feed_and_write_candidate(
        args.feed,
        args.candidate,
        item_text,
        args.version,
        args.build,
    )
    print(f"release preflight OK: {args.version} build {args.build}")
    print(f"candidate appcast: {args.candidate}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PreflightError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
