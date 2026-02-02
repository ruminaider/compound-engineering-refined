---
name: git-worktree
description: This skill manages Git worktrees for isolated parallel development. It handles creating, listing, switching, and cleaning up worktrees with a simple interactive interface, following KISS principles.
---

# Git Worktree Manager

This skill provides a unified interface for managing Git worktrees across your development workflow. Whether you're reviewing PRs in isolation or working on features in parallel, this skill handles all the complexity.

## What This Skill Does

- **Create worktrees** from main branch with clear branch names
- **List worktrees** with current status
- **Switch between worktrees** for parallel work
- **Clean up completed worktrees** automatically
- **Consolidate** worktrees, stashes, and branches with agent-driven audit
- **Interactive confirmations** at each step
- **Automatic .gitignore management** for worktree directory
- **Automatic .env file copying** from main repo to new worktrees

## CRITICAL: Always Use the Manager Script

**NEVER call `git worktree add` directly.** Always use the `worktree-manager.sh` script.

The script handles critical setup that raw git commands don't:
1. Copies `.env`, `.env.local`, `.env.test`, etc. from main repo
2. Ensures `.worktrees` is in `.gitignore`
3. Creates consistent directory structure

```bash
# ✅ CORRECT - Always use the script
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh create feature-name

# ❌ WRONG - Never do this directly
git worktree add .worktrees/feature-name -b feature-name main
```

## When to Use This Skill

Use this skill in these scenarios:

1. **Code Review (`/workflows:review`)**: If NOT already on the PR branch, offer worktree for isolated review
2. **Feature Work (`/workflows:work`)**: Always ask if user wants parallel worktree or live branch work
3. **Parallel Development**: When working on multiple features simultaneously
4. **Cleanup**: After completing work in a worktree
5. **Consolidate**: Periodic audit of all worktrees, stashes, and stale branches

## How to Use

### In Claude Code Workflows

The skill is automatically called from `/workflows:review` and `/workflows:work` commands:

```
# For review: offers worktree if not on PR branch
# For work: always asks - new branch or worktree?
```

### Manual Usage

You can also invoke the skill directly from bash:

```bash
# Create a new worktree (copies .env files automatically)
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh create feature-login

# List all worktrees
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh list

# Switch to a worktree
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh switch feature-login

# Copy .env files to an existing worktree (if they weren't copied)
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh copy-env feature-login

# Clean up completed worktrees
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

## Commands

### `create <branch-name> [from-branch]`

Creates a new worktree with the given branch name.

**Options:**
- `branch-name` (required): The name for the new branch and worktree
- `from-branch` (optional): Base branch to create from (defaults to `main`)

**Example:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh create feature-login
```

**What happens:**
1. Checks if worktree already exists
2. Updates the base branch from remote
3. Creates new worktree and branch
4. **Copies all .env files from main repo** (.env, .env.local, .env.test, etc.)
5. Shows path for cd-ing to the worktree

### `list` or `ls`

Lists all available worktrees with their branches and current status.

**Example:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh list
```

**Output shows:**
- Worktree name
- Branch name
- Which is current (marked with ✓)
- Main repo status

### `switch <name>` or `go <name>`

Switches to an existing worktree and cd's into it.

**Example:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh switch feature-login
```

**Optional:**
- If name not provided, lists available worktrees and prompts for selection

### `cleanup` or `clean`

Interactively cleans up inactive worktrees with confirmation.

**Example:**
```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

**What happens:**
1. Lists all inactive worktrees
2. Asks for confirmation
3. Removes selected worktrees
4. Cleans up empty directories

### `consolidate` or `audit`

Performs a thorough audit of all worktrees, stashes, and branches, then interactively cleans up with user confirmation. This is an **agent-driven** command — the script gathers state, then you (Claude) reason through classification and propose actions.

#### How to Run

```bash
# Step 1: Gather state report
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh consolidate
```

The script outputs a structured report with three sections: WORKTREES, STASHES, and BRANCHES. You then classify and act on each item using the methodology below.

#### Phase 1 — Gather State

The `consolidate` subcommand runs all data gathering and outputs a structured report. Parse the three sections:

- **WORKTREES**: path, branch, commit, dirty status, tracking status, PR state
- **STASHES**: index, branch association, message, diff stats
- **BRANCHES**: name, tracking info, status, whether it has a worktree

#### Phase 2 — Classify Each Worktree

For each worktree in the report, classify it:

| Category | Signals | Action |
|---|---|---|
| **Merged & clean** | tracking=`gone`, PR=`MERGED`, dirty=`clean` | Remove worktree + delete branch |
| **Merged with uncommitted changes** | tracking=`gone`, PR=`MERGED`, dirty≠`clean` | Show diff, ask user if obsolete or valuable |
| **Detached HEAD** | branch=`(detached)` | Inspect changes, likely discard unless user wants to preserve |
| **Active with open PR** | PR=`OPEN`, tracking=`up-to-date` or `ahead` | Keep. Optionally pull to latest. |
| **Local-only (no PR, no remote)** | tracking=`no-remote`, PR=`none` | Ask user — likely delete |

For merged branches, verify merge status: `gh pr list --state all --head <branch> --json state,mergedAt`

#### Phase 3 — Classify Stashes

For each stash in the report, classify it:

| Category | Signals | Action |
|---|---|---|
| **Associated with merged branch** | stash branch is merged/gone | Show stats, recommend drop |
| **Associated with active worktree** | stash branch has active worktree | Keep |
| **Temp stash (branch switch)** | message contains "temp stash for branch switch" | Check if content matches committed state, recommend drop |
| **Old main stash** | branch=`main`, stash is old | Recommend drop |
| **Unknown/other** | No clear category | Ask user |

#### Phase 4 — Execute with Confirmation

1. **Present a summary table** of all proposed actions using a single `AskUserQuestion` call:
   ```
   Proposed cleanup actions:
   ┌─────────────────────────┬────────────┬──────────────────────────┐
   │ Item                    │ Action     │ Reason                   │
   ├─────────────────────────┼────────────┼──────────────────────────┤
   │ wt: feature-old         │ REMOVE     │ PR #42 merged, clean     │
   │ stash@{3}               │ DROP       │ On merged branch         │
   │ branch: experiment      │ DELETE     │ Local-only, no PR        │
   │ stash@{0}               │ KEEP       │ Active worktree          │
   └─────────────────────────┴────────────┴──────────────────────────┘
   ```
2. Use `AskUserQuestion` to confirm the batch
3. **Execution order matters:**
   - Drop stashes from highest index to lowest (preserves indices)
   - Remove worktrees before deleting their branches
   - Use `git branch -D` (force) — squash merges don't satisfy `-d`

#### Phase 5 — Clean Up Stale Branches

After worktree/stash cleanup, find remaining stale branches:
- Local branches with `[gone]` remote tracking (remote deleted)
- Local branches with no remote and no PR

Ask user before deleting. Use `git branch -D` for confirmed deletions.

#### Phase 6 — Verify

Run final checks and report:
```bash
git worktree list
git stash list
git branch -vv | grep -E "gone|ahead|behind"
gh pr list --author @me
```

Present a brief "after" summary confirming the cleanup results.

## Workflow Examples

### Code Review with Worktree

```bash
# Claude Code recognizes you're not on the PR branch
# Offers: "Use worktree for isolated review? (y/n)"

# You respond: yes
# Script runs (copies .env files automatically):
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh create pr-123-feature-name

# You're now in isolated worktree for review with all env vars
cd .worktrees/pr-123-feature-name

# After review, return to main:
cd ../..
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

### Parallel Feature Development

```bash
# For first feature (copies .env files):
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh create feature-login

# Later, start second feature (also copies .env files):
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh create feature-notifications

# List what you have:
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh list

# Switch between them as needed:
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh switch feature-login

# Return to main and cleanup when done:
cd .
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

## Key Design Principles

### KISS (Keep It Simple, Stupid)

- **One manager script** handles all worktree operations
- **Simple commands** with sensible defaults
- **Interactive prompts** prevent accidental operations
- **Clear naming** using branch names directly

### Opinionated Defaults

- Worktrees always created from **main** (unless specified)
- Worktrees stored in **.worktrees/** directory
- Branch name becomes worktree name
- **.gitignore** automatically managed

### Safety First

- **Confirms before creating** worktrees
- **Confirms before cleanup** to prevent accidental removal
- **Won't remove current worktree**
- **Clear error messages** for issues

## Integration with Workflows

### `/workflows:review`

Instead of always creating a worktree:

```
1. Check current branch
2. If ALREADY on PR branch → stay there, no worktree needed
3. If DIFFERENT branch → offer worktree:
   "Use worktree for isolated review? (y/n)"
   - yes → call git-worktree skill
   - no → proceed with PR diff on current branch
```

### `/workflows:work`

Always offer choice:

```
1. Ask: "How do you want to work?
   1. New branch on current worktree (live work)
   2. Worktree (parallel work)"

2. If choice 1 → create new branch normally
3. If choice 2 → call git-worktree skill to create from main
```

## Troubleshooting

### "Worktree already exists"

If you see this, the script will ask if you want to switch to it instead.

### "Cannot remove worktree: it is the current worktree"

Switch out of the worktree first (to main repo), then cleanup:

```bash
cd $(git rev-parse --show-toplevel)
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh cleanup
```

### Lost in a worktree?

See where you are:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh list
```

### .env files missing in worktree?

If a worktree was created without .env files (e.g., via raw `git worktree add`), copy them:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh copy-env feature-name
```

Navigate back to main:

```bash
cd $(git rev-parse --show-toplevel)
```

## Technical Details

### Directory Structure

```
.worktrees/
├── feature-login/          # Worktree 1
│   ├── .git
│   ├── app/
│   └── ...
├── feature-notifications/  # Worktree 2
│   ├── .git
│   ├── app/
│   └── ...
└── ...

.gitignore (updated to include .worktrees)
```

### How It Works

- Uses `git worktree add` for isolated environments
- Each worktree has its own branch
- Changes in one worktree don't affect others
- Share git history with main repo
- Can push from any worktree

### Performance

- Worktrees are lightweight (just file system links)
- No repository duplication
- Shared git objects for efficiency
- Much faster than cloning or stashing/switching
