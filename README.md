# kh-claude

Run [Claude Code](https://code.claude.com) on Debian and Ubuntu servers managed with [KeyHelp](https://www.keyhelp.de), without ever running it as root.

Website: **https://nicvex.github.io/kh-claude/**

> Unofficial community project. Not affiliated with or endorsed by Anthropic or Keyweb AG.

## Install

As root, replace `user` with your KeyHelp username:

```bash
curl -fsSL https://nicvex.github.io/kh-claude/install.sh | bash -s user
```

Then start it:

```bash
hash -r
claude              # all projects in /home/users/user/www
claude shop.de      # straight into one project
```

On the first start, log in once (open the URL it shows in your browser and paste the code back). You need a Claude Pro, Max, Team, Enterprise or Console account.

Prefer a fixed version? Use a release tag instead of the latest:

```bash
curl -fsSL https://raw.githubusercontent.com/nicvex/kh-claude/v1.0.2/install.sh | bash -s user
```

## What it sets up

| Piece | What it does |
|---|---|
| Claude Code | Installed from Anthropic's signed apt repository; the key fingerprint is checked. |
| `claude` (root only) | Always starts Claude as the KeyHelp user, inside tmux. Run it again to reattach after a disconnect. |
| `www/CLAUDE.md` | Tells Claude it's on a KeyHelp server, that every folder is its own project, and what belongs in the panel. |
| Backups | Before Claude changes or deletes a file, the original goes to `www/claude-backups/<project>/<date>_<session>/`. New files are listed in `NEW.txt`. Projects stay clean. |
| Project memory | `claude-backups/<project>/MEMORY.md` holds structure, notes, open tasks and a changelog. It's loaded at session start and updated after each step. |
| `kh-fixowner` | Gives root-owned files inside `www/` back to the user. Claude has to ask you before using it. |
| Databases | Claude reads with the project's own credentials. Before any write it makes a dump and asks. |
| Updates | Update notice when you start `claude`, `kh-claude-update` to install, daily Claude Code upgrade. |

## Folder layout

```
/home/users/user/www/
├── CLAUDE.md
├── shop.de/                      your project, untouched by backups
├── blog.de/
└── claude-backups/
    └── shop.de/
        ├── MEMORY.md
        ├── MEMORY-archive.md
        ├── 2026-11-18_14-02_abcdef12/
        │   ├── files/            originals before the first change
        │   ├── MANIFEST.txt      every action with time
        │   └── NEW.txt           files Claude created
        └── db/                   dumps before database writes
```

## Everyday commands

| Command | |
|---|---|
| `claude` / `claude <project>` | Start or reattach |
| `Ctrl+b` then `d` | Detach, Claude keeps running |
| `tmux ls` | List running sessions |
| `/resume` | Reopen an earlier conversation |
| `kh-claude-update` | Show changes and install a new version |

## Updates

Every time you start `claude`, it checks GitHub for a new kh-claude version and tells you (takes at most a few seconds; if GitHub is unreachable, Claude starts normally). `kh-claude-update` shows the exact diff and asks before installing.

Settings live in `/etc/kh-claude.conf`:

```bash
KH_USER="user"
CLAUDE_AUTO_UPGRADE="yes"   # daily upgrade of Claude Code (signed apt repo)
AUTO_UPDATE="no"            # "yes" installs new kh-claude versions automatically
```

`AUTO_UPDATE="yes"` means your servers run whatever is published here as root, every day. Leave it off unless you control this repository.

## Security model

- Claude runs as the KeyHelp user. It can't touch other users, KeyHelp itself or system files.
- The only root action it can take is `kh-fixowner`, limited to `www/`, and you approve each call.
- `sudo`, `mysql` and `mysqldump` always ask for permission.
- No KeyHelp API access. The panel stays yours.

## Uninstall

```bash
rm -f /usr/local/sbin/claude /usr/local/bin/claude-kh /usr/local/bin/kh-backup \
      /usr/local/bin/kh-memory /usr/local/bin/kh-claude-update /usr/local/sbin/kh-fixowner \
      /etc/sudoers.d/kh-fixowner /etc/cron.daily/kh-claude /etc/kh-claude.conf
rm -rf /usr/local/share/kh-claude
apt remove claude-code        # optional
```

Backups, memory files and `www/CLAUDE.md` are left in place.

## License

MIT
