#!/bin/bash
# claude-review: Automated CLAUDE.md maintenance via Claude Code
# Runs through predefined projects, updating each CLAUDE.md with
# incremental git-diff-based reviews.

set -euo pipefail

# === CONFIGURATION ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECTS_FILE="$SCRIPT_DIR/projects.json"
PLIST_LABEL="com.claude-review"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

# Read project directories from projects.json
if [ ! -f "$PROJECTS_FILE" ]; then
  echo "ERROR: $PROJECTS_FILE not found" >&2
  exit 1
fi
PROJECTS=()
while IFS= read -r line; do
  PROJECTS+=("$line")
done < <(python3 -c "import json,sys; [print(p) for p in json.load(open(sys.argv[1]))]" "$PROJECTS_FILE")

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

wait_for_auth() {
  local max_attempts=10
  local delay=30
  for ((i=1; i<=max_attempts; i++)); do
    if claude -p "ping" --max-turns 1 &>/dev/null; then
      log "Auth ready"
      return 0
    fi
    log "Auth not ready (attempt $i/$max_attempts), waiting ${delay}s..."
    sleep "$delay"
  done
  log "ERROR: Auth never became ready after $((max_attempts * delay))s"
  return 1
}

# The prompt sent to Claude Code for each project
REVIEW_PROMPT='You are maintaining this project'\''s CLAUDE.md file. Your job is to keep it as a comprehensive, up-to-date reference covering: project purpose, architecture, tech stack, directory structure, code conventions, key patterns, and best practices.

Look at the bottom of CLAUDE.md for a metadata block like:
<!-- last-review: {timestamp} | {git-commit-hash} -->

If found, run `git log --oneline {hash}..HEAD` to see what changed since the last review. Then use `git diff {hash} HEAD` (or targeted file reads) to understand the changes. Update CLAUDE.md only where the changes warrant it — do not rewrite unchanged sections.

If no metadata block exists, or CLAUDE.md does not exist, do a full project review: read key files (package.json, tsconfig, directory structure, representative source files) and generate a comprehensive CLAUDE.md from scratch.

Before writing or updating CLAUDE.md, check if a `specs/` directory exists in the project root. If it does, read every document in it (recursively). These are product specs, design docs, and other context written by the team. Use them to inform your understanding of the product'\''s purpose, design decisions, and intended behavior. Incorporate relevant product context into the auto-generated overview (e.g. in a "## Product Overview" section) so that future Claude sessions have a solid understanding of what the project is and why it exists.

After updating, replace or append the metadata block at the very bottom:
<!-- last-review: {current_ISO_timestamp} | {current_HEAD_hash} -->

Structure of CLAUDE.md:
- Everything ABOVE the auto-generated section is user-authored content. NEVER modify, reorder, or remove any of it. Treat it as immutable.
- Your auto-generated content MUST be wrapped in clear markers with a visible header, exactly like this:

<!-- AUTO-GENERATED-START -->
# Auto-Generated Project Overview
_This section is automatically maintained by claude-review. Do not edit manually — changes will be overwritten._
_Last reviewed: {timestamp}_

## Architecture
...

## Tech Stack
...

## Directory Structure
...

## Code Conventions
...

## Key Patterns
...

<!-- AUTO-GENERATED-END -->
<!-- last-review: {timestamp} | {git-commit-hash} -->

- If CLAUDE.md already exists with user content but no auto-generated section, APPEND your section at the bottom. Never insert it in the middle of existing content.
- If the auto-generated section already exists, replace ONLY the content between the AUTO-GENERATED-START and AUTO-GENERATED-END markers.
- Keep the auto-generated content concise and scannable (use headers, bullet points).
- If nothing meaningful changed since the last review, just update the metadata timestamp/hash.

Other rules:
- NEVER delete any files. You should only read files and edit/create CLAUDE.md. Do not run rm, unlink, git clean, or any destructive commands.
- NEVER commit, push, or make any git changes. You are read-only except for CLAUDE.md.
- The ONLY file you are allowed to write to or create is CLAUDE.md in the project root.'

review_project() {
  local project_dir="$1"

  if [ ! -d "$project_dir" ]; then
    log "SKIP: $project_dir does not exist"
    return
  fi

  if [ ! -d "$project_dir/.git" ]; then
    log "SKIP: $project_dir is not a git repository"
    return
  fi

  log "REVIEWING: $project_dir"

  # Run Claude Code in print mode with restricted tools
  # --allowedTools: read-only tools + git read commands + write only CLAUDE.md
  # --disallowedTools: block destructive commands as safety net
  if (cd "$project_dir" && claude -p "$REVIEW_PROMPT" \
    --allowedTools "Read,Glob,Grep,Bash(git log *),Bash(git diff *),Bash(git rev-parse *),Bash(git show *),Bash(ls *),Bash(find *),Bash(cat *),Bash(head *),Bash(tail *),Edit(/CLAUDE.md),Write(/CLAUDE.md)" \
    --disallowedTools "Bash(rm *),Bash(rmdir *),Bash(unlink *),Bash(git push *),Bash(git commit *),Bash(git add *),Bash(git reset *),Bash(git clean *),Bash(git checkout *),Bash(git restore *),Bash(git rm *),Bash(git mv *)" \
    ) 2>&1; then
    log "DONE: $project_dir"
    echo ""
  else
    log "ERROR: Failed reviewing $project_dir (exit code $?)"
  fi
}

# === LAUNCHD SETUP ===
ensure_launchd() {
  if [ -f "$PLIST_PATH" ]; then
    return
  fi

  log "Creating launchd plist at $PLIST_PATH"
  cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>open</string>
        <string>${SCRIPT_DIR}/launch-review.command</string>
    </array>
    <key>StartInterval</key>
    <integer>86400</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${SCRIPT_DIR}/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${SCRIPT_DIR}/launchd-stderr.log</string>
</dict>
</plist>
PLIST

  launchctl load "$PLIST_PATH"
  log "Loaded launchd agent: $PLIST_LABEL (runs every 24h)"
}

# === MAIN ===
ensure_launchd

wait_for_auth || exit 1

log "--- Starting review cycle ---"

for project in "${PROJECTS[@]}"; do
  review_project "$project"
done

log "--- Review cycle complete ---"
