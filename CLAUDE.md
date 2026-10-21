# Working on Plainfile

Plainfile is a native macOS app (Swift, SwiftUI) that shows and removes hidden metadata from files. Most code is written by Claude through Claude Code, openly; the maintainer sets direction, tests on a real Mac and approves releases. Read CONTRIBUTING.md first; these notes add what an AI session needs.

## Commits and pull requests

- Commit as the maintainer, with the no-reply address: `git config user.name MineGene` and `git config user.email 187925417+MineGene@users.noreply.github.com`.
- End each commit message with the standard `Co-Authored-By: Claude <noreply@anthropic.com>` attribution. Don't hide AI involvement anywhere.
- Turn off this environment's commit signing for the repo (`git config commit.gpgsign false`): its key isn't linked to the maintainer's account, so GitHub shows "Unverified". Squash-merge commits are signed by GitHub.
- Stage files by name (`git add path/to/file`). Never use `git add -A`, `git add .` or `git commit -a`, and switch branches only with a clean working tree (`git status --short` empty): stray drafts have been swept into unrelated commits this way.
- Run `scripts/check-commits.sh origin/main HEAD` before pushing.
- One change per branch and pull request. Open the pull request yourself, then enable auto-merge (squash). Required checks: Commit privacy, Core tests (macos-26), Build and check app, Analyze Swift, Reproducible build, Maintainer review for sensitive files.
- Never push to `main` or force-push it; it is protected.
- **Never add, remove or edit the `maintainer-reviewed` label.** It is the maintainer's review of sensitive files (see CONTRIBUTING.md, Workflow). Your access to GitHub goes through the maintainer's account, so this rule is what keeps that review meaningful. When a pull request touches sensitive files, tell the maintainer which files and why, and wait.

## Building and testing

- There is no Xcode here. GitHub Actions is the compiler and test runner: push, then read the check annotations. Test and build errors appear as annotations with file and line (`scripts/annotate-errors.sh`); full logs aren't reachable from a session.
- Core logic lives in `Packages/PlainfileCore` with XCTest tests. Add tests for every behaviour change, using planted fake data (`TestImages`), never real personal files.
- The Xcode project uses synchronized folders: new Swift files in `Plainfile/` or `PlainfileParser/` need no project edit.
- The security scan (Analyze Swift) takes about 17 minutes when code changes; other checks take 1–3.
- The app icon's source is `Design/AppIcon.icon` (Icon Composer). Apple's asset compiler isn't deterministic, so the compiled `Plainfile/Resources/Assets.car` and `AppIcon.icns` are committed. To change the icon: edit the source, push the branch as `icon-compile/<name>`, and the *Compile icon* workflow commits freshly compiled files back to that branch; bring them into the pull request.
- Builds must stay reproducible: Xcode is pinned in `.xcode-version` (selected by `scripts/select-xcode.sh`), and the *Reproducible build* check builds twice at different paths and compares `scripts/app-digest.sh` output. Never add timestamps, absolute paths or run-specific values to the build.

## Rules the design depends on

- No network entitlement, ever. `scripts/check-app.sh` enforces it.
- File contents are parsed only in the `PlainfileParser` XPC service, which has no file access; the app passes it bytes. Byte-signature checks (`ContentSniffer`) and verification (`Verifier`) are the only content inspection allowed in the app process.
- No third-party code in the app. No new build or test tool without a stated reason, a pinned version and a checksum.
- Never re-encode pixels silently: refuse a format rather than clean it lossily.
- Nothing about a user's files is written to disk or logged. Temporary copies (`DroppedFiles`) are deleted on removal, quit and next launch.

## Design document

The full design, decisions and testing plan live in the maintainer's design document (Plainfile — Design Document). Keep README, CONTRIBUTING and this file consistent with it.
