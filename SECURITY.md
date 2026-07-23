# 321Doit Security & Integrity Whitepaper

**Version:** 0.6 · 2026-06-30
**Scope:** This document covers only the Turbo Offload module inside the 321Doit filmmaking workstation. It is not the full product description for Storyboard, Planning, Script Log, or Media Conversion.

**Audience:** DITs, data managers, post-production engineers, archivists who need to understand what 321Doit actually guarantees about a copy.

This document describes the threat model 321Doit was built for, the integrity guarantees it offers, and — explicitly — what it does **not** protect against. We would rather be narrow and honest than broad and vague.

A Chinese translation lives at [SECURITY.zh.md](SECURITY.zh.md).

---

## 1. Threat model

The Turbo Offload module in 321Doit defends against:

- **Storage-side bit rot** during a multi-destination copy (a card or destination drive returns silently corrupted bytes).
- **Partial writes** caused by power loss, eject, or crashed processes (a half-copied file should not look complete).
- **Accidental overwrite** of an earlier card's offload package by a later one with a colliding folder name.
- **Operator error** where one destination drive fails mid-job and the operator does not notice.
- **Verification gaps** where a "copy succeeded" message is shown without the destination actually being read back and compared.

321Doit does **not** defend against:

- **Active tampering by a knowledgeable adversary** with write access to the destination disk. xxHash64 is not a cryptographic hash; an attacker with the manifest in hand can construct a different file with the same hash. SHA-256 mode (preference) does defend against this in the data plane, but the manifest itself is not signed by a trusted authority.
- **Compromised system tools** (ffmpeg, the OS file APIs, the disk firmware). 321Doit assumes the local environment is trusted.
- **Theft or unauthorised copying** of the offload package itself. There is no encryption-at-rest.
- **Audit-grade non-repudiation.** The PDF report has a signature line for ink or third-party digital signatures, but the report is not itself cryptographically signed by 321Doit.

This boundary is intentional. The set-side workflow values speed and simplicity over cryptographic strength. Sites that need stronger guarantees (legal evidence, archival integrity at decade scales) should layer a second tool — for example, ASC MHL v2.0 with C4 chain hashes (which 321Doit emits and the official ASC tool can verify) plus a separate detached signature over the manifest.

---

## 2. Hash algorithms

| Algorithm | Default | Bytes / sec on M-series | Defends bit rot | Defends adversarial collision |
|-----------|---------|--------------------------|------------------|-------------------------------|
| xxHash64  | yes     | multi-GB                 | yes              | **no** (non-cryptographic)    |
| MD5       | opt-in  | hundreds of MB           | yes              | weak (broken)                 |
| SHA-1     | opt-in  | hundreds of MB           | yes              | weak (broken)                 |
| SHA-256   | opt-in  | hundreds of MB           | yes              | yes                           |

**Why xxHash64 is the default.** A DIT's pain point on set is that a 256 GB card multiplied by three destinations is 768 GB to read back during verification, on top of the original write. SHA-256 turns that step into the bottleneck of the whole job; xxHash64 keeps it limited by disk speed. xxHash64 is also the algorithm that Pomfort Silverstack, ShotPut Pro and other shipping DIT tools default to, so 321Doit's manifests are interoperable with that ecosystem.

**When to switch to SHA-256.** Choose SHA-256 in preferences when the offload feeds an archival pipeline (LTO, cold storage, long-term legal hold) where the reduced collision risk justifies the throughput penalty.

**Why not BLAKE3 or xxh3-128.** Both are excellent algorithms. They are not yet first-class citizens in the ASC MHL v2.0 spec, so emitting them would produce manifests that downstream tooling cannot validate. We will revisit if the spec adds them.

---

## 3. Copy and verification flow

For each file, every destination goes through the same five steps:

1. **Open temp.** A unique sibling file `.321doit-copying-<uuid>-<filename>` is opened on the destination volume. This file is never visible to other tools by name and is collected at boot or job start if a previous run crashed.
2. **Stream write.** Bytes are read from the source once and fanned out to every destination in parallel. The 1 MiB default buffer is configurable in preferences.
3. **Hash.** The chosen algorithm hashes the source stream as bytes flow through. The source is read **once** per file, regardless of destination count.
4. **Verify on read-back.** After the temp file is closed, 321Doit re-opens it on the destination and re-hashes from disk. This catches storage that lied about a successful write — a real failure mode on consumer SSDs and worn cards.
5. **Atomic rename.** Only on a hash match does the temp file `rename(2)` to its final name. A crash before this point leaves the orphaned temp; the final name never appears.

If verification fails on a given destination, that destination is marked failed; the other destinations continue. The manifest written for the failed destination records the mismatch explicitly.

---

## 4. Anti-overwrite policy

The output folder is constructed deterministically as `<PROJECT>_<YYYYMMDD>_<CARD>` (with optional editorial-delivery suffix). If that folder already exists on the destination, 321Doit refuses the job with `OffloadError.duplicateOutput` rather than merging or overwriting.

Rationale: a silent merge between two offloads of different cards is impossible to recover from after the fact. Forcing the operator to either rename the new card or move the old folder out of the way is a deliberate friction point.

The check is per-destination, so a job that finds a collision on one drive but not another will fail only the colliding destination.

---

## 5. ASC MHL v2.0 compliance

321Doit emits an ASC MHL v2.0 generation under `<offload>/ascmhl/` per the namespace `urn:ASC:MHL:v2.0`. The chain manifest under the same folder includes a C4 (Cinema Content Creation Cloud) ID hash of each generation file, computed as base58-encoded SHA-512 of the .mhl with the C4 alphabet padded to 88 characters.

This means a third party — your archive, your post house, the next DIT — can verify the offload with the official Python tool from ASC:

```sh
pip install ascmhl

# Manifest schema + chain hash. Catches structural manifest tampering.
ascmhl info  /Volumes/Backup/PROJECT_YYYYMMDD_CARD

# File-set integrity (added / missing files). Does NOT re-hash content
# in the 1.2 release — see note below.
ascmhl diff  /Volumes/Backup/PROJECT_YYYYMMDD_CARD

# Bit-rot detection: re-hashes every file and prints
# "ERROR: hash mismatch …" on stderr if any file changed since the
# manifest was written. Exits non-zero on mismatch.
ascmhl create -v -h xxh64 /Volumes/Backup/PROJECT_YYYYMMDD_CARD
```

In ascmhl 1.2 the documented `verify` subcommand is not yet shipping; `ascmhl create -v` is the actual hash-content verifier (it builds a fresh generation and reports per-file hash mismatches against the previous one). 321Doit's release smoke test runs `ascmhl info` + `ascmhl diff` against a freshly-built mock offload — that catches every schema regression and the file-set, but does **not** catch bit-rot of the offloaded content. For bit-rot detection on a real card after offload, run `ascmhl create -v` manually as shown above.

321Doit's *internal* offload flow does verify file content during copy: every destination is read back from disk and hashed against the source before the rename step (see "Copy and verification flow" above). The official tool is the third-party check on the manifest, not on the copy step.

The ignore list in the manifest covers 321Doit's own report and workflow side-cars (`03_REPORTS/`, `04_CHECKSUMS/`, `_321Doit/`, transcoded folders) so that adding a PDF report to the package after the fact does not invalidate the manifest.

---

## 6. Reports

Every offload writes a PDF report alongside the MHL. The report includes:

- A "Generated by 321Doit v0.x" stamp on the title page and again in every page footer.
- A **Manifest Integrity** block listing the SHA-256 of the .mhl file. This lets an auditor downstream confirm that the manifest they hold has not been edited since the offload.
- An **Operator Sign-off** block with name and a blank signature/date line, designed to be signed in ink on a printed copy or overlaid with a digital signature using Preview / Adobe Acrobat. 321Doit does **not** itself embed a PKCS#7 signature into the PDF — that would require shipping or generating an X.509 certificate, which is out of scope for the current version.

---

## 7. Code-signing posture

321Doit ships **ad-hoc code-signed**. We have not paid for an Apple Developer ID, so the .app and .dmg do not carry a Team ID and are not Apple-notarized. macOS Gatekeeper will warn the first time a user opens the app on a new Mac. The README documents the right-click → Open workflow and, where necessary, `xattr -dr com.apple.quarantine`.

Implications for users:

- **You should verify the SHA-256 of the .dmg against the value published in the GitHub Release** before opening it. Ad-hoc signing means there is no chain of trust back to Apple.
- **Auto-update (Sparkle) uses an EdDSA signature on the appcast** that is independent of Apple's signing infrastructure, so update authenticity is protected even though install authenticity is not.
- A future paid-developer release will fold the same binary under a notarized signature with no functional change to MHL or PDF output.

---

## 8. Known limitations

- **No resume mode for partially-failed cards.** A failed card must be rerun. Partial state in `_321Doit/session.json` is read by the engine to skip already-verified files, so a rerun is not a full re-copy.
- **R3D / BRAW / ARRIRAW / CRM transcoding** depends on the locally installed ffmpeg build's codec support. 321Doit does not ship ffmpeg.
- **No App Store sandbox.** The app reads and writes anywhere the user has access. Removing the app removes only the bundle, not previous offloads.
- **No encryption at rest.** Offload packages are plaintext on the destination disk.

---

## 9. Reporting a security issue

For security-sensitive bug reports — cryptographic mistakes, data loss paths, ways to defeat the anti-overwrite check — please open a private security advisory on GitHub rather than a public issue. Non-sensitive bugs and feature requests can go to the issue tracker as usual.
