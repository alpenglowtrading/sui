# Lark Notification Script Testing Guide

## Overview
This guide explains how to test the `lark_notify.sh` script locally and troubleshoot common issues.

## 🔒 SECURITY NOTICE

**NEVER expose `LARK_WEBHOOK` and `LARK_SECRET` in:**
- Scripts or code
- Logs or documentation
- AI interactions
- Version control

**ALWAYS use `.env` file for local testing and GitHub Secrets for production.**

## 🚨 IMPORTANT: Signature Issue Fix

**If you encounter Error 19021 "sign match fail":**

The issue is in signature generation. Use this correct format:
```bash
# ❌ WRONG (literal \n)
sign_string="${timestamp}\n${secret}"

# ✅ CORRECT (real newline)
sign_string=$(printf "%s\n%s" "$timestamp" "$secret")
```

Also ensure Unix timestamp format:
```bash
# ❌ WRONG (ISO format)
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ✅ CORRECT (Unix timestamp)
timestamp=$(date +%s)
```

## Test Setup

### 1. Make Script Executable
```bash
chmod +x .github/scripts/lark_notify.sh
```

### 2. Set Environment Variables

#### Option A: Test with httpbin.org (safe testing)
```bash
# Test webhook endpoint (accepts POST, returns 200)
export LARK_WEBHOOK="https://httpbin.org/post"
export LARK_SECRET="test_secret"
```

#### Option B: Test with real Lark webhook (SECURE METHOD)
```bash
# IMPORTANT: Never expose real credentials in scripts or logs
# Create .env file with your actual credentials:
cat > .env << 'EOF'
LARK_WEBHOOK=your_actual_webhook_url
LARK_SECRET=your_actual_secret
EOF

# Add .env to .gitignore to prevent accidental commits
echo ".env" >> .gitignore

# Load environment variables securely
source .env
```

### 3. Set Event Variables

#### Test Workflow Failure
```bash
export GITHUB_EVENT_NAME="workflow_run"
export GITHUB_EVENT_STATUS="failure"
export GITHUB_EVENT_WORKFLOW_NAME="Test Workflow"
export GITHUB_EVENT_WORKFLOW_URL="https://github.com/test/test/actions/runs/123"
export GITHUB_EVENT_WORKFLOW_BRANCH="main"
export GITHUB_EVENT_WORKFLOW_ACTOR="testuser"
export GITHUB_EVENT_WORKFLOW_RUN_ID="123"
export GITHUB_EVENT_WORKFLOW_COMMIT_SHA="abc123def456789"
export GITHUB_EVENT_REPO="test/test"
export GITHUB_EVENT_REPO_NAME="test"
```

#### Test PR Event
```bash
export GITHUB_EVENT_NAME="pull_request"
export GITHUB_EVENT_ACTION="opened"
export GITHUB_EVENT_PR_TITLE="Test PR"
export GITHUB_EVENT_PR_URL="https://github.com/test/test/pull/123"
export GITHUB_EVENT_PR_USER="testuser"
export GITHUB_EVENT_PR_NUMBER="123"
export GITHUB_EVENT_PR_BASE_BRANCH="main"
export GITHUB_EVENT_PR_HEAD_BRANCH="feature/test"
export GITHUB_EVENT_PR_DRAFT="false"
export GITHUB_EVENT_PR_MERGED="false"
export GITHUB_EVENT_PR_ADDITIONS="10"
export GITHUB_EVENT_PR_DELETIONS="5"
export GITHUB_EVENT_PR_CHANGED_FILES="3"
```

#### Test Push Event
```bash
export GITHUB_EVENT_NAME="push"
export GITHUB_EVENT_REF_NAME="main"
export GITHUB_EVENT_HEAD_COMMIT_MESSAGE="Test commit message"
export GITHUB_EVENT_HEAD_COMMIT_AUTHOR="testuser"
export GITHUB_EVENT_COMMIT_SHA="abc123def456789"
export GITHUB_EVENT_REPO="test/test"
export GITHUB_EVENT_REPO_NAME="test"
```

### 4. Run Test
```bash
# For safe testing (httpbin.org)
./.github/scripts/lark_notify.sh

# For real testing (requires .env with actual credentials)
source .env && ./.github/scripts/lark_notify.sh
```

## Expected Responses

### ✅ Success Response
```json
{"StatusCode":0,"StatusMessage":"success","code":0,"data":{},"msg":"success"}
```

### ❌ Error 19021 (Signature Issue)
```json
{"code":19021,"data":{},"msg":"sign match fail or timestamp is not within one hour from current time"}
```

### ❌ HTTP 401/403 (Auth Issue)
```
Authentication/authorization failed - check LARK_SECRET
```

## Debugging Steps

### 1. Test Signature Generation (Safe Test)
```bash
# Test correct signature format with dummy data
timestamp=$(date +%s)
secret="test_secret"
sign_string=$(printf "%s\n%s" "$timestamp" "$secret")
signature=$(printf "" | openssl dgst -sha256 -hmac "$sign_string" -binary | base64)
echo "Timestamp: $timestamp"
echo "Signature: $signature"
```

### 2. Test Simple Message (Safe Test)
```bash
# Test without signature using httpbin.org
curl -X POST "https://httpbin.org/post" \
  -H 'Content-Type: application/json' \
  -d '{"msg_type": "text", "content": {"text": "Test message"}}'
```

### 3. Check Webhook URL (Only for debugging)
```bash
# ONLY use this with httpbin.org for testing
curl -I "https://httpbin.org/post"
```

## What the Test Validates

- ✅ JSON generation and validation
- ✅ Signature generation (HMAC-SHA256 with correct format)
- ✅ HTTP request handling
- ✅ Error handling and debugging output
- ✅ Script execution without crashes
- ✅ Timestamp format (Unix vs ISO)
- ✅ Newline character handling in signature

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| Error 19021 | Wrong signature format | Use `printf "%s\n%s"` not `"${timestamp}\n${secret}"` |
| Error 19021 | Wrong timestamp format | Use `date +%s` not `date -u +"%Y-%m-%dT%H:%M:%SZ"` |
| HTTP 401/403 | Wrong secret | Check `LARK_SECRET` in `.env` matches bot token |
| No response | Wrong webhook URL | Verify `LARK_WEBHOOK` in `.env` is correct |
| Script exits early | Missing env vars | Check all required variables are set |

## Quick Fix Command

If you have the signature issue, run this to fix it:
```bash
# Fix signature generation in lark_notify.sh
sed -i 's/local sign_string="${timestamp}\\n${secret}"/local sign_string=$(printf "%s\\n%s" "$timestamp" "$secret")/g' .github/scripts/lark_notify.sh

# Fix timestamp format
sed -i 's/TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")/TIMESTAMP=$(date +%s)/g' .github/scripts/lark_notify.sh
```

## Testing Different Scenarios

### Test All Event Types
```bash
# Loop through different event types
for event in "push" "pull_request" "workflow_run"; do
  export GITHUB_EVENT_NAME="$event"
  echo "Testing $event event..."
  source .env && ./.github/scripts/lark_notify.sh
done
```

### Secure Testing Protocol
```bash
# 1. Create .env with real credentials (NEVER commit this)
# 2. Add .env to .gitignore
# 3. Load env vars: source .env
# 4. Run test: ./.github/scripts/lark_notify.sh
# 5. Delete .env when done: rm .env
```

## 🔐 Security Checklist

Before testing with real credentials:
- [ ] `.env` file created with real values
- [ ] `.env` added to `.gitignore`
- [ ] Never paste real webhook URL or secret in scripts
- [ ] Never commit `.env` file
- [ ] Delete `.env` file after testing
- [ ] Use GitHub Secrets for production

---

*This testing guide includes the signature fix that resolves Error 19021 and follows security best practices for credential handling.*