#!/bin/bash
# Script to manage workflow skip-worktree settings

# Workflows to keep deleted (never sync back from upstream)
DELETED_WORKFLOWS=(
  "links_checker.yml"
  "nightly.yml"
  "release.yml"
  "simulator-nightly.yml"
  "split-cluster-bisect.yml"
  "split-cluster-pr.yml"
  "ci-docs.yml"
  "create-release-announce.yml"
  "github-issues-monitor.yml"
  "release-notes-monitor.yml"
)

# Custom workflows to preserve (already in your fork)
CUSTOM_WORKFLOWS=(
  "lark_notify.yml"
)

set_skip_worktree() {
  echo "Setting skip-worktree for deleted workflows..."
  for workflow in "${DELETED_WORKFLOWS[@]}"; do
    workflow_path=".github/workflows/$workflow"
    if [ -f "$workflow_path" ]; then
      echo "Removing and setting skip-worktree for: $workflow"
      rm "$workflow_path"
      git add "$workflow_path"
      git commit -m "Remove $workflow (keeping deleted)"
    fi
    # Set skip-worktree even if file doesn't exist (prevents future restoration)
    git update-index --skip-worktree "$workflow_path" 2>/dev/null || true
  done
}

unset_skip_worktree() {
  echo "Unsetting skip-worktree for all workflows..."
  for workflow in "${DELETED_WORKFLOWS[@]}"; do
    workflow_path=".github/workflows/$workflow"
    git update-index --no-skip-worktree "$workflow_path" 2>/dev/null || true
  done
}

list_skip_worktree() {
  echo "Files with skip-worktree set:"
  git ls-files -v | grep ^S | grep "\.github/workflows/"
}

case "$1" in
  "set")
    set_skip_worktree
    ;;
  "unset")
    unset_skip_worktree
    ;;
  "list")
    list_skip_worktree
    ;;
  *)
    echo "Usage: $0 {set|unset|list}"
    echo "  set    - Set skip-worktree for deleted workflows"
    echo "  unset  - Unset skip-worktree for all workflows"
    echo "  list   - List files with skip-worktree set"
    exit 1
    ;;
esac