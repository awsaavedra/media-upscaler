# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| `main` (latest commit) | ✅ |
| Tagged releases (`v1.0`, `v2.0`, …) | ✅ latest tag only |
| Older tags | ❌ |

Security fixes are applied to `main` and cherry-picked to the most recent tag only.

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Report vulnerabilities privately via **GitHub Security Advisories**:

1. Go to the repository's **Security** tab → **Advisories** → **Report a vulnerability**
2. Describe the issue, affected versions, and reproduction steps
3. You will receive an acknowledgement within **5 business days**

## Disclosure Policy

- Maintainer acknowledges the report and begins triage within 5 business days
- A fix is developed under embargo
- Coordinated disclosure: fix lands in `main`, a GitHub Security Advisory is published, and the reporter is credited (unless they request anonymity)
- CVE assignment is requested if the impact warrants it

## Scope

This project is a **local CLI tool** — it makes no network requests after setup and has no server component. The primary attack surfaces are:

- Shell injection via untrusted file paths passed to the scripts
- Dependency vulnerabilities in the fetched venv (`tools/realesrgan/venv`) — particularly packages used during `setup.sh` download phase (`requests`, `urllib3`, `certifi`)
- Malicious model weights loaded by inference scripts

Out of scope: vulnerabilities in `ffmpeg`, `video2x`, Real-ESRGAN, or other third-party engines — report those to their upstream projects.
