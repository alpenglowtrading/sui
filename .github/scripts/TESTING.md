# Lark Notification Script Testing Guide

## Overview
This guide explains how to test the `lark_notify.sh` script locally without sending actual notifications to Lark.

## Test Setup

### 1. Make Script Executable
```bash
chmod +x .github/scripts/lark_notify.sh
```

### 2. Set Environment Variables
Export the required environment variables with test values:

```bash
# Test webhook endpoint (accepts POST, returns 200)
export LARK_WEBHOOK="https://httpbin.org/post"

# Test secret for signature verification
export LARK_SECRET="test_secret"

# Simulate workflow failure event
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

### 3. Run Test
```bash
./.github/scripts/lark_notify.sh
```

## What the Test Validates

- ✅ JSON generation and validation
- ✅ Signature generation (HMAC-SHA256)
- ✅ HTTP request handling
- ✅ Error handling and debugging output
- ✅ Script execution without crashes

## Test Output
Successful test shows:
- JSON card structure
- Signature verification details
- HTTP 200 response
- "Notification sent successfully" message

## Other Event Types
Test different events by changing `GITHUB_EVENT_NAME`:

```bash
# Test PR event
export GITHUB_EVENT_NAME="pull_request"
export GITHUB_EVENT_ACTION="opened"
export GITHUB_EVENT_PR_TITLE="Test PR"
export GITHUB_EVENT_PR_URL="https://github.com/test/test/pull/123"
export GITHUB_EVENT_PR_USER="testuser"
export GITHUB_EVENT_PR_NUMBER="123"

# Test push event
export GITHUB_EVENT_NAME="push"
export GITHUB_EVENT_REF_NAME="main"
export GITHUB_EVENT_HEAD_COMMIT_MESSAGE="Test commit"
export GITHUB_EVENT_HEAD_COMMIT_AUTHOR="testuser"
```

## Note
This test uses `httpbin.org/post` which accepts HTTP requests but doesn't send real notifications. For actual Lark testing, replace with your real webhook URL.