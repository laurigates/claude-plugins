#!/usr/bin/env bash
#
# Command Analytics Tracker
# Captures Skill tool invocations to track command/skill usage

set -euo pipefail

# Analytics directory
ANALYTICS_DIR="${HOME}/.claude-analytics"
EVENTS_FILE="${ANALYTICS_DIR}/events.jsonl"
SUMMARY_FILE="${ANALYTICS_DIR}/summary.json"

# Create analytics directory if it doesn't exist
mkdir -p "${ANALYTICS_DIR}"

# Read hook input from stdin (JSON with tool parameters and result)
HOOK_INPUT=$(cat)

# Extract relevant data
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SKILL_NAME=$(echo "${HOOK_INPUT}" | jq -r '.parameters.skill // "unknown"')
SKILL_ARGS=$(echo "${HOOK_INPUT}" | jq -r '.parameters.args // ""')
PROJECT_DIR=$(pwd)
SUCCESS=$(echo "${HOOK_INPUT}" | jq -r 'if .error then false else true end')
ERROR_MSG=$(echo "${HOOK_INPUT}" | jq -r '.error // ""')

# Determine if this is a command (contains colon) or skill
if [[ "${SKILL_NAME}" == *:* ]]; then
  EVENT_TYPE="command"
else
  EVENT_TYPE="skill"
fi

# Capture agent teams context when available
TEAM_ROLE="${CLAUDE_TEAM_ROLE:-}"
TEAM_SESSION="${CLAUDE_TEAM_SESSION:-}"

# Create event record
EVENT=$(jq -n \
  --arg timestamp "${TIMESTAMP}" \
  --arg type "${EVENT_TYPE}" \
  --arg name "${SKILL_NAME}" \
  --arg args "${SKILL_ARGS}" \
  --arg project "${PROJECT_DIR}" \
  --argjson success "${SUCCESS}" \
  --arg error "${ERROR_MSG}" \
  --arg team_role "${TEAM_ROLE}" \
  --arg team_session "${TEAM_SESSION}" \
  '{
    timestamp: $timestamp,
    type: $type,
    name: $name,
    args: $args,
    project: $project,
    success: $success,
    error: $error
  } + (if $team_role != "" then {team_role: $team_role} else {} end)
    + (if $team_session != "" then {team_session: $team_session} else {} end)')

# Append to events file (JSONL format)
echo "${EVENT}" >> "${EVENTS_FILE}"

# Update summary file
if [[ -f "${SUMMARY_FILE}" ]]; then
  SUMMARY=$(cat "${SUMMARY_FILE}")
else
  SUMMARY=$(jq -n \
    --arg since "${TIMESTAMP}" \
    '{
      tracking_since: $since,
      total_invocations: 0,
      items: {}
    }')
fi

# Update summary statistics
SUMMARY=$(echo "${SUMMARY}" | jq \
  --arg name "${SKILL_NAME}" \
  --arg type "${EVENT_TYPE}" \
  --argjson success "${SUCCESS}" \
  --arg timestamp "${TIMESTAMP}" \
  '
  .total_invocations += 1 |
  .items[$name] //= {
    type: $type,
    count: 0,
    success: 0,
    failure: 0,
    first_used: $timestamp,
    last_used: $timestamp
  } |
  .items[$name].count += 1 |
  .items[$name].last_used = $timestamp |
  if $success then
    .items[$name].success += 1
  else
    .items[$name].failure += 1
  end
')

echo "${SUMMARY}" > "${SUMMARY_FILE}"

# Exit successfully (don't block the workflow)
exit 0
