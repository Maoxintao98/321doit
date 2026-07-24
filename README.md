<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">中文</a> ·
  <a href="https://github.com/Maoxintao98/321doit/releases">Releases</a>
</p>

# 321Doit

**321Doit** is a free, open-source, local-first **filmmaking workstation for macOS**. It serves directors, cinematographers, producers, script supervisors, DITs, editors, post teams, independent creators, and small crews.

It brings storyboarding, production planning, script logging, verified offload, media conversion, and post handoff into one project-aware workspace. 321Doit began with secure camera-card offload, but it is no longer a single-purpose offload utility.

321Doit is built around a simple idea:

> Professional production workflows should not be locked behind expensive, closed, or overly complicated systems.

<p align="center">
  <a href="#download">Download</a> ·
  <a href="#what-is-321doit">What is 321Doit?</a> ·
  <a href="#current-status">Status</a> ·
  <a href="#core-features">Features</a> ·
  <a href="https://github.com/Maoxintao98/321doit/releases">Releases</a>
</p>

---

## What Is 321Doit?

**321Doit** is a native macOS workstation built around five professional tools. Each tool works independently or shares scenes, shots, shooting days, media, and handoff data through Project Mode.

It is not a general-purpose file manager.  
It is not just a checksum report generator.  
It is not only a card-copy utility.

321Doit is designed to connect the real production chain:

```text
Creative and script intent
  → Living Storyboard
  → Production Planning
  → Rapid Script Log
  → Turbo Offload
  → Media Conversion
  → Final Cut Pro / DaVinci Resolve and post handoff
```

The product is already a **full filmmaking workstation**; secure offload remains an important professional module and trust foundation rather than the definition of the entire app. See [PRODUCT.md](PRODUCT.md) for the canonical product brief.

---

## Download

Download the latest version from GitHub Releases:

- [GitHub Releases](https://github.com/Maoxintao98/321doit/releases)

Open the DMG, double-click **Install 321Doit.pkg**, and follow the macOS Installer. The package installs the app into **Applications** and verifies the installed Universal 2 bundle before finishing.

---

## Current Status

321Doit is currently in **Beta**.

The five-tool workstation is present in the app, with each module under active testing and interaction refinement.

| Area | Status |
|---|---|
| Living Storyboard: shot table, layered canvas, director wheels, blocking, animatic | Implemented / improving |
| Production Planning: calendar, shooting days, call sheets, scenes, on-set data | Implemented / improving |
| Rapid Script Log: scenes, shots, takes, continuity, multicam, iPad workflow | Implemented / improving |
| Multi-destination camera card offload | Usable |
| Parallel copy to multiple targets | Usable |
| File verification | Usable |
| xxHash64 / MD5 / SHA-1 / SHA-256 checksum options | Implemented |
| Resume manifest | Implemented |
| Strict resume validation | Implemented |
| Preflight safety checks | Implemented |
| Camera card detection | Implemented |
| ASC MHL v2.0 output | Implemented |
| PDF / CSV / JSON / TXT reports | Implemented |
| PDF reports with frame grabs | Implemented where supported |
| Media Conversion: rewrap, video transcode, lossless audio, media inspection | Implemented / improving |
| MP4 / MOV / MKV / WebM / AVI / M2TS / MXF | Implemented |
| H.264 / H.265 / ProRes / AV1 / VP9 / MPEG-2 / DNxHR | Implemented where supported by FFmpeg |
| Proxy and LUT workflows | Implemented |
| LUT bake-in | Implemented |
| Final Cut Pro handoff | Implemented / improving |
| DaVinci Resolve handoff | Implemented / improving |
| Sparkle update checking | Implemented |
| Slack / Feishu / WeCom webhook notifications | Implemented / improving |
| Project workspace | Implemented / improving |
| Script log / continuity workflow | Implemented |
| Card registry / camera registry | Implemented |
| Scene / shot / take metadata | Implemented / improving |
| Multi-camera take management | Implemented / improving |
| iPad script-log companion workflow | Implemented / improving |
| Local MCP tools for Codex, OpenCode, and compatible AI clients | Beta / guarded |
| Full filmmaking workstation | Current product form |

---

## Core Features

### Local AI Tool Interface (Beta)

The Universal 2 app embeds a local stdio MCP server for compatible AI clients
such as Codex and OpenCode. Its 22 tools cover structured project discovery,
snapshots, storyboard work, production planning, script logging, verified
offload, and verified media conversion.

Agents can write complete storyboard scenes, update/export shooting-day call
sheets, record/export script Takes, run verified camera-card offloads, and
convert media. Long-running jobs return live task state followed by exact
output and report paths. Writes are constrained by explicit allowed roots,
confirmation, idempotency keys, project permissions, field locks, revisions,
local backups, verification, and audit logs.

This is a local tool interface, not a built-in cloud model: it makes no network
requests, and the Agent cannot delete/format source cards or publish unverified
conversion output. Setup and client configuration are documented in
[Tools/MCP/README.md](Tools/MCP/README.md).

---

### Secure Camera Card Offload

321Doit can copy one camera card or source folder to multiple destinations in a single job.

This is useful for small crews that need:

- a working drive
- a backup drive
- an archive drive

Instead of trusting a Finder copy, 321Doit treats offload as a production safety step.

Each offload can generate structured folders, verification records, checksum files, and reports that can be handed to editorial, production, or archive teams.

---

### Multi-Destination Copy

321Doit supports copying from one source to up to three target destinations.

If one destination fails, other destinations can continue depending on the failure condition.

The goal is to reduce the chance that a single drive, cable, port, or connection issue destroys the whole offload job.

---

### Selectable Checksum Verification

321Doit supports multiple checksum algorithms:

- xxHash64
- MD5
- SHA-1
- SHA-256

The selected algorithm is used consistently across verification and reports where applicable.

This allows users to choose between speed-oriented and compatibility-oriented workflows.

---

### Resume and Strict Resume

Interrupted jobs can be resumed through a `session.json` resume manifest.

321Doit also supports strict resume validation.

In strict mode, the app does not simply trust file name, file size, or modification time. It can re-read existing target files and verify their contents before deciding whether a file is safe to skip.

This helps detect cases where a file looks correct from the outside but has been silently changed, corrupted, or partially written.

---

### Preflight Safety Checks

Before starting an offload, 321Doit performs safety checks such as:

- source readability
- target writability
- available disk capacity
- overwrite risk
- same-name card conflicts
- system drive warning
- same physical volume warning
- filesystem limitation checks
- hidden or abnormal file detection
- empty folder awareness
- resumable session detection

The purpose is simple:

> warn before the copy starts, not after the card has already been erased.

---

### Camera Card Detection

321Doit can inspect mounted volumes and infer likely camera card types or source structures.

Current detection logic supports or assists with workflows from:

- Sony
- Canon
- RED
- ARRI
- Blackmagic Design
- GoPro
- Panasonic
- mirrorless / hybrid camera workflows
- non-standard small-crew folder structures

This is especially useful for small teams where cards are not always named cleanly and workflows are not always standardized.

---

### Card Registry and Camera Registry

321Doit includes card and camera registry workflows.

These modules help production teams keep track of:

- camera bodies
- camera cards
- card IDs
- card usage history
- camera-to-card relationships
- source volume identity
- production media ownership
- card reuse risk

The goal is to make media traceability stronger, especially in small crews where card labels, camera assignments, and folder names are often managed manually.

---

### Script Log and Continuity Workflow

321Doit includes script log and continuity workflow support.

The script log workflow is designed to track production information such as:

- scenes
- shots
- takes
- camera angles
- take status
- notes
- continuity information
- production metadata

This allows on-set decisions and observations to travel with the media instead of being trapped in paper notes, screenshots, chat messages, or memory.

---

### Scene / Shot / Take Metadata

321Doit is expanding media management beyond folders and filenames.

The app can manage production metadata around:

- scene numbers
- shot numbers
- take numbers
- multi-camera takes
- circle takes
- false starts
- quick tags
- notes
- camera-specific information

This metadata foundation is important for future editorial handoff, searchable production records, and deeper Final Cut Pro / DaVinci Resolve integration.

---

### Reports and Proof of Copy

321Doit can generate production-friendly verification reports:

- ASC MHL
- PDF
- CSV
- JSON
- TXT
- checksum sidecars

Reports are designed to make the offload auditable and easier to hand over to post-production, producers, assistant editors, or archive teams.

Where supported, PDF reports can also include frame grabs to help identify media visually.

---

### Proxy, Transcode, and LUT Workflow

321Doit includes proxy and transcode workflows for editorial preparation.

Supported directions include:

- H.264
- H.265
- ProRes
- H.266 experimental workflow
- LUT bake-in
- with-LUT and without-LUT proxy variants
- post-production handoff packages

On macOS, 321Doit uses system-native paths where appropriate, including AVFoundation and VideoToolbox. FFmpeg is used for advanced codec, filter, LUT, and professional format workflows.

Core offload features work without FFmpeg.  
Advanced proxy, LUT, frame extraction, and transcoding features may require FFmpeg.

---

### Final Cut Pro and DaVinci Resolve Handoff

321Doit is designed to connect on-set media work with real editorial workflows.

Current and ongoing handoff directions include:

- one-click post-production handoff packages
- Final Cut Pro import workflows
- DaVinci Resolve import workflows
- original/proxy relationship management
- metadata export
- editorial-friendly folder structures
- support for non-ASCII paths and real-world file names

The goal is not only to copy files, but to make the relationship between originals, proxies, reports, card records, script notes, take metadata, and editorial handoff files clear enough for post-production.

---

## Typical Workflow

A current 321Doit workflow may look like this:

```text
1. Create or open a project.
2. Register or confirm camera and card information.
3. Select a camera card or source folder.
4. Confirm detected card information.
5. Choose one to three destination drives.
6. Run preflight checks.
7. Start verified offload.
8. Generate reports and checksums.
9. Generate proxies if needed.
10. Bake LUTs if needed.
11. Record or review scene / shot / take metadata.
12. Optionally sync verified media and script metadata through an NLE integration.
13. Deliver originals, proxies, reports, card records, script notes, and metadata together.
```

---

## Output Structure

A typical Layout v2 offload task looks like this. Each destination stores one original master:

```text
PROJECT_YYYYMMDD_CARD/
├── MEDIA/
│   └── CARD001/
│       ├── [original camera-card tree]
│       └── ascmhl/
├── PROXIES/
├── REPORTS/
├── CHECKSUMS/
└── .321doit/
    ├── session.json
    ├── task.json
    ├── audit.json
    ├── layout-version
    └── app.log
```

Proxies are optional derivatives. Reports and verification live inside the copy tool. The app no longer generates a separate post handoff package; NLE integrations use the stable `task.json` contract. Existing tasks continue using their legacy layout when resumed.

Application-wide diagnostics are stored locally at:

```text
~/Library/Application Support/321Doit/Logs/321Doit-YYYY-MM-DD.log
```

Use **Tools → Open Logs Folder** or **Preferences → Logs & Diagnostics** to reveal them. Daily logs retain 30 days by default and cover app lifecycle, update checks, Turbo Offload, and Media Conversion. Detailed task evidence remains beside each offload at `.321doit/app.log`; conversion evidence remains beside converted output at `.321doit/conversion/<task-id>.json`.

---

## Current Product Structure

321Doit is already a filmmaking workstation connecting creative planning, production, media operations, and post:

```text
Living Storyboard
  → Production Planning
  → Rapid Script Log
  → Turbo Offload
  → Media Conversion
  → Post Handoff
```

Card offload remains the trust foundation.  
Everything else is built around making production information travel safely with the media.

---

## Installation

The app is currently distributed outside the Mac App Store.  
Some builds may be ad-hoc signed instead of Apple Developer ID notarized.

Formal offline installer:

1. Open the DMG.
2. Double-click **Install 321Doit.pkg** and complete the macOS Installer.
3. Launch `321Doit.app` from **Applications**.

The current release channel uses an ad-hoc signature and is not Apple-notarized. The installer clears quarantine from the exact app it installs, but macOS may still block a PKG downloaded manually in a browser. Control-click the PKG and choose **Open**, or use **System Settings → Privacy & Security → Open Anyway** after verifying that the filename and published SHA-256 match the release page.

As a last-resort diagnostic for an app that was copied outside the formal installer:

```sh
xattr -dr com.apple.quarantine /Applications/321Doit.app
```

---

## Optional Dependency: FFmpeg

321Doit can perform core copy and verification without FFmpeg.

FFmpeg is recommended for:

- advanced proxy generation
- H.265 / H.266 workflows
- LUT bake-in
- frame grabs
- professional codec decoding
- ProRes variants through FFmpeg
- workflows involving RAW or less common camera formats

The formal offline installer includes Universal 2 builds of FFmpeg and FFprobe. It preserves an existing native-compatible installation and otherwise uses the copy embedded in 321Doit. Homebrew and network downloads are not required.

For normal local development updates, replace the app directly without rebuilding a DMG:

```sh
./update_app.sh
```

Run `./package.sh` only when producing a formal release installer. 321Doit still prefers an existing FFmpeg installation and supports a custom path in Preferences.

---

## Build From Source

Requirements:

- macOS 13 or later
- Xcode or Xcode Command Line Tools
- Swift
- FFmpeg/FFprobe are bundled by the formal installer; optional for source development

Clone the repository:

```sh
git clone https://github.com/Maoxintao98/321doit.git
cd 321doit
```

Build:

```sh
./build.sh
```

The build script creates a Universal Binary for Apple Silicon and Intel Macs where supported. Ordinary internal builds automatically receive a strictly increasing Build number. The last successful counter is kept under ignored `build/` output, and failed builds do not consume a number.

To reproduce a specific formal artifact, lock the Build explicitly:

```sh
APP_BUILD_OVERRIDE=42 ./build.sh
```

`./update_app.sh` uses the same automatic counter and refuses to replace an installed app with the same version and a non-increasing Build unless rollback testing is explicitly enabled.

---

## Run Tests

Basic test suite:

```sh
./run_tests.sh
```

Rigorous test suite:

```sh
./run_rigorous_tests.sh
```

Current test coverage includes areas such as:

- checksum algorithms
- xxHash64
- ASC MHL layout
- PDF report generation
- output naming
- macOS metadata filtering
- multi-target offload
- strict resume validation
- temporary file cleanup
- handoff rendering
- non-ASCII path handling
- script log behavior
- card registry behavior
- camera registry behavior

---

## Packaging

Package a DMG:

```sh
./package.sh
```

`package.sh` uses the Build embedded in the App for the PKG, DMG filename, signature and appcast. Use `APP_BUILD_OVERRIDE=<number> ./package.sh` when a formal release must be reproducible.

The formal artifact is a DMG wrapper containing one macOS PKG installer. Output:

```text
dist/321Doit-<version>-build<build>-offline-installer.dmg
```

The DMG can be distributed through GitHub Releases, GitHub Pages, websites, AirDrop, or direct sharing.

---

## Auto Update

321Doit includes a Sparkle-compatible update checking mechanism.

The app recognizes a higher Build under the same short version, verifies the Ed25519 enclosure signature, keeps that exact verified DMG in its local cache, clears quarantine only from that verified artifact, and opens it for installation. Download, verification, and installation therefore use the same package. The appcast retains earlier release entries as rollback download points.

---

## Current Limitations

321Doit is still in Beta.

Known limitations:

- The app is currently focused on macOS.
- The app is currently distributed outside the Mac App Store.
- Some builds may be ad-hoc signed rather than Apple Developer ID notarized.
- macOS Gatekeeper may require manual first-launch approval.
- Advanced proxy, LUT, and codec features depend on local FFmpeg capability.
- RAW formats such as R3D, BRAW, ARRIRAW, and CRM depend on local decoding support.
- The iPad script-log companion is implemented and continues to be refined; other mobile companions are not yet available.
- The five-tool workstation is implemented, while cross-module automation and post integrations continue to evolve.
- Always test with non-critical media before using a new version on paid production work.

---

## Why 321Doit Exists

Many small crews still manage production media with Finder, manual folders, spreadsheets, screenshots, paper notes, chat messages, and memory.

That works until something goes wrong.

Professional media safety and production tracking should not be available only to large productions with expensive DIT systems.

321Doit exists for people who need a more reliable workflow but do not have the budget, crew size, or infrastructure of a large studio production.

It is built for:

- independent filmmakers
- documentary teams
- student crews
- small commercial teams
- music video crews
- regional production teams
- solo creators
- anyone who has ever copied a camera card and silently prayed nothing went wrong

---

## Philosophy

321Doit is open source because production tools should be accessible.

A tool for creators should be:

- safe
- transparent
- local-first
- practical
- understandable
- affordable
- respectful of real on-set pressure

No unnecessary cloud lock-in.  
No forced subscription model.  
No pretending small crews do not exist.

---

## About the Name

321Doit means: prepare, check, and do it.

The project began with a simple mission: make camera-card offload safer. Today, the name represents preparing, checking, and carrying the entire filmmaking workflow through—inside one local-first workstation.

---

## Author

Independently developed by **Mao Xintao**.

---

## Open-Source Acknowledgements

Open source makes 321Doit possible. We gratefully acknowledge **FFmpeg /
FFprobe**, **OpenCode**, and the **ascmhl / ASC MHL reference implementation**.

See [Third-Party Open-Source Acknowledgements](THIRD_PARTY_NOTICES.md) for each
project's role, distribution status, source, and license.

---

## License

321Doit is free and open-source software.

Please see the repository license file for details.
