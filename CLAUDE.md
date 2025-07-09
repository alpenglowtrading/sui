# CLAUDE.md - Keep under 300 tokens

## Essential File Paths
- GitHub Actions: `.github/workflows/lark_notify.yml`
- Lark notification script: `.github/scripts/lark_notify.sh`

## Recent Work Done
- **FIXED LARK SIGNATURE ISSUE** - Error 19021 "sign match fail" resolved
- Updated signature generation (lark_notify.sh:204): Use `printf "%s\n%s"` for real newline
- Changed timestamp format (lark_notify.sh:27): Unix timestamp `date +%s` not ISO format
- Lark notifications now working: HTTP 200 with success response

## Key Patterns
- Workflow notification failures usually in lark_notify.sh
- Script uses functions for JSON card creation and webhook calls
- Exit codes: 0 for success/skip, 1 for failure