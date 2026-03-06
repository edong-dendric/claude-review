# claude-review

A background process that uses Claude Code to automatically maintain `CLAUDE.md` files across your projects. It runs on a daily loop, reviewing each project's codebase and keeping an up-to-date overview of architecture, tech stack, conventions, and more.

## How it works

1. Reads a list of project directories from `projects.json`
2. For each project, launches Claude Code in non-interactive mode (`-p`)
3. Claude checks `CLAUDE.md` for a `<!-- last-review: ... -->` metadata tag containing the last-reviewed git commit hash
4. If found, Claude diffs only the commits since that hash (incremental review)
5. If not found, Claude does a full project review from scratch
6. Claude writes/updates the auto-generated section of `CLAUDE.md`, preserving any manually-written content above it
7. After all projects are reviewed, sleeps for 24 hours and repeats

If a `specs/` directory exists in a project, Claude reads all docs in it to understand product context and design decisions.

## Setup

### 1. Configure your projects

Edit `projects.json` with absolute paths to your git repositories:

```json
[
  "/Users/you/projects/my-app",
  "/Users/you/projects/another-app"
]
```

### 2. Run manually

```bash
./launch-review.command
```

Or from anywhere:

```bash
open /path/to/claude-review/launch-review.command
```

### 3. Run on login (optional)

To have it start automatically when you log in:

1. Open **System Settings > General > Login Items & Extensions**
2. Click **+** under "Open at Login"
3. Select `launch-review.command`

This opens a Terminal window on login so you can see progress.

## Files

| File | Purpose |
|------|---------|
| `projects.json` | List of project directories to review |
| `review-projects.sh` | Main script — loop, permissions, and Claude prompt |
| `launch-review.command` | Double-clickable wrapper that opens in Terminal.app |

## CLAUDE.md structure

The script preserves any content you've written manually at the top of `CLAUDE.md`. Auto-generated content is clearly separated:

```markdown
# Your manually-written rules, conventions, etc.
(untouched by claude-review)

<!-- AUTO-GENERATED-START -->
# Auto-Generated Project Overview
_This section is automatically maintained by claude-review. Do not edit manually._

## Product Overview
## Architecture
## Tech Stack
## Directory Structure
## Code Conventions
## Key Patterns
<!-- AUTO-GENERATED-END -->
<!-- last-review: 2026-03-05T18:00:00Z | abc1234 -->
```

## Permissions

Claude runs with restricted tool access:

- **Allowed:** Read, Glob, Grep, read-only git commands (`git log`, `git diff`, `git show`, `git rev-parse`), basic file inspection (`ls`, `find`, `cat`, `head`, `tail`), and Edit/Write limited to `CLAUDE.md` only
- **Blocked:** `rm`, `rmdir`, `unlink`, `git push`, `git commit`, `git add`, `git reset`, `git clean`, `git checkout`, `git restore`, `git rm`, `git mv`

Claude cannot delete files, modify source code, or make any git changes.
