#!/bin/bash

# Git Worktree Manager
# Handles creating, listing, switching, and cleaning up Git worktrees
# KISS principle: Simple, interactive, opinionated

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get repo root
GIT_ROOT=$(git rev-parse --show-toplevel)
WORKTREE_DIR="$GIT_ROOT/.worktrees"

# Ensure .worktrees is in .gitignore
ensure_gitignore() {
  if ! grep -q "^\.worktrees$" "$GIT_ROOT/.gitignore" 2>/dev/null; then
    echo ".worktrees" >> "$GIT_ROOT/.gitignore"
  fi
}

# Copy .env files from main repo to worktree
copy_env_files() {
  local worktree_path="$1"

  echo -e "${BLUE}Copying environment files...${NC}"

  # Find all .env* files in root (excluding .env.example which should be in git)
  local env_files=()
  for f in "$GIT_ROOT"/.env*; do
    if [[ -f "$f" ]]; then
      local basename=$(basename "$f")
      # Skip .env.example (that's typically committed to git)
      if [[ "$basename" != ".env.example" ]]; then
        env_files+=("$basename")
      fi
    fi
  done

  if [[ ${#env_files[@]} -eq 0 ]]; then
    echo -e "  ${YELLOW}ℹ️  No .env files found in main repository${NC}"
    return
  fi

  local copied=0
  for env_file in "${env_files[@]}"; do
    local source="$GIT_ROOT/$env_file"
    local dest="$worktree_path/$env_file"

    if [[ -f "$dest" ]]; then
      echo -e "  ${YELLOW}⚠️  $env_file already exists, backing up to ${env_file}.backup${NC}"
      cp "$dest" "${dest}.backup"
    fi

    cp "$source" "$dest"
    echo -e "  ${GREEN}✓ Copied $env_file${NC}"
    copied=$((copied + 1))
  done

  echo -e "  ${GREEN}✓ Copied $copied environment file(s)${NC}"
}

# Create a new worktree
create_worktree() {
  local branch_name="$1"
  local from_branch="${2:-main}"

  if [[ -z "$branch_name" ]]; then
    echo -e "${RED}Error: Branch name required${NC}"
    exit 1
  fi

  local worktree_path="$WORKTREE_DIR/$branch_name"

  # Check if worktree already exists
  if [[ -d "$worktree_path" ]]; then
    echo -e "${YELLOW}Worktree already exists at: $worktree_path${NC}"
    echo -e "Switch to it instead? (y/n)"
    read -r response
    if [[ "$response" == "y" ]]; then
      switch_worktree "$branch_name"
    fi
    return
  fi

  echo -e "${BLUE}Creating worktree: $branch_name${NC}"
  echo "  From: $from_branch"
  echo "  Path: $worktree_path"
  echo ""
  echo "Proceed? (y/n)"
  read -r response

  if [[ "$response" != "y" ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    return
  fi

  # Update main branch
  echo -e "${BLUE}Updating $from_branch...${NC}"
  git checkout "$from_branch"
  git pull origin "$from_branch" || true

  # Create worktree
  mkdir -p "$WORKTREE_DIR"
  ensure_gitignore

  echo -e "${BLUE}Creating worktree...${NC}"
  git worktree add -b "$branch_name" "$worktree_path" "$from_branch"

  # Copy environment files
  copy_env_files "$worktree_path"

  echo -e "${GREEN}✓ Worktree created successfully!${NC}"
  echo ""
  echo "To switch to this worktree:"
  echo -e "${BLUE}cd $worktree_path${NC}"
  echo ""
}

# List all worktrees
list_worktrees() {
  echo -e "${BLUE}Available worktrees:${NC}"
  echo ""

  if [[ ! -d "$WORKTREE_DIR" ]]; then
    echo -e "${YELLOW}No worktrees found${NC}"
    return
  fi

  local count=0
  for worktree_path in "$WORKTREE_DIR"/*; do
    if [[ -d "$worktree_path" && -d "$worktree_path/.git" ]]; then
      count=$((count + 1))
      local worktree_name=$(basename "$worktree_path")
      local branch=$(git -C "$worktree_path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

      if [[ "$PWD" == "$worktree_path" ]]; then
        echo -e "${GREEN}✓ $worktree_name${NC} (current) → branch: $branch"
      else
        echo -e "  $worktree_name → branch: $branch"
      fi
    fi
  done

  if [[ $count -eq 0 ]]; then
    echo -e "${YELLOW}No worktrees found${NC}"
  else
    echo ""
    echo -e "${BLUE}Total: $count worktree(s)${NC}"
  fi

  echo ""
  echo -e "${BLUE}Main repository:${NC}"
  local main_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  echo "  Branch: $main_branch"
  echo "  Path: $GIT_ROOT"
}

# Switch to a worktree
switch_worktree() {
  local worktree_name="$1"

  if [[ -z "$worktree_name" ]]; then
    list_worktrees
    echo -e "${BLUE}Switch to which worktree? (enter name)${NC}"
    read -r worktree_name
  fi

  local worktree_path="$WORKTREE_DIR/$worktree_name"

  if [[ ! -d "$worktree_path" ]]; then
    echo -e "${RED}Error: Worktree not found: $worktree_name${NC}"
    echo ""
    list_worktrees
    exit 1
  fi

  echo -e "${GREEN}Switching to worktree: $worktree_name${NC}"
  cd "$worktree_path"
  echo -e "${BLUE}Now in: $(pwd)${NC}"
}

# Copy env files to an existing worktree (or current directory if in a worktree)
copy_env_to_worktree() {
  local worktree_name="$1"
  local worktree_path

  if [[ -z "$worktree_name" ]]; then
    # Check if we're currently in a worktree
    local current_dir=$(pwd)
    if [[ "$current_dir" == "$WORKTREE_DIR"/* ]]; then
      worktree_path="$current_dir"
      worktree_name=$(basename "$worktree_path")
      echo -e "${BLUE}Detected current worktree: $worktree_name${NC}"
    else
      echo -e "${YELLOW}Usage: worktree-manager.sh copy-env [worktree-name]${NC}"
      echo "Or run from within a worktree to copy to current directory"
      list_worktrees
      return 1
    fi
  else
    worktree_path="$WORKTREE_DIR/$worktree_name"

    if [[ ! -d "$worktree_path" ]]; then
      echo -e "${RED}Error: Worktree not found: $worktree_name${NC}"
      list_worktrees
      return 1
    fi
  fi

  copy_env_files "$worktree_path"
  echo ""
}

# Consolidate: gather full state report for agent-driven cleanup
consolidate_report() {
  echo "=== WORKTREES ==="
  echo "PATH | BRANCH | COMMIT | DIRTY | TRACKING | PR_STATUS"

  # Get all worktrees (including external paths)
  while IFS= read -r line; do
    local wt_path wt_branch wt_commit wt_dirty wt_tracking wt_pr_status

    # Parse worktree list --porcelain output
    if [[ "$line" == "worktree "* ]]; then
      wt_path="${line#worktree }"
      wt_branch=""
      wt_commit=""
      wt_dirty="clean"
      wt_tracking=""
      wt_pr_status=""
      continue
    elif [[ "$line" == "HEAD "* ]]; then
      wt_commit="${line#HEAD }"
      wt_commit="${wt_commit:0:8}"
      continue
    elif [[ "$line" == "branch "* ]]; then
      wt_branch="${line#branch refs/heads/}"
      continue
    elif [[ "$line" == "detached" ]]; then
      wt_branch="(detached)"
      continue
    elif [[ "$line" == "bare" ]]; then
      # Skip bare repo entry
      wt_path=""
      continue
    elif [[ -n "$line" ]]; then
      continue
    fi

    # Empty line = end of worktree entry, emit the row
    if [[ -z "$wt_path" ]]; then
      continue
    fi

    # Check dirty status
    if [[ -d "$wt_path" ]]; then
      local status_output
      status_output=$(git -C "$wt_path" status --porcelain 2>/dev/null || echo "")
      if [[ -n "$status_output" ]]; then
        local modified untracked
        modified=$(echo "$status_output" | grep -c "^ M\|^M \|^MM\|^A \|^D \|^ D\|^R " 2>/dev/null | tr -d '[:space:]' || echo "0")
        untracked=$(echo "$status_output" | grep -c "^??" 2>/dev/null | tr -d '[:space:]' || echo "0")
        wt_dirty="dirty(${modified}mod,${untracked}new)"
      fi
    fi

    # Check tracking status
    if [[ "$wt_branch" != "(detached)" && -n "$wt_branch" ]]; then
      local tracking_info
      tracking_info=$(git -C "$wt_path" for-each-ref --format='%(upstream:short) %(upstream:track)' "refs/heads/$wt_branch" 2>/dev/null || echo "")
      if [[ -z "$tracking_info" || "$tracking_info" == " " ]]; then
        wt_tracking="no-remote"
      elif [[ "$tracking_info" == *"[gone]"* ]]; then
        wt_tracking="gone"
      elif [[ "$tracking_info" == *"[ahead"* ]]; then
        wt_tracking="ahead"
      elif [[ "$tracking_info" == *"[behind"* ]]; then
        wt_tracking="behind"
      else
        wt_tracking="up-to-date"
      fi

      # Check PR status via gh
      wt_pr_status=$(gh pr list --state all --head "$wt_branch" --json state,number --jq '.[0] | "\(.state)#\(.number)"' 2>/dev/null || echo "none")
      if [[ -z "$wt_pr_status" || "$wt_pr_status" == "null#null" ]]; then
        wt_pr_status="none"
      fi
    else
      wt_tracking="n/a"
      wt_pr_status="n/a"
    fi

    echo "$wt_path | $wt_branch | $wt_commit | $wt_dirty | $wt_tracking | $wt_pr_status"
    wt_path=""
  done < <(git worktree list --porcelain; echo "")

  echo ""
  echo "=== STASHES ==="
  echo "INDEX | BRANCH | MESSAGE | STAT"

  local stash_count
  stash_count=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$stash_count" -gt 0 ]]; then
    local i=0
    while IFS= read -r stash_line; do
      # Parse stash entry: stash@{N}: WIP on branch: commit msg
      local stash_branch stash_msg
      stash_branch=$(echo "$stash_line" | sed -n 's/^stash@{[0-9]*}: [^:]*on \([^:]*\):.*/\1/p')
      stash_msg=$(echo "$stash_line" | sed 's/^stash@{[0-9]*}: //')

      # Get stash diff stats
      local stash_stat
      stash_stat=$(git stash show "stash@{$i}" --stat 2>/dev/null | tail -1 | sed 's/^ *//' || echo "empty")
      if [[ -z "$stash_stat" ]]; then
        stash_stat="empty"
      fi

      echo "stash@{$i} | $stash_branch | $stash_msg | $stash_stat"
      i=$((i + 1))
    done < <(git stash list 2>/dev/null)
  else
    echo "(no stashes)"
  fi

  echo ""
  echo "=== BRANCHES ==="
  echo "NAME | TRACKING | STATUS | HAS_WORKTREE"

  # Get all worktree branches for cross-reference
  local wt_branches
  wt_branches=$(git worktree list --porcelain | grep "^branch " | sed 's|^branch refs/heads/||')

  while IFS= read -r branch_line; do
    # Parse git branch -vv output
    # Format: * branch  commit [tracking] message
    #   or:   branch  commit [tracking] message
    local is_current=""
    if [[ "$branch_line" == "* "* ]]; then
      is_current="*"
      branch_line="${branch_line:2}"
    else
      branch_line="${branch_line:2}"
    fi

    local br_name br_tracking br_status br_has_wt
    br_name=$(echo "$branch_line" | awk '{print $1}')

    # Extract tracking info from brackets
    if [[ "$branch_line" == *"["*"]"* ]]; then
      br_tracking=$(echo "$branch_line" | sed -n 's/.*\[\([^]]*\)\].*/\1/p')
      if [[ "$br_tracking" == *": gone"* ]]; then
        br_status="gone"
      elif [[ "$br_tracking" == *": ahead"* ]]; then
        br_status="ahead"
      elif [[ "$br_tracking" == *": behind"* ]]; then
        br_status="behind"
      else
        br_status="up-to-date"
      fi
    else
      br_tracking="no-remote"
      br_status="local-only"
    fi

    # Check if branch has a worktree
    if echo "$wt_branches" | grep -qx "$br_name" 2>/dev/null; then
      br_has_wt="yes"
    else
      br_has_wt="no"
    fi

    echo "${is_current}${br_name} | $br_tracking | $br_status | $br_has_wt"
  done < <(git branch -vv 2>/dev/null)
}

# Clean up completed worktrees
cleanup_worktrees() {
  if [[ ! -d "$WORKTREE_DIR" ]]; then
    echo -e "${YELLOW}No worktrees to clean up${NC}"
    return
  fi

  echo -e "${BLUE}Checking for completed worktrees...${NC}"
  echo ""

  local found=0
  local to_remove=()

  for worktree_path in "$WORKTREE_DIR"/*; do
    if [[ -d "$worktree_path" && -d "$worktree_path/.git" ]]; then
      local worktree_name=$(basename "$worktree_path")

      # Skip if current worktree
      if [[ "$PWD" == "$worktree_path" ]]; then
        echo -e "${YELLOW}(skip) $worktree_name - currently active${NC}"
        continue
      fi

      found=$((found + 1))
      to_remove+=("$worktree_path")
      echo -e "${YELLOW}• $worktree_name${NC}"
    fi
  done

  if [[ $found -eq 0 ]]; then
    echo -e "${GREEN}No inactive worktrees to clean up${NC}"
    return
  fi

  echo ""
  echo -e "Remove $found worktree(s)? (y/n)"
  read -r response

  if [[ "$response" != "y" ]]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    return
  fi

  echo -e "${BLUE}Cleaning up worktrees...${NC}"
  for worktree_path in "${to_remove[@]}"; do
    local worktree_name=$(basename "$worktree_path")
    git worktree remove "$worktree_path" --force 2>/dev/null || true
    echo -e "${GREEN}✓ Removed: $worktree_name${NC}"
  done

  # Clean up empty directory if nothing left
  if [[ -z "$(ls -A "$WORKTREE_DIR" 2>/dev/null)" ]]; then
    rmdir "$WORKTREE_DIR" 2>/dev/null || true
  fi

  echo -e "${GREEN}Cleanup complete!${NC}"
}

# Main command handler
main() {
  local command="${1:-list}"

  case "$command" in
    create)
      create_worktree "$2" "$3"
      ;;
    list|ls)
      list_worktrees
      ;;
    switch|go)
      switch_worktree "$2"
      ;;
    copy-env|env)
      copy_env_to_worktree "$2"
      ;;
    cleanup|clean)
      cleanup_worktrees
      ;;
    consolidate|audit)
      consolidate_report
      ;;
    help)
      show_help
      ;;
    *)
      echo -e "${RED}Unknown command: $command${NC}"
      echo ""
      show_help
      exit 1
      ;;
  esac
}

show_help() {
  cat << EOF
Git Worktree Manager

Usage: worktree-manager.sh <command> [options]

Commands:
  create <branch-name> [from-branch]  Create new worktree (copies .env files automatically)
                                      (from-branch defaults to main)
  list | ls                           List all worktrees
  switch | go [name]                  Switch to worktree
  copy-env | env [name]               Copy .env files from main repo to worktree
                                      (if name omitted, uses current worktree)
  cleanup | clean                     Clean up inactive worktrees
  consolidate | audit                 Full state report for agent-driven cleanup
  help                                Show this help message

Environment Files:
  - Automatically copies .env, .env.local, .env.test, etc. on create
  - Skips .env.example (should be in git)
  - Creates .backup files if destination already exists
  - Use 'copy-env' to refresh env files after main repo changes

Examples:
  worktree-manager.sh create feature-login
  worktree-manager.sh create feature-auth develop
  worktree-manager.sh switch feature-login
  worktree-manager.sh copy-env feature-login
  worktree-manager.sh copy-env                   # copies to current worktree
  worktree-manager.sh cleanup
  worktree-manager.sh consolidate                # full audit report
  worktree-manager.sh list

EOF
}

# Run
main "$@"
