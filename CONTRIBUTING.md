# Contributing

Thanks for helping. Plainfile is a privacy tool, so the project holds itself to the same standard it asks of files.

## Privacy rules

- **Never commit, attach or paste personal files** — photos, videos, documents or screenshots that show real metadata. Make fresh test files instead, or generate them in tests (see `ScannerTests.swift`).
- **Commit with your GitHub no-reply email.** Turn on *Keep my email addresses private* at [github.com/settings/emails](https://github.com/settings/emails), then:

  ```sh
  git config user.email "<id>+<username>@users.noreply.github.com"
  ```

  The address is shown on that settings page.
- **Say when AI wrote it.** Much of Plainfile is written by Claude through Claude Code, and that's stated openly. If an AI tool wrote or substantially shaped your change, say so in the pull request and add a `Co-authored-by:` line for it.
- Commit trailers are limited to `Signed-off-by`, `Co-authored-by`, `Fixes`, `Closes`, `Resolves`, `Refs` and `Claude-Session`. Any email in them must be a GitHub no-reply address or `noreply@anthropic.com`.

The *Commit privacy* check enforces the email and trailer rules on every pull request.

## Workflow

1. Branch from `main`; one change per pull request.
2. Push and open a pull request. CI builds the app, runs the tests, checks entitlements and commit privacy, and runs CodeQL. Nothing needs a Mac except writing code.
3. Pull requests are squash-merged automatically once every required check passes (auto-merge). The maintainer can still review, hold or close any pull request.
4. **Sensitive files need the maintainer's review.** Changes to permissions (`Config/`), workflows and scripts (`.github/`, `scripts/`), the Xcode project, the isolated file reader (`PlainfileParser/`, `ParserServiceProtocol.swift`), the pinned Xcode version, the compiled icon or `CLAUDE.md` wait until the maintainer adds the `maintainer-reviewed` label. A new push removes the label, so the reviewed version is the one that merges.

`main` is protected: no direct pushes, force pushes or deletions.

## Building locally (optional)

Requires macOS 15+, Apple silicon and Xcode.

```sh
scripts/build-app.sh                 # builds build/Release/Plainfile.app
scripts/check-app.sh build/Release/Plainfile.app
swift test --package-path Packages/PlainfileCore
```

The build uses Xcode only. New Swift files in `Plainfile/` or `PlainfileParser/` are added to the project automatically; entitlements live in `Config/`.

## Rules the code must keep

- The app and the parser service never get a network entitlement. `scripts/check-app.sh` fails the build if one appears.
- File contents are only parsed inside `PlainfileParser`, which has no file-access entitlements. The app passes it bytes.
- **No third-party code in the app.** Use Apple frameworks (ImageIO, AVFoundation, PDFKit, Compression) only.
- Keep build and test tools to a minimum. Any new one needs a stated reason in the pull request, an exact pinned version and a checksum, and must never ship inside the app.
- Nothing about a user's files is written to disk or logged.
- GitHub Actions are pinned to full commit SHAs. Dependabot proposes updates after a 7-day cooldown.

## Testing

Because much of the code is written by an AI, no single check is trusted on its own. Each layer is meant to catch what the others miss:

1. **Unit tests on planted data** (done): fake location, camera and author planted in JPEG, PNG and HEIC, removed, then checked by a fresh scan, a raw-byte search and a pixel comparison.
2. **Verification inside the app** (engine done): every clean is re-scanned, byte-searched and pixel-compared before the original is replaced.
3. **Independent cross-check** (next): ExifTool and mat2 re-examine every cleaned test file on CI.
4. **Real-world sample files** (next): openly licensed files from many devices and apps, pinned by checksum. Never personal files.
5. **Tests for the tests** (next): deliberately broken versions of the cleaner must make the tests fail.
6. **Corrupted-file testing, sanitizers and a coverage floor** (planned).
7. **Interface tests** (with the UI) and **the maintainer's check on a real Mac** before each release.

## Releases

In the Actions tab, open **Release › Run workflow**, keep the branch on `main`, and enter the new version (for example `0.2.0`). The run waits for the maintainer's approval, then builds `main`, creates the `v0.2.0` tag and publishes the DMG with its checksum and build attestation.
