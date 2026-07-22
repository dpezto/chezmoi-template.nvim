# Security Policy

## Reporting a Vulnerability

Please report security vulnerabilities privately via
[GitHub's private vulnerability reporting](https://github.com/dpezto/chezmoi-template.nvim/security/advisories/new)
rather than filing a public issue.

Since this is a Neovim plugin (no server component, no secrets handled at
runtime beyond what `chezmoi` itself manages), the main risk surface is:

- Arbitrary code execution via a malicious `.tmpl` file being parsed/rendered
- Supply-chain issues in CI (GitHub Actions dependencies)

Expect an initial response within a few days; this is a solo-maintained project.
