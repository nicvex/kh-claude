# Changelog

## 1.0.1 – 2026-11-18

- Update check now runs on every `claude` start (was once a day) and asks GitHub directly (Pages as fallback)
- `kh-claude-update` downloads the installer from the matching release tag

## 1.0.0 – 2026-11-18

First public release.

- Installs Claude Code from Anthropic's signed apt repository (fingerprint checked)
- `claude` for root always starts as the KeyHelp user, inside tmux (reattach after disconnect)
- Server context in `www/CLAUDE.md` (KeyHelp rules, one folder = one project)
- Automatic backups of changed, deleted and new files to `www/claude-backups/<project>/<date>_<session>/`
- Per-project memory `claude-backups/<project>/MEMORY.md`, loaded at session start
- `kh-fixowner`: give root-owned files in www/ back to the user (asks first)
- Database rules: read freely, dump and ask before writing
- Update check on start, `kh-claude-update`, daily Claude Code upgrade
