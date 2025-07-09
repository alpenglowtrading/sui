#!/bin/bash
set -euo pipefail

# Exit early if webhook URL is not set
if [ -z "${LARK_WEBHOOK:-}" ]; then
  echo "LARK_WEBHOOK secret is not set, skipping notification"
  exit 0
fi

# Global list of expected workflow names (from lark_notify.yml)
EXPECTED_WORKFLOWS=(
  "Documentation"
  "Docs CI"
  "IDE Tests"
  "Move Formatter"
  "Turborepo CI"
)

# Initialize variables from environment
EVENT_NAME="${GITHUB_EVENT_NAME:-}"
ACTION="${GITHUB_EVENT_ACTION:-}"
STATUS="${GITHUB_EVENT_STATUS:-}"
REPO="${GITHUB_EVENT_REPO:-}"
REPO_NAME="${GITHUB_EVENT_REPO_NAME:-}"
REPO_OWNER="${GITHUB_EVENT_REPO_OWNER:-}"
ACTOR="${GITHUB_EVENT_ACTOR:-}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Function to escape JSON strings
escape_json() {
  local input="$1"
  # Escape backslashes first, then quotes, then newlines and tabs
  echo "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g; s/\t/\\t/g; s/\r/\\r/g'
}

# Function to truncate text with ellipsis
truncate_text() {
  local text="$1"
  local max_length="${2:-200}"
  if [ ${#text} -gt $max_length ]; then
    echo "${text:0:$max_length}..."
  else
    echo "$text"
  fi
}

# Function to create rich notification card
create_notification_card() {
  local event_type="$1"
  local template_color="$2"
  local elements="$3"
  local timestamp="$4"
  
  cat << EOF
{
  "msg_type": "interactive",
  "card": {
    "config": {
      "wide_screen_mode": true,
      "enable_forward": true
    },
    "header": {
      "title": {
        "tag": "plain_text",
        "content": "${event_type}"
      },
      "template": "${template_color}",
      "ud_icon": {
        "token": "img_v2_041b28e3-5680-48c2-9af2-497ace79333g"
      }
    },
    "elements": [
      ${elements}
    ]
  },
  "timestamp": "${timestamp}"
}
EOF
}

# Function to create standard button action
create_button_action() {
  local buttons="$1"
  cat << EOF
{
  "tag": "action",
  "actions": [
    ${buttons}
  ]
}
EOF
}

# Function to create standard button
create_button() {
  local text="$1"
  local url="$2"
  local type="${3:-primary}"
  cat << EOF
{
  "tag": "button",
  "text": {
    "tag": "plain_text",
    "content": "${text}"
  },
  "type": "${type}",
  "url": "${url}"
}
EOF
}

# Function to create field layout
create_field_layout() {
  local fields="$1"
  cat << EOF
{
  "tag": "div",
  "fields": [
    ${fields}
  ]
}
EOF
}

# Function to create field
create_field() {
  local label="$1"
  local value="$2"
  local is_short="${3:-true}"
  cat << EOF
{
  "is_short": ${is_short},
  "text": {
    "tag": "lark_md",
    "content": "**${label}:**\n${value}"
  }
}
EOF
}

# Function to create divider
create_divider() {
  echo '{"tag": "hr"}'
}

# Function to create content div
create_content_div() {
  local content="$1"
  cat << EOF
{
  "tag": "div",
  "text": {
    "tag": "lark_md",
    "content": "${content}"
  }
}
EOF
}

# Function to get workflow run details
get_workflow_run_details() {
  local run_id="$1"
  local jobs_response
  
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    jobs_response=$(curl -s -f \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${REPO}/actions/runs/${run_id}/jobs" 2>/dev/null || echo '{"jobs":[]}')
  else
    jobs_response='{"jobs":[]}'
  fi
  
  echo "$jobs_response"
}

# Function to check if all workflows for a commit are complete
check_all_workflows_complete() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "No GITHUB_TOKEN available, cannot check workflow completion status"
    return
  fi
  
  # Check if we've already sent notification for this commit
  local notification_file="/tmp/lark_notify_${COMMIT_SHA}_sent"
  if [ -f "$notification_file" ]; then
    echo "Already sent notification for commit ${COMMIT_SHA}, skipping"
    return
  fi
  
  # Get ALL workflow runs for this commit (remove event filter to get all workflows)
  local runs_response
  runs_response=$(curl -s -f \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${REPO}/actions/runs?head_sha=${COMMIT_SHA}" 2>/dev/null || echo '{"workflow_runs":[]}')
  
  # Check if all expected workflows are complete and get their statuses
  local all_complete="true"
  local has_failure="false"
  local completed_workflows=""
  local total_expected_workflows=${#EXPECTED_WORKFLOWS[@]}
  local completed_count=0
  
  # Track unique workflow names to avoid double counting
  declare -A workflow_status
  declare -A workflow_conclusion
  
  # Parse workflow runs using jq and filter by expected workflows
  while IFS='|' read -r name status conclusion; do
    if [ -n "$name" ]; then
      # Check if this workflow is in the expected list
      local is_expected="false"
      for expected in "${EXPECTED_WORKFLOWS[@]}"; do
        if [ "$name" = "$expected" ]; then
          is_expected="true"
          break
        fi
      done
      
      if [ "$is_expected" = "true" ]; then
        # Only update if we don't have this workflow or if this run is more recent
        if [ -z "${workflow_status[$name]:-}" ] || [ "$status" = "completed" ]; then
          workflow_status[$name]="$status"
          workflow_conclusion[$name]="$conclusion"
        fi
      fi
    fi
  done < <(echo "$runs_response" | jq -r '.workflow_runs[] | "\(.name)|\(.status)|\(.conclusion // "unknown")"' 2>/dev/null || true)
  
  # Now count unique workflows
  for workflow_name in "${EXPECTED_WORKFLOWS[@]}"; do
    if [ -n "${workflow_status[$workflow_name]:-}" ]; then
      if [ "${workflow_status[$workflow_name]}" = "completed" ]; then
        completed_count=$((completed_count + 1))
        completed_workflows="${completed_workflows}• $workflow_name: ${workflow_conclusion[$workflow_name]:-unknown}\n"
        if [ "${workflow_conclusion[$workflow_name]:-}" = "failure" ]; then
          has_failure="true"
        fi
      else
        all_complete="false"
      fi
    else
      all_complete="false"
    fi
  done
  
  echo "Status check: ${completed_count}/${total_expected_workflows} expected workflows complete, has_failure=${has_failure}, all_complete=${all_complete}"
  
  # Only send success notification if ALL expected workflows are complete and no failures
  if [ "$all_complete" = "true" ] && [ "$has_failure" = "false" ] && [ "$completed_count" -eq "$total_expected_workflows" ]; then
    # Create flag file to prevent duplicate notifications
    echo "$(date)" > "$notification_file"
    send_all_passed_notification
  fi
}

# Function to send "all passed" notification
send_all_passed_notification() {
  local event_type="✅ All Tests Passed"
  local template_color="green"
  
  local content_div=$(create_content_div "All workflows completed successfully on **${BRANCH}**")
  local divider=$(create_divider)
  
  local field1=$(create_field "👤 Triggered by" "@${WORKFLOW_ACTOR}" true)
  local field2=$(create_field "🌿 Branch" "${BRANCH}" true)
  local field3=$(create_field "📝 Commit" "${SHORT_SHA}" true)
  local field4=$(create_field "📦 Repository" "${REPO_NAME}" true)
  local field_layout=$(create_field_layout "${field1}, ${field2}, ${field3}, ${field4}")
  
  local button1=$(create_button "📝 View Commit" "https://github.com/${REPO}/commit/${COMMIT_SHA}" "primary")
  local button2=$(create_button "🌲 View Branch" "https://github.com/${REPO}/tree/${BRANCH}" "default")
  local button_action=$(create_button_action "${button1}, ${button2}")
  
  local elements="${content_div}, ${divider}, ${field_layout}, ${button_action}"
  local card_json=$(create_notification_card "$event_type" "$template_color" "$elements" "$TIMESTAMP")
  
  echo "🚀 Sending 'All Tests Passed' notification to Lark..."
  echo "$card_json" | jq -C '.'
  
  # Send notification with signature if secret is provided
  CURRENT_TIMESTAMP=$(date +%s)
  
  if [ -n "${LARK_SECRET:-}" ]; then
    SIGNATURE=$(generate_signature "$card_json" "$LARK_SECRET" "$CURRENT_TIMESTAMP")
    CURL_HEADERS=(-H 'Content-Type: application/json' -H "X-Lark-Request-Timestamp: $CURRENT_TIMESTAMP" -H "X-Lark-Request-Nonce: $(uuidgen)" -H "X-Lark-Signature: $SIGNATURE")
  else
    CURL_HEADERS=(-H 'Content-Type: application/json')
  fi
  
  if curl -X POST "$LARK_WEBHOOK" \
    "${CURL_HEADERS[@]}" \
    -d "$card_json" \
    --fail-with-body \
    --max-time 30 \
    --silent \
    --show-error; then
    echo "✅ All passed notification sent successfully"
  else
    echo "❌ Failed to send all passed notification"
  fi
}

# Main notification logic
case "$EVENT_NAME" in
  "pull_request")
    TITLE="$(escape_json "${GITHUB_EVENT_PR_TITLE:-}")"
    URL="${GITHUB_EVENT_PR_URL:-}"
    USER="${GITHUB_EVENT_PR_USER:-}"
    PR_NUMBER="${GITHUB_EVENT_PR_NUMBER:-}"
    BASE_BRANCH="${GITHUB_EVENT_PR_BASE_BRANCH:-}"
    HEAD_BRANCH="${GITHUB_EVENT_PR_HEAD_BRANCH:-}"
    DRAFT="${GITHUB_EVENT_PR_DRAFT:-}"
    MERGED="${GITHUB_EVENT_PR_MERGED:-}"
    ADDITIONS="${GITHUB_EVENT_PR_ADDITIONS:-}"
    DELETIONS="${GITHUB_EVENT_PR_DELETIONS:-}"
    CHANGED_FILES="${GITHUB_EVENT_PR_CHANGED_FILES:-}"
    
    # Skip synchronize events for draft PRs unless explicitly enabled
    if [ "$ACTION" == "synchronize" ] && [ "$DRAFT" == "true" ]; then
      echo "Skipping synchronize event for draft PR"
      exit 0
    fi
    
    case "$ACTION" in
      "opened")
        EVENT_TYPE="🆕 Pull Request Opened"
        TEMPLATE_COLOR="green"
        ;;
      "closed")
        if [ "$MERGED" == "true" ]; then
          EVENT_TYPE="🎉 Pull Request Merged"
          TEMPLATE_COLOR="purple"
        else
          EVENT_TYPE="❌ Pull Request Closed"
          TEMPLATE_COLOR="red"
        fi
        ;;
      "reopened")
        EVENT_TYPE="🔄 Pull Request Reopened"
        TEMPLATE_COLOR="blue"
        ;;
      "ready_for_review")
        EVENT_TYPE="👀 Pull Request Ready for Review"
        TEMPLATE_COLOR="green"
        ;;
      "converted_to_draft")
        EVENT_TYPE="📝 Pull Request Converted to Draft"
        TEMPLATE_COLOR="grey"
        ;;
      *)
        EVENT_TYPE="🔔 Pull Request Updated"
        TEMPLATE_COLOR="orange"
        ;;
    esac
    
    # Create elements
    CONTENT_DIV=$(create_content_div "**#${PR_NUMBER}:** ${TITLE}")
    DIVIDER=$(create_divider)
    
    FIELD1=$(create_field "👤 Author" "@${USER}" true)
    FIELD2=$(create_field "🌿 Branch" "${HEAD_BRANCH} → ${BASE_BRANCH}" true)
    FIELD3=$(create_field "📊 Changes" "+${ADDITIONS} -${DELETIONS} (~${CHANGED_FILES} files)" true)
    FIELD4=$(create_field "🏷️ Status" "$([ "$DRAFT" == "true" ] && echo "Draft" || echo "Ready")" true)
    FIELD_LAYOUT=$(create_field_layout "${FIELD1}, ${FIELD2}, ${FIELD3}, ${FIELD4}")
    
    BUTTON1=$(create_button "🔍 View PR" "$URL" "primary")
    BUTTON2=$(create_button "👤 View Author" "https://github.com/${USER}" "default")
    BUTTON_ACTION=$(create_button_action "${BUTTON1}, ${BUTTON2}")
    
    ELEMENTS="${CONTENT_DIV}, ${DIVIDER}, ${FIELD_LAYOUT}, ${BUTTON_ACTION}"
    CARD_JSON=$(create_notification_card "$EVENT_TYPE" "$TEMPLATE_COLOR" "$ELEMENTS" "$TIMESTAMP")
    ;;
    
  "push")
    # Skip push events for non-main branches unless it's a release branch
    if [[ "${GITHUB_EVENT_REF_NAME}" != "main" ]] && [[ "${GITHUB_EVENT_REF_NAME}" != "develop" ]] && [[ "${GITHUB_EVENT_REF_NAME}" != release/* ]] && [[ "${GITHUB_EVENT_REF_NAME}" != hotfix/* ]]; then
      echo "Skipping push event for branch: ${GITHUB_EVENT_REF_NAME}"
      exit 0
    fi
    
    # Get commit info
    COMMIT_SHA="${GITHUB_EVENT_COMMIT_SHA:-}"
    SHORT_SHA="${COMMIT_SHA:0:7}"
    URL="https://github.com/${REPO}/commit/${COMMIT_SHA}"
    BRANCH="${GITHUB_EVENT_REF_NAME:-}"
    
    # Try to get commit message and author
    COMMIT_MSG="${GITHUB_EVENT_HEAD_COMMIT_MESSAGE:-}"
    AUTHOR="${GITHUB_EVENT_HEAD_COMMIT_AUTHOR:-}"
    
    # Final fallbacks
    if [ -z "$COMMIT_MSG" ]; then
      COMMIT_MSG="Commit ${SHORT_SHA}"
    fi
    if [ -z "$AUTHOR" ]; then
      AUTHOR="${ACTOR}"
    fi
    
    COMMIT_MSG="$(escape_json "$COMMIT_MSG")"
    COMMIT_MSG="$(truncate_text "$COMMIT_MSG" 150)"
    
    EVENT_TYPE="🚀 New Push to ${BRANCH}"
    TEMPLATE_COLOR="blue"
    
    CONTENT_DIV=$(create_content_div "${COMMIT_MSG}")
    DIVIDER=$(create_divider)
    
    FIELD1=$(create_field "👤 Author" "${AUTHOR}" true)
    FIELD2=$(create_field "📝 Commit" "${SHORT_SHA}" true)
    FIELD3=$(create_field "🌿 Branch" "${BRANCH}" true)
    FIELD4=$(create_field "📦 Repository" "${REPO_NAME}" true)
    FIELD_LAYOUT=$(create_field_layout "${FIELD1}, ${FIELD2}, ${FIELD3}, ${FIELD4}")
    
    BUTTON1=$(create_button "🔍 View Commit" "$URL" "primary")
    BUTTON2=$(create_button "🌲 View Branch" "https://github.com/${REPO}/tree/${BRANCH}" "default")
    BUTTON_ACTION=$(create_button_action "${BUTTON1}, ${BUTTON2}")
    
    ELEMENTS="${CONTENT_DIV}, ${DIVIDER}, ${FIELD_LAYOUT}, ${BUTTON_ACTION}"
    CARD_JSON=$(create_notification_card "$EVENT_TYPE" "$TEMPLATE_COLOR" "$ELEMENTS" "$TIMESTAMP")
    ;;
    
  "workflow_run")
    WORKFLOW_NAME="${GITHUB_EVENT_WORKFLOW_NAME:-}"
    URL="${GITHUB_EVENT_WORKFLOW_URL:-}"
    BRANCH="${GITHUB_EVENT_WORKFLOW_BRANCH:-}"
    WORKFLOW_ACTOR="${GITHUB_EVENT_WORKFLOW_ACTOR:-}"
    RUN_ID="${GITHUB_EVENT_WORKFLOW_RUN_ID:-}"
    COMMIT_SHA="${GITHUB_EVENT_WORKFLOW_COMMIT_SHA:-}"
    SHORT_SHA="${COMMIT_SHA:0:7}"
    
    case "$STATUS" in
      "failure")
        # Immediate notification for failures
        EVENT_TYPE="🚨 CI Failed: ${WORKFLOW_NAME}"
        TEMPLATE_COLOR="red"
        
        # Get failed jobs information
        JOBS_INFO=$(get_workflow_run_details "$RUN_ID")
        FAILED_JOBS=$(echo "$JOBS_INFO" | jq -r '.jobs[] | select(.conclusion == "failure") | "• " + .name' | head -5 | tr '\n' '\n' || echo "• Check workflow logs for details")
        
        CONTENT_DIV=$(create_content_div "**${WORKFLOW_NAME}** failed on **${BRANCH}**")
        DIVIDER=$(create_divider)
        
        if [ -n "$FAILED_JOBS" ]; then
          FAILED_JOBS_DIV=$(create_content_div "**❌ Failed Jobs:**\n${FAILED_JOBS}")
        else
          FAILED_JOBS_DIV=$(create_content_div "**❌ Failed Jobs:**\n• Check workflow logs for details")
        fi
        
        DIVIDER2=$(create_divider)
        
        FIELD1=$(create_field "👤 Triggered by" "@${WORKFLOW_ACTOR}" true)
        FIELD2=$(create_field "🌿 Branch" "${BRANCH}" true)
        FIELD3=$(create_field "📝 Commit" "${SHORT_SHA}" true)
        FIELD4=$(create_field "📦 Repository" "${REPO_NAME}" true)
        FIELD_LAYOUT=$(create_field_layout "${FIELD1}, ${FIELD2}, ${FIELD3}, ${FIELD4}")
        
        BUTTON1=$(create_button "🔍 View Logs" "$URL" "danger")
        BUTTON2=$(create_button "📝 View Commit" "https://github.com/${REPO}/commit/${COMMIT_SHA}" "default")
        BUTTON_ACTION=$(create_button_action "${BUTTON1}, ${BUTTON2}")
        
        ELEMENTS="${CONTENT_DIV}, ${DIVIDER}, ${FAILED_JOBS_DIV}, ${DIVIDER2}, ${FIELD_LAYOUT}, ${BUTTON_ACTION}"
        CARD_JSON=$(create_notification_card "$EVENT_TYPE" "$TEMPLATE_COLOR" "$ELEMENTS" "$TIMESTAMP")
        ;;
        
      "success"|"cancelled"|"skipped"|"neutral")
        # Check if all workflows for this commit are complete
        echo "Workflow ${WORKFLOW_NAME} completed with status: ${STATUS}"
        check_all_workflows_complete
        exit 0
        ;;
        
      *)
        echo "Skipping notification for workflow status: $STATUS"
        exit 0
        ;;
    esac
    ;;
    
  *)
    echo "Unsupported event type: $EVENT_NAME"
    exit 0
    ;;
esac

# Validate JSON before sending
if ! echo "$CARD_JSON" | jq empty 2>/dev/null; then
  echo "❌ Invalid JSON generated, skipping notification"
  echo "$CARD_JSON" | head -20
  exit 1
fi

echo "🚀 Sending notification to Lark..."
echo "$CARD_JSON" | jq -C '.'

# Function to generate signature
generate_signature() {
  local payload="$1"
  local secret="$2"
  local timestamp="$3"
  
  if [ -n "$secret" ]; then
    # Create signature string: timestamp + payload
    local sign_string="${timestamp}${payload}"
    # Generate HMAC-SHA256 signature
    echo -n "$sign_string" | openssl dgst -sha256 -hmac "$secret" -binary | base64
  else
    echo ""
  fi
}

# Send notification with retry logic
RETRY_COUNT=0
MAX_RETRIES=3

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  # Generate timestamp for signature
  CURRENT_TIMESTAMP=$(date +%s)
  
  # Generate signature if secret is provided
  if [ -n "${LARK_SECRET:-}" ]; then
    SIGNATURE=$(generate_signature "$CARD_JSON" "$LARK_SECRET" "$CURRENT_TIMESTAMP")
    CURL_HEADERS=(-H 'Content-Type: application/json' -H "X-Lark-Request-Timestamp: $CURRENT_TIMESTAMP" -H "X-Lark-Request-Nonce: $(uuidgen)" -H "X-Lark-Signature: $SIGNATURE")
  else
    CURL_HEADERS=(-H 'Content-Type: application/json')
  fi
  
  if curl -X POST "$LARK_WEBHOOK" \
    "${CURL_HEADERS[@]}" \
    -d "$CARD_JSON" \
    --fail-with-body \
    --max-time 30 \
    --retry 2 \
    --retry-delay 5 \
    --silent \
    --show-error; then
    echo "✅ Notification sent successfully"
    exit 0
  else
    RETRY_COUNT=$((RETRY_COUNT + 1))
    echo "⚠️ Attempt $RETRY_COUNT failed, retrying in 5 seconds..."
    sleep 5
  fi
done

echo "❌ Failed to send notification after $MAX_RETRIES attempts"
exit 1