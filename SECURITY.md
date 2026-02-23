# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x     | Yes       |

## Reporting a Vulnerability

If you discover a security issue, please use [GitHub's private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability) on this repository.

Do not open a public issue for security vulnerabilities.

**Response time:** This project is maintained alongside the author's primary work. Security reports will be prioritized, but initial response may take up to 7 days.

## Scope

motspilot is a local shell script and set of markdown files. It does not handle authentication, network communication, or user data directly. Security concerns most likely relate to:

- Shell script injection via task names or descriptions
- Unintended file operations
- Information leakage through log files or artifacts
