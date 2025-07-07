#!/bin/bash
# Script to protect entire .github/ directory from upstream changes

set_skip_worktree() {
  echo "Setting skip-worktree for entire .github/ directory..."
  
  # Get all files in .github/ directory
  find .github/ -type f | while read -r file; do
    echo "Setting skip-worktree for: $file"
    git update-index --skip-worktree "$file" 2>/dev/null || true
  done
  
  echo "✅ All .github/ files are now protected from upstream changes"
}

unset_skip_worktree() {
  echo "Unsetting skip-worktree for .github/ directory..."
  
  # Get all files in .github/ directory
  find .github/ -type f | while read -r file; do
    echo "Unsetting skip-worktree for: $file"
    git update-index --no-skip-worktree "$file" 2>/dev/null || true
  done
  
  echo "✅ All .github/ files can now be updated from upstream"
}

list_skip_worktree() {
  echo "Files with skip-worktree set in .github/:"
  git ls-files -v | grep ^S | grep "\.github/"
}

protect_upstream_files() {
  echo "Comparing with upstream .github/ directory and protecting differences..."
  
  # Get upstream remote (usually origin)
  upstream_remote=$(git remote | grep -E "^(origin|upstream)$" | head -1)
  if [ -z "$upstream_remote" ]; then
    echo "❌ No upstream remote found"
    return 1
  fi
  
  # Fetch latest from upstream
  echo "Fetching latest from $upstream_remote..."
  git fetch "$upstream_remote" main --quiet
  
  # Get list of files in upstream .github/
  upstream_files=$(git ls-tree -r --name-only "$upstream_remote/main" -- .github/ 2>/dev/null || true)
  
  if [ -z "$upstream_files" ]; then
    echo "No .github/ files found in upstream"
    return 0
  fi
  
  echo "Found upstream .github/ files:"
  echo "$upstream_files"
  echo ""
  
  # Check each upstream file
  echo "$upstream_files" | while read -r file; do
    if [ -n "$file" ]; then
      if [ -f "$file" ]; then
        # File exists locally, set skip-worktree to prevent updates
        echo "Protecting existing file: $file"
        git update-index --skip-worktree "$file" 2>/dev/null || true
      else
        # File doesn't exist locally but exists in upstream
        # Create a dummy file and set skip-worktree to prevent it from being added
        echo "Preventing upstream file from being added: $file"
        mkdir -p "$(dirname "$file")"
        echo "# This file is intentionally blocked from upstream" > "$file"
        git add "$file" 2>/dev/null || true
        git update-index --skip-worktree "$file" 2>/dev/null || true
      fi
    fi
  done
  
  echo "✅ All upstream .github/ files are now protected"
}

auto_protect() {
  echo "Auto-protecting .github/ directory after git operations..."
  
  # First protect against upstream files
  protect_upstream_files
  
  # Install git hooks to auto-protect files
  mkdir -p .git/hooks
  
  # Create post-merge hook
  cat > .git/hooks/post-merge << 'EOF'
#!/bin/bash
# Auto-protect .github/ files after merge
echo "Auto-protecting .github/ files after merge..."
bash scripts/manage-workflows.sh protect-upstream
EOF
  chmod +x .git/hooks/post-merge
  
  # Create post-checkout hook
  cat > .git/hooks/post-checkout << 'EOF'
#!/bin/bash
# Auto-protect .github/ files after checkout
echo "Auto-protecting .github/ files after checkout..."
bash scripts/manage-workflows.sh protect-upstream
EOF
  chmod +x .git/hooks/post-checkout
  
  echo "✅ Auto-protection hooks installed"
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
  "protect-upstream")
    protect_upstream_files
    ;;
  "auto-protect")
    auto_protect
    ;;
  *)
    echo "Usage: $0 {set|unset|list|protect-upstream|auto-protect}"
    echo "  set              - Set skip-worktree for all .github/ files"
    echo "  unset            - Unset skip-worktree for all .github/ files"
    echo "  list             - List files with skip-worktree set"
    echo "  protect-upstream - Compare with upstream and protect all .github/ differences"
    echo "  auto-protect     - Set up automatic protection with git hooks"
    exit 1
    ;;
esac