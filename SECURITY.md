# Security policy

Plainfile opens files people didn't create, so parser bugs are taken seriously.

## Reporting a vulnerability

Please report privately using GitHub's **[Report a vulnerability](https://github.com/MineGene/plainfile/security/advisories/new)** button (Security tab). Don't open a public issue.

Include the Plainfile version, macOS version, and steps to reproduce. If a crafted file is needed, attach one made for the report — never a real personal file.

## Supported versions

Only the latest release receives fixes. Plainfile can't update itself (it has no network access), so security fixes are clearly marked in release notes.

## Design

- The app and its parser service are sandboxed with no network entitlement; CI fails any build that adds one.
- File contents are parsed only in a separate XPC service with no file-access entitlements.
- Hardened runtime is enabled; no JIT, unsigned memory or library-validation exceptions.
- Parsing has a 30-second time limit per file; a hung parser is cut off rather than blocking the app.
- File attributes are read only if they are known, and only up to 64 KB.
- GitHub Actions are pinned to commit SHAs and the build tool to a checksum-verified release; Dependabot updates them after a 7-day cooldown.
- Releases are built only from commits on `main`, by GitHub Actions, with a public build attestation.
