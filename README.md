# Plainfile

See — and soon remove — the hidden information in your files on macOS: where a photo was taken, which device made it, who wrote a document, and the web page you downloaded it from.

Plainfile is free, open source (MIT) and private by design. It has **no network access at all**: macOS's sandbox blocks every connection, so nothing about your files can leave your Mac.

> **Status: early preview (0.1).** This version only *shows* metadata. Nothing is changed. Removing metadata, previewing the result and undo are being built next.

## What it shows today

| Where | What |
| --- | --- |
| Photos (JPEG, HEIC, PNG, TIFF, GIF, WebP and other formats macOS can read) | GPS location, camera make, model and serial numbers, maker notes, dates, author and copyright, editing software, XMP data |
| Any file | Download source (the web address macOS records when you download something), Gatekeeper download flag, Finder tags and comments, file dates, file name |

Items are grouped in plain language (Location, People and authorship, Device, Downloaded from, …) and marked with how much they reveal.

## Install

1. Download the latest `Plainfile-x.y.z.dmg` from [Releases](https://github.com/MineGene/plainfile/releases), open it and drag Plainfile to Applications.
2. Open Plainfile. macOS will say it can't verify the developer. That's expected: Plainfile is free and isn't notarised by Apple.
3. Open **System Settings › Privacy & Security**, scroll down and click **Open Anyway**, then confirm. You only need to do this once per version.

Only download Plainfile from the Releases page above.

**Check your download (optional).** Each release lists a SHA-256 checksum and is built by GitHub from this repository's public source, with a signed record of that build:

```sh
shasum -a 256 Plainfile-x.y.z.dmg
gh attestation verify Plainfile-x.y.z.dmg --repo MineGene/plainfile
```

Requires macOS 15 or later on a Mac with Apple silicon (M1 or later). Intel Macs are not supported.

**Updates:** Plainfile never checks for updates, because it can't go online. Click **Watch › Custom › Releases** on this page to be told about new versions.

## Privacy and security

- **No network access.** The app has no network entitlement, so macOS refuses any connection it might try to make. Every build checks this automatically.
- **No telemetry, analytics, crash reporters or third-party SDKs.**
- **Untrusted files are read in a separate, locked-down process** with no access to your files or the network. If a malicious file ever exploited a bug in the reader, it would be stuck there.
- **Nothing is saved.** What Plainfile finds stays in memory and disappears when you quit.
- **Honest results.** "No metadata found" is never a guarantee. Watermarks, hidden data in pixels and what's visible in a photo can't be removed by any metadata tool.

Found a security problem? Please report it privately — see [SECURITY.md](SECURITY.md).

## How it's built

Native Swift and SwiftUI, using Apple's own frameworks (ImageIO, and soon AVFoundation and PDFKit) instead of third-party parsers.

- `Plainfile/` — the app (SwiftUI window, file handling)
- `PlainfileParser/` — the isolated parser service (XPC)
- `Packages/PlainfileCore/` — scanners and models shared by both, with tests
- `project.yml` — Xcode project definition for [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Everything is built, tested and released by GitHub Actions — no developer hardware involved:

- **CI** (every push, every pull request and weekly): core tests, app build, and a check that the app is sandboxed, has no network entitlement, and the parser has no file access.
- **Commit privacy** check: every commit must use a GitHub no-reply email, with no attribution trailers.
- **CodeQL** security analysis of the Swift code, and **zizmor** audits of the workflows themselves.
- **Pinned tools:** every GitHub Action is pinned to an exact commit, and the build tool (XcodeGen) to a checksum-verified release. Dependabot proposes updates after a 7-day cooldown.
- **Release** (on a `v*` tag, after approval): builds, ad-hoc signs, packages a DMG, attaches a checksum and build attestation, and publishes the release.

To build locally on an Apple-silicon Mac with Xcode: `scripts/build-app.sh`.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md). **Never attach personal photos or documents** to an issue — they contain exactly the metadata this project is about. Make a fresh test file instead.

## Roadmap

1. **Preview (now)** — read-only inspector for images and file attributes.
2. **v1** — remove selected metadata, verify the result, preview before and after, undo until quit; video and audio (MOV, MP4, M4A) and PDF.
3. **v1.1** — Word, Excel and PowerPoint files; MP3/FLAC tags; Finder Quick Action.
4. **v2** — ZIP archives, Pages/Numbers/Keynote, saved presets.

## Licence

MIT — see [LICENSE](LICENSE).
