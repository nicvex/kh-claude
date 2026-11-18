#!/bin/bash
# kh-claude – Claude Code on KeyHelp Debian servers (unofficial community project)
# https://github.com/nicvex/kh-claude
# Run as root. Safe to run again (idempotent).
# Usage: bash install.sh [keyhelp-user]   (default: saved user, else "user")
set -euo pipefail

KHC_VERSION="1.0.1"
KHC_BASE="https://nicvex.github.io/kh-claude"
KHC_RAW="https://raw.githubusercontent.com/nicvex/kh-claude"
KHC_CONF="/etc/kh-claude.conf"
KHC_SHARE="/usr/local/share/kh-claude"

CONF_USER=""
[ -f "$KHC_CONF" ] && CONF_USER="$(. "$KHC_CONF"; echo "${KH_USER:-}")"
KH_USER="${1:-${CONF_USER:-user}}"
echo "==> kh-claude $KHC_VERSION for KeyHelp user '$KH_USER'"
WWW="/home/users/$KH_USER/www"
FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }
id "$KH_USER" >/dev/null 2>&1 || { echo "User '$KH_USER' not found"; exit 1; }
[ -d "$WWW" ] || { echo "$WWW not found"; exit 1; }

echo "==> Installing Claude Code (apt)"
apt-get update -q
apt-get install -y -q curl gnupg tmux jq
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc
GOT=$(gpg --show-keys --with-colons /etc/apt/keyrings/claude-code.asc | awk -F: '/^fpr/{print $10; exit}')
[ "$GOT" = "$FPR" ] || { echo "Key fingerprint mismatch: $GOT"; rm -f /etc/apt/keyrings/claude-code.asc; exit 1; }
echo "deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
  > /etc/apt/sources.list.d/claude-code.list
apt-get update -q
apt-get install -y -q claude-code
/usr/bin/claude --version

echo "==> Writing $WWW/CLAUDE.md"
[ -f "$WWW/CLAUDE.md" ] && cp "$WWW/CLAUDE.md" "$WWW/CLAUDE.md.bak"
cat > "$WWW/CLAUDE.md" <<EOF
# Server context

This is a Debian server ($(hostname -f)) administrated with **KeyHelp** (hosting control panel).
You are running as the unprivileged KeyHelp user \`$KH_USER\`, not root. The only allowed sudo command is \`kh-fixowner\` (see below).

## Layout

- \`/home/users/$KH_USER/www/\` – this directory. **Every subfolder is a separate, independent project/website** (except \`claude-backups/\`).
- \`/home/users/$KH_USER/www/claude-backups/\` – backups of everything you change. Not a project; never edit or list it as one.
- \`/home/users/$KH_USER/logs/\` – web server / PHP logs (read these when debugging)
- \`/home/users/$KH_USER/tmp/\` – temp files

## Rules

- Before changing anything, make clear **which project** you are working in. Never edit files across several projects in one task unless asked.
- If a project has its own \`CLAUDE.md\`, follow it.
- Projects may use different PHP versions, frameworks and databases. Check each project's files (composer.json, package.json, .env, wp-config.php, …) instead of assuming.
- Server-level settings are managed **in the KeyHelp panel**, not by files: vhosts/Apache/Nginx, PHP version and php.ini values, PHP-FPM, SSL certificates, cron jobs, databases, email, DNS, FTP. Don't try to change these; tell me what to set in KeyHelp instead.
- Never print or commit secrets (.env, DB passwords, wp-config.php credentials).
- Don't delete files or databases without asking.

## Backups (keep projects clean)

- **Never** create backup copies (.bak, .old, copies) inside a project folder.
- Edit/Write tool changes are backed up automatically to \`claude-backups/<project>/<date>_<session>/files/\`.
- Before changing or deleting files **via shell** (rm, mv, sed -i, unzip over files, git checkout, composer/npm that overwrite files …), first run \`kh-backup <path>…\` for the affected files or folders.
- New files are recorded in \`NEW.txt\` of the backup folder, all actions in \`MANIFEST.txt\`.
- These are live websites: avoid long-running or heavy commands without asking.

## Project memory

- Every project has its memory file at \`claude-backups/<project>/MEMORY.md\` (outside the project, so the project stays clean). Built-in auto memory is off; use only these files.
- Started inside a project, its MEMORY.md and the last file changes are loaded automatically. Started in www/, you get an index: **read the project's MEMORY.md before working on it.**
- After every completed step (not every tiny edit) update MEMORY.md with the Edit tool:
  - Changelog entry at the top: \`YYYY-MM-DD HH:MM – what & why – files – backup folder\`
  - Structure, Notes/gotchas, Open tasks: update when you learn something useful for next time.
  - Fill in the one-line \`>\` description if it's still a placeholder.
- Keep it short (max ~150 lines). Move changelog entries beyond the newest 30 to \`MEMORY-archive.md\` in the same folder.

## Root-owned files

- If a file in www/ can't be edited because it's owned by root, run \`sudo /usr/local/sbin/kh-fixowner <path>\`. It only works inside \`$WWW\`.
- Anything else that needs root: don't try workarounds. Print the exact command and I'll run it myself as root.

## Databases

- Database credentials are in each project's config (.env, wp-config.php, …). Use the \`mysql\` / \`mysqldump\` clients with them; don't print the passwords.
- Read-only queries (SELECT, SHOW, DESCRIBE) are fine.
- Before any write (UPDATE, DELETE, ALTER, DROP, imports), make a dump with \`mysqldump\` into \`$WWW/claude-backups/<project>/db/<YYYY-MM-DD_HH-MM>_<dbname>.sql\` and ask me first.
- Creating databases or DB users is done in KeyHelp, not by you.

## Overview

When I ask for an overview, list each project folder with: type/framework, PHP/Node version hints, git status, and anything that looks broken or outdated.
EOF
chown "$KH_USER": "$WWW/CLAUDE.md"
chmod 640 "$WWW/CLAUDE.md"

echo "==> Installing launcher /usr/local/bin/claude-kh"
cat > /usr/local/bin/claude-kh <<'EOF'
#!/bin/bash
# Start Claude Code always as the KeyHelp user.
# Usage: claude-kh [project-folder]
set -e
U="__KH_USER__"
DIR="/home/users/$U/www${1:+/$1}"
[ -d "$DIR" ] || { echo "Not found: $DIR"; exit 1; }
# Always run inside tmux: reattach if the session exists, else create it
if [ -z "${TMUX:-}" ]; then
  if [ "$(id -u)" -eq 0 ] && [ -x /usr/local/bin/kh-claude-update ]; then
    MSG="$(timeout 6 /usr/local/bin/kh-claude-update --check 2>/dev/null || true)"
    [ -n "$MSG" ] && { echo "$MSG"; sleep 3; }
  fi
  S="claude${1:+-${1//[.:]/_}}"
  exec tmux new-session -A -s "$S" "$0" "$@"
fi
if [ "$(id -un)" = "$U" ]; then
  cd "$DIR" && exec /usr/bin/claude
fi
exec sudo -u "$U" -H bash -c "cd '$DIR' && exec /usr/bin/claude"
EOF
sed -i "s/__KH_USER__/$KH_USER/" /usr/local/bin/claude-kh
chmod 0755 /usr/local/bin/claude-kh

echo "==> Installing /usr/local/sbin/kh-fixowner (+ sudoers rule)"
cat > /usr/local/sbin/kh-fixowner <<'EOF'
#!/bin/bash
# Give root-owned files inside www/ back to the KeyHelp user. Nothing else.
set -euo pipefail
U="__KH_USER__"
BASE="/home/users/$U/www"
G="$(id -gn "$U")"
[ $# -ge 1 ] || { echo "Usage: kh-fixowner <path>..."; exit 1; }
for p in "$@"; do
  r="$(realpath -e -- "$p")"
  case "$r" in "$BASE"/*) ;; *) echo "Refused (outside $BASE): $r"; exit 1;; esac
  chown -R -h -P "$U:$G" -- "$r"
  echo "Fixed: $r"
done
EOF
sed -i "s/__KH_USER__/$KH_USER/" /usr/local/sbin/kh-fixowner
chmod 0755 /usr/local/sbin/kh-fixowner
echo "$KH_USER ALL=(root) NOPASSWD: /usr/local/sbin/kh-fixowner" > /etc/sudoers.d/kh-fixowner
chmod 0440 /etc/sudoers.d/kh-fixowner
visudo -cf /etc/sudoers.d/kh-fixowner

echo "==> Installing /usr/local/bin/kh-backup + $WWW/claude-backups"
install -d -o "$KH_USER" -g "$(id -gn "$KH_USER")" -m 0700 "$WWW/claude-backups"
cat > /usr/local/bin/kh-backup <<'EOF'
#!/bin/bash
# Back up files before Claude changes them -> www/claude-backups/<project>/<date>_<session>/
#   kh-backup <path>...   manual (before rm, mv, sed -i, ...)
#   kh-backup --hook      Claude Code PreToolUse hook (JSON on stdin)
set -uo pipefail
WWW="/home/users/__KH_USER__/www"
BK="$WWW/claude-backups"
STATE="$HOME/.claude/kh-backup-session"

sess_dir() {   # $1 = project -> prints backup folder of the current session
  local sid d
  sid="$(cat "$STATE" 2>/dev/null || echo "manual")"
  d="$(ls -d "$BK/$1/"*"_$sid" 2>/dev/null | head -n1)"
  if [ -z "$d" ]; then d="$BK/$1/$(date +%Y-%m-%d_%H-%M)_$sid"; mkdir -p "$d/files"; fi
  echo "$d"
}

backup_one() {   # $1 = path, $2 = label
  [ -n "${1:-}" ] || return 0
  local abs rel proj d
  abs="$(realpath -m -- "$1")"
  case "$abs" in "$BK"|"$BK"/*) return 0;; "$WWW"/*) ;; *) return 0;; esac
  if [ -d "$abs" ] && [ ! -L "$abs" ]; then
    find "$abs" \( -type f -o -type l \) -print0 | while IFS= read -r -d '' f; do backup_one "$f" "$2"; done
    return 0
  fi
  rel="${abs#"$WWW"/}"
  case "$rel" in */*) proj="${rel%%/*}"; rel="${rel#*/}";; *) proj="_www";; esac
  d="$(sess_dir "$proj")"
  if [ -e "$abs" ] || [ -L "$abs" ]; then
    [ -e "$d/files/$rel" ] || [ -L "$d/files/$rel" ] && return 0   # keep first (original) state only
    mkdir -p "$d/files/$(dirname -- "$rel")"
    cp -a -- "$abs" "$d/files/$rel" && echo "$(date '+%F %T')  $2  $rel" >> "$d/MANIFEST.txt"
  else
    grep -qxF -- "$rel" "$d/NEW.txt" 2>/dev/null && return 0
    echo "$rel" >> "$d/NEW.txt"
    echo "$(date '+%F %T')  NEW  $rel" >> "$d/MANIFEST.txt"
  fi
}

if [ "${1:-}" = "--hook" ]; then
  IN="$(cat)"
  SID="$(jq -r '.session_id // empty' <<<"$IN" | cut -c1-8)"
  [ -n "$SID" ] && echo "$SID" > "$STATE"
  case "$(jq -r '.tool_name // empty' <<<"$IN")" in
    Edit|MultiEdit) backup_one "$(jq -r '.tool_input.file_path // empty' <<<"$IN")" EDIT ;;
    Write)          backup_one "$(jq -r '.tool_input.file_path // empty' <<<"$IN")" WRITE ;;
    NotebookEdit)   backup_one "$(jq -r '.tool_input.notebook_path // empty' <<<"$IN")" EDIT ;;
  esac
  exit 0   # never block Claude
fi

[ $# -ge 1 ] || { echo "Usage: kh-backup <path>..."; exit 1; }
for p in "$@"; do backup_one "$p" SHELL; echo "Backed up: $p"; done
EOF
sed -i "s/__KH_USER__/$KH_USER/" /usr/local/bin/kh-backup
chmod 0755 /usr/local/bin/kh-backup

echo "==> Installing /usr/local/bin/kh-memory (project memory loader)"
cat > /usr/local/bin/kh-memory <<'EOF'
#!/bin/bash
# SessionStart hook: load claude-backups/<project>/MEMORY.md into Claude's context.
set -uo pipefail
WWW="/home/users/__KH_USER__/www"
BK="$WWW/claude-backups"
IN="$(cat)"
CWD="$(jq -r '.cwd // empty' <<<"$IN" 2>/dev/null)"
CWD="$(realpath -m -- "${CWD:-$PWD}")"

if [ "$CWD" = "$WWW" ]; then
  echo "## Project memory index (claude-backups/<project>/MEMORY.md)"
  for m in "$BK"/*/MEMORY.md; do
    [ -f "$m" ] || continue
    p="$(basename "$(dirname "$m")")"
    echo "- $p: $(grep -m1 '^>' "$m" | sed 's/^> *//') (updated $(date -r "$m" '+%F %H:%M'))"
  done
  echo "Read a project's MEMORY.md before working on it."
  exit 0
fi
case "$CWD" in "$WWW"/*) ;; *) exit 0;; esac
P="${CWD#"$WWW"/}"; P="${P%%/*}"
[ "$P" = "claude-backups" ] && exit 0
M="$BK/$P/MEMORY.md"
mkdir -p "$BK/$P"
[ -f "$M" ] || cat > "$M" <<EOT
# $P
> (short description – fill in)

## Structure

## Notes / gotchas

## Open tasks

## Changelog (newest first)
EOT
echo "## Project memory: $M"
head -n 300 "$M"
L="$(ls -1d "$BK/$P"/20*/ 2>/dev/null | tail -n1)"
if [ -n "$L" ] && [ -f "$L/MANIFEST.txt" ]; then
  echo; echo "## Last file changes ($(basename "$L"))"; tail -n 20 "$L/MANIFEST.txt"
fi
exit 0
EOF
sed -i "s/__KH_USER__/$KH_USER/" /usr/local/bin/kh-memory
chmod 0755 /usr/local/bin/kh-memory

echo "==> Claude settings (ask for sudo + DB, backup + memory hooks)"
UHOME="$(getent passwd "$KH_USER" | cut -d: -f6)"
install -d -o "$KH_USER" -g "$(id -gn "$KH_USER")" -m 0700 "$UHOME/.claude"
[ -f "$UHOME/.claude/settings.json" ] && cp "$UHOME/.claude/settings.json" "$UHOME/.claude/settings.json.bak"
cat > "$UHOME/.claude/settings.json" <<'EOF'
{
  "autoMemoryEnabled": false,
  "permissions": {
    "allow": ["Bash(kh-backup:*)", "Edit(//home/users/__KH_USER__/www/claude-backups/**)"],
    "ask": ["Bash(sudo:*)", "Bash(mysql:*)", "Bash(mysqldump:*)"],
    "additionalDirectories": ["/home/users/__KH_USER__/www/claude-backups"]
  },
  "hooks": {
    "SessionStart": [
      { "hooks": [{ "type": "command", "command": "/usr/local/bin/kh-memory" }] }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|MultiEdit|Write|NotebookEdit|Bash",
        "hooks": [{ "type": "command", "command": "/usr/local/bin/kh-backup --hook" }]
      }
    ]
  }
}
EOF
sed -i "s/__KH_USER__/$KH_USER/g" "$UHOME/.claude/settings.json"
chown "$KH_USER": "$UHOME/.claude/settings.json"

echo "==> Root: 'claude' -> claude-kh (via /usr/local/sbin, only in root's PATH)"
ln -sf /usr/local/bin/claude-kh /usr/local/sbin/claude
sed -i "/alias claude='claude-kh'/d" /root/.bashrc   # old alias no longer needed

echo "==> Config $KHC_CONF"
if [ -f "$KHC_CONF" ]; then
  sed -i "s/^KH_USER=.*/KH_USER=\"$KH_USER\"/" "$KHC_CONF"
else
  cat > "$KHC_CONF" <<EOF
# kh-claude settings
KH_USER="$KH_USER"
CLAUDE_AUTO_UPGRADE="yes"   # daily: upgrade Claude Code from Anthropic's signed apt repo
AUTO_UPDATE="no"            # "yes": install new kh-claude versions automatically (runs as root!)
EOF
fi
chmod 0644 "$KHC_CONF"
install -d -m 0755 "$KHC_SHARE"
echo "$KHC_VERSION" > "$KHC_SHARE/VERSION"
if [ -f "${BASH_SOURCE[0]:-}" ]; then cp "${BASH_SOURCE[0]}" "$KHC_SHARE/install.sh"
else curl -fsSL --max-time 30 "$KHC_BASE/install.sh" -o "$KHC_SHARE/install.sh" || true; fi
rm -f "$KHC_SHARE/.last-check"

echo "==> Installing /usr/local/bin/kh-claude-update"
cat > /usr/local/bin/kh-claude-update <<'EOF'
#!/bin/bash
# kh-claude-update            check, show the changes, ask, install
# kh-claude-update --check    print a notice if GitHub has a newer version (runs on every 'claude' start)
# kh-claude-update --yes      install without asking (daily cron when AUTO_UPDATE="yes")
set -uo pipefail
BASE="__KHC_BASE__"
RAW="__KHC_RAW__"
SHARE="/usr/local/share/kh-claude"
KH_USER="user"; [ -f /etc/kh-claude.conf ] && . /etc/kh-claude.conf
LOCAL="$(cat "$SHARE/VERSION" 2>/dev/null || echo 0)"
remote_version() {   # $1 = timeout; GitHub main branch first, Pages as fallback
  local v
  v="$({ curl -fsS --max-time "${1:-5}" "$RAW/main/VERSION" \
      || curl -fsS --max-time "${1:-5}" "$BASE/VERSION"; } 2>/dev/null | tr -d '[:space:]')"
  [[ "$v" =~ ^[0-9]+(\.[0-9]+)*$ ]] && echo "$v"
}
newer() { [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]; }

if [ "${1:-}" = "--check" ]; then
  R="$(remote_version 4)" || exit 0
  newer "$R" "$LOCAL" && echo "kh-claude update available: $LOCAL -> $R   (run: kh-claude-update)"
  exit 0
fi

[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }
R="$(remote_version)" || { echo "Could not reach GitHub"; exit 1; }
newer "$R" "$LOCAL" || { echo "kh-claude is up to date ($LOCAL)."; exit 0; }
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
curl -fsSL --max-time 30 "$RAW/v$R/install.sh" -o "$TMP" \
  || curl -fsSL --max-time 30 "$RAW/main/install.sh" -o "$TMP" || { echo "Download failed"; exit 1; }
grep -q "^KHC_VERSION=\"$R\"" "$TMP" || { echo "Downloaded installer is not version $R, aborting"; exit 1; }
echo "Update $LOCAL -> $R   Changelog: $BASE/CHANGELOG.md"
if [ "${1:-}" != "--yes" ]; then
  PG="$(command -v less || echo cat)"
  diff -u "$SHARE/install.sh" "$TMP" | "$PG" || true
  read -rp "Install kh-claude $R? [y/N] " a
  case "$a" in y|Y) ;; *) echo "Cancelled."; exit 0;; esac
fi
bash "$TMP" "$KH_USER"
EOF
sed -i -e "s#__KHC_BASE__#$KHC_BASE#" -e "s#__KHC_RAW__#$KHC_RAW#" /usr/local/bin/kh-claude-update
chmod 0755 /usr/local/bin/kh-claude-update

echo "==> Daily job /etc/cron.daily/kh-claude"
cat > /etc/cron.daily/kh-claude <<'EOF'
#!/bin/sh
# kh-claude daily job: upgrade Claude Code, optionally kh-claude itself.
[ -f /etc/kh-claude.conf ] && . /etc/kh-claude.conf
if [ "${CLAUDE_AUTO_UPGRADE:-yes}" = "yes" ]; then
  apt-get update -qq >/dev/null 2>&1
  apt-get install -y -qq --only-upgrade claude-code >/dev/null 2>&1
fi
if [ "${AUTO_UPDATE:-no}" = "yes" ]; then
  /usr/local/bin/kh-claude-update --yes >/var/log/kh-claude-update.log 2>&1
fi
exit 0
EOF
chmod 0755 /etc/cron.daily/kh-claude

echo
echo "Done: kh-claude $KHC_VERSION. Run 'hash -r' (or log in again), then 'claude' (or 'claude <project>')."
echo "First start: log in once per server as $KH_USER (opens a login URL)."
