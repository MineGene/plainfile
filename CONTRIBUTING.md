# Contributing

Thanks for helping. Plainfile is a privacy tool, so the project holds itself to the same standard it asks of files.

## Privacy rules

- **Never commit, attach or paste personal files** — photos, videos, documents or screenshots that show real metadata. Make fresh test files instead, or generate them in tests (see `ScannerTests.swift`).
- **Commit with your GitHub no-reply email.** Turn on *Keep my email addresses private* at [github.com/settings/emails](https://github.com/settings/emails), then:

  ```sh
  git config user.email "<id>+<username>@users.noreply.github.com"
  ```

  The address is shown on that settings page.
- **No attribution or tool trailers** in commit messages. Only `Signed-off-by`, `Co-authored-by` (with a no-reply email), `Fixes`, `Closes`, `Resolves` and `Refs` are allowed.

The *Commit privacy* check enforces the last two on every pull request.

## Workflow

1. Branch from `main`; one change per pull request.
2. Push and open a pull request. CI builds the app, runs the tests, checks entitlements and commit privacy, and runs CodeQL. Nothing needs a Mac except writing code.
3. Pull requests are squash-merged automatically once every required check passes (auto-merge). The maintainer can still review, hold or close any pull request.

`main` is protected: no direct pushes, force pushes or deletions.

## Building locally (optional)

Requires macOS 15+, Apple silicon and Xcode.

```sh
scripts/build-app.sh                 # builds build/Release/Plainfile.app
scripts/check-app.sh build/Release/Plainfile.app
swift test --package-path Packages/PlainfileCore
```

The build uses a pinned, checksum-verified XcodeGen (`scripts/install-xcodegen.sh`); don't replace it with a Homebrew install.

## Rules the code must keep

- The app and the parser service never get a network entitlement. `scripts/check-app.sh` fails the build if one appears.
- File contents are only parsed inside `PlainfileParser`, which has no file-access entitlements. The app passes it bytes.
- **No third-party code in the app.** Use Apple frameworks (ImageIO, AVFoundation, PDFKit, Compression) only.
- Keep build and test tools to a minimum. Any new one needs a stated reason in the pull request, an exact pinned version and a checksum, and must never ship inside the app.
- Nothing about a user's files is written to disk or logged.
- GitHub Actions are pinned to full commit SHAs. Dependabot proposes updates after a 7-day cooldown.

## Releases

In the Actions tab, open **Release › Run workflow**, keep the branch on `main`, and enter the new version (for example `0.2.0`). The run waits for the maintainer's approval, then builds `main`, creates the `v0.2.0` tag and publishes the DMG with its checksum and build attestation.
