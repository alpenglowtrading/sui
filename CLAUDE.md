# CLAUDE.md - Keep under 300 tokens

## Essential File Paths
- GitHub Actions: `.github/workflows/lark_notify.yml`
- Lark notification script: `.github/scripts/lark_notify.sh`

## Recent Work Done
- Fixed missing `check_all_workflows_complete` function in lark_notify.sh:343
- Removed unnecessary comment about workflow completion logic
- Cleaned up workflow completion handling for success/cancelled/skipped/neutral statuses

## Key Patterns
- Workflow notification failures usually in lark_notify.sh
- Script uses functions for JSON card creation and webhook calls
- Exit codes: 0 for success/skip, 1 for failure