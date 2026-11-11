# SPDX-License-Identifier: MIT
# Copyright (c) 2025-2026 Kaptain contributors (Fred Cooke)
#
# Shared helpers for the Slack notify providers. Sourced, not executed.
#
# Configuration is one key per file, as Kubernetes mounts a ConfigMap/Secret:
#
#   ${NOTIFY_SECRETS_BASE}/slackAppBotUserOAuthToken Bot User OAuth Token, xoxb-...
#   ${NOTIFY_CONFIG_BASE}/slackChannelId             Deploy thread channel, C0...
#   ${NOTIFY_CONFIG_BASE}/slackAlertChannelId        Alert channel, C0..., separate from the deploy channel
#   ${NOTIFY_CONFIG_BASE}/slackUsername              Optional, needs chat:write.customize
#   ${NOTIFY_CONFIG_BASE}/slackIconEmoji             Optional, needs chat:write.customize
#   ${NOTIFY_CONFIG_BASE}/slackIconUrl               Optional, needs chat:write.customize
#   ${NOTIFY_CONFIG_BASE}/slackRequired              Optional, 'true' makes validation failure block the deploy
#   ${NOTIFY_CONFIG_BASE}/slackFailureUserIds        Optional, user IDs (U0...) to DM on failure, comma and/or space separated
#   ${NOTIFY_CONFIG_BASE}/slackAlertUserIds          Optional, user IDs (U0...) to DM on alert, comma and/or space separated
#   ${NOTIFY_CONFIG_BASE}/slackAlertMention          Optional, mention before alert posts, default <!here>, empty for none
#   ${NOTIFY_CONFIG_BASE}/slack<Level>Prefix         Optional, text put before each message of that level, see slack_prefix
#   ${NOTIFY_CONFIG_BASE}/slack<Kind>Reaction        Optional, reaction on the opening post, see slack_thread_react_for
#   ${NOTIFY_CONFIG_BASE}/slackThreadLookbackDays    Optional, days of history searched for NOTIFY_THREAD_KEY, default 30
#   ${NOTIFY_CONFIG_BASE}/slackContext               'deploy' or 'build', picks the default DM wording
#   ${NOTIFY_CONFIG_BASE}/slackCurl<Setting>         Optional, curl retry and timeouts, see slack_curl_settings
#   ${NOTIFY_CONFIG_BASE}/slackFailureDmLeader       Optional, first line of failure DMs, default per slackContext
#   ${NOTIFY_CONFIG_BASE}/slackFailureLinkLabel      Optional, text before the thread link in failure DMs
#   ${NOTIFY_CONFIG_BASE}/slackAlertDmLeader         Optional, first line of alert DMs
#   ${NOTIFY_CONFIG_BASE}/slackAlertLinkLabel        Optional, text before the alert link in alert DMs
#
# The optional entries' defaults are files in lib/notify-slack-defaults/, one
# per entry, with deploy/ and build/ variants picked by slackContext for the DM
# wording, packaged there from src/defaults. Absent gives the default, present
# but empty turns it off.
#
# NOTIFY_CONFIG_BASE, NOTIFY_SECRETS_BASE and NOTIFY_WORK_BASE must be set by
# the caller, there are no defaults. The thread is recorded by the first post
# of the run under ${NOTIFY_WORK_BASE}/notify/slack.
#
# NOTIFY_THREAD_KEY, set by the caller, makes runs with the same key share one
# thread, for example an env name and version. The opening post carries the key
# as hidden message metadata and later runs find it by searching the channel
# history, which needs channels:history (and groups:history for private ones).
# Unset, each run opens its own thread.

# shellcheck disable=SC2154 # NOTIFY_*_BASE are set by the caller, see above
SLACK_DEFAULTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/notify-slack-defaults"

# Print the value of a config or secret key, empty if absent
slack_read_key() {
  local file="$1/$2"
  [[ -f "${file}" ]] || return 0
  tr -d '\r\n' < "${file}"
}

# Print the plugin's default for an optional entry, the slackContext variant
# for the entries that differ between deploy and build
slack_default() {
  local key="$1"
  local context
  if [[ -f "${SLACK_DEFAULTS_DIR}/${key}" ]]; then
    slack_read_key "${SLACK_DEFAULTS_DIR}" "${key}"
    return 0
  fi
  context=$(slack_read_key "${NOTIFY_CONFIG_BASE}" slackContext)
  if [[ "${context}" == "deploy" || "${context}" == "build" ]]; then
    slack_read_key "${SLACK_DEFAULTS_DIR}/${context}" "${key}"
  fi
}

# Print an optional entry's value: the config entry when present, empty
# included, which turns it off, otherwise the plugin's default
slack_setting() {
  local key="$1"
  if [[ -f "${NOTIFY_CONFIG_BASE}/${key}" ]]; then
    slack_read_key "${NOTIFY_CONFIG_BASE}" "${key}"
  else
    slack_default "${key}"
  fi
}

# Print the message prefix for a level followed by a space, from
# slack<Level>Prefix, for example slackWarningPrefix
slack_prefix() {
  local level="$1"
  local value
  value=$(slack_setting "slack${level}Prefix")
  if [[ -n "${value}" ]]; then
    printf '%s ' "${value}"
  fi
}

# Call a Slack Web API method with a JSON payload and print the response body.
# Returns non-zero with a message on stderr if the call fails or ok is not true.
# Optional third argument is a file to dump the response headers into.
slack_api() {
  local method="$1"
  local payload="$2"
  local headers_file="${3:-/dev/null}"
  slack_request "${method}" \
    -H 'Content-Type: application/json; charset=utf-8' \
    -D "${headers_file}" \
    --data-binary "${payload}"
}

# Call a read-only Slack Web API method, which take query parameters rather
# than JSON. Arguments after the method are name=value pairs.
slack_api_get() {
  local method="$1"
  shift
  local args=(-G)
  local pair
  for pair in "$@"; do
    args+=(--data-urlencode "${pair}")
  done
  slack_request "${method}" "${args[@]}"
}

# Print the curl retry and timeout arguments. Defaults favour getting every
# message through, in order, on unreliable networks over speed. Each can be
# overridden with a whole number in slackCurl<Setting>, for example
# slackCurlMaxTime. Invalid or empty values fall back to the default.
slack_curl_settings() {
  local setting
  local value
  for setting in Retry RetryDelay ConnectTimeout MaxTime RetryMaxTime; do
    value=$(slack_read_key "${NOTIFY_CONFIG_BASE}" "slackCurl${setting}")
    if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
      value=$(slack_default "slackCurl${setting}")
    fi
    case "${setting}" in
      Retry) printf -- '--retry\n%s\n' "${value}" ;;
      RetryDelay) printf -- '--retry-delay\n%s\n' "${value}" ;;
      ConnectTimeout) printf -- '--connect-timeout\n%s\n' "${value}" ;;
      MaxTime) printf -- '--max-time\n%s\n' "${value}" ;;
      RetryMaxTime) printf -- '--retry-max-time\n%s\n' "${value}" ;;
    esac
  done
}

# Shared by slack_api and slack_api_get, extra arguments are passed to curl
slack_request() {
  local method="$1"
  shift
  local token
  token=$(slack_read_key "${NOTIFY_SECRETS_BASE}" slackAppBotUserOAuthToken)
  if [[ -z "${token}" ]]; then
    echo "slack: slackAppBotUserOAuthToken not found in ${NOTIFY_SECRETS_BASE}" >&2
    return 1
  fi

  local curl_settings=()
  local line
  while IFS= read -r line; do
    curl_settings+=("${line}")
  done < <(slack_curl_settings)

  # Token goes in via a config on stdin so it never shows up in ps output
  local response
  if ! response=$(printf 'header = "Authorization: Bearer %s"\n' "${token}" |
      curl -sS "${curl_settings[@]}" -K - "$@" \
        "https://slack.com/api/${method}"); then
    echo "slack: ${method} request failed" >&2
    return 1
  fi

  if [[ "$(yq -p json '.ok' <<< "${response}")" != "true" ]]; then
    local error
    error=$(yq -p json '.error' <<< "${response}")
    # Callers can declare one error as expected with a local slack_tolerated_error
    if [[ "${error}" == "${slack_tolerated_error:-}" ]]; then
      printf '%s\n' "${response}"
      return 0
    fi
    echo "slack: ${method} failed: ${error}" >&2
    return 1
  fi
  printf '%s\n' "${response}"
}

# Build a chat.postMessage payload. Empty fields are dropped, so thread_ts and
# the customize fields only appear when they have values. A thread key is only
# attached to a message that opens a thread.
slack_message_payload() {
  SLACK_CHANNEL="$1" \
  SLACK_TEXT="$2" \
  SLACK_THREAD_TS="${3:-}" \
  SLACK_BROADCAST="${4:-false}" \
  SLACK_THREAD_KEY="${5:-}" \
  SLACK_USERNAME="$(slack_read_key "${NOTIFY_CONFIG_BASE}" slackUsername)" \
  SLACK_ICON_EMOJI="$(slack_read_key "${NOTIFY_CONFIG_BASE}" slackIconEmoji)" \
  SLACK_ICON_URL="$(slack_read_key "${NOTIFY_CONFIG_BASE}" slackIconUrl)" \
  yq -n -o json -I0 '
    .channel = strenv(SLACK_CHANNEL) |
    .text = strenv(SLACK_TEXT) |
    .thread_ts = strenv(SLACK_THREAD_TS) |
    .username = strenv(SLACK_USERNAME) |
    .icon_emoji = strenv(SLACK_ICON_EMOJI) |
    .icon_url = strenv(SLACK_ICON_URL) |
    del(.[] | select(. == "")) |
    with(select(has("thread_ts") and strenv(SLACK_BROADCAST) == "true"); .reply_broadcast = true) |
    with(select((has("thread_ts") | not) and strenv(SLACK_THREAD_KEY) != "");
      .metadata.event_type = "kaptain_notify_thread" |
      .metadata.event_payload.thread_key = strenv(SLACK_THREAD_KEY))
  '
}

# Post a standalone message, not part of the deploy thread. Prints the
# response so callers can link to the message.
slack_post() {
  local channel="$1"
  local text="$2"
  local payload
  payload=$(slack_message_payload "${channel}" "${text}")
  slack_api chat.postMessage "${payload}"
}

# Post into the deploy thread, opening it with this message if there is none
# yet. Pass 'true' as the second argument to also show a reply in the channel.
slack_thread_post() {
  local text="$1"
  local broadcast="${2:-false}"
  local channel
  local thread_ts=""

  if [[ -f "${NOTIFY_WORK_BASE}/notify/slack/ts" ]]; then
    channel=$(cat "${NOTIFY_WORK_BASE}/notify/slack/channel")
    thread_ts=$(cat "${NOTIFY_WORK_BASE}/notify/slack/ts")
  else
    channel=$(slack_read_key "${NOTIFY_CONFIG_BASE}" slackChannelId)
    if [[ -z "${channel}" ]]; then
      echo "slack: slackChannelId not found in ${NOTIFY_CONFIG_BASE}" >&2
      return 1
    fi
    # A thread opened by an earlier run with the same key is joined, not duplicated
    if [[ -n "${NOTIFY_THREAD_KEY:-}" ]]; then
      thread_ts=$(slack_find_thread "${channel}" "${NOTIFY_THREAD_KEY}") || thread_ts=""
      if [[ -n "${thread_ts}" ]]; then
        slack_save_thread "${channel}" "${thread_ts}"
      fi
    fi
  fi

  local payload
  local response
  payload=$(slack_message_payload "${channel}" "${text}" "${thread_ts}" "${broadcast}" "${NOTIFY_THREAD_KEY:-}")
  response=$(slack_api chat.postMessage "${payload}") || return 1

  if [[ -z "${thread_ts}" ]]; then
    slack_save_thread "$(yq -p json '.channel' <<< "${response}")" "$(yq -p json '.ts' <<< "${response}")"
  fi
}

# Record the deploy thread for the rest of this run
slack_save_thread() {
  mkdir -p "${NOTIFY_WORK_BASE}/notify/slack"
  printf '%s\n' "$1" > "${NOTIFY_WORK_BASE}/notify/slack/channel"
  printf '%s\n' "$2" > "${NOTIFY_WORK_BASE}/notify/slack/ts"
}

# Print the ts of the newest message in the channel that opened a thread for
# the key, searching back slackThreadLookbackDays. Prints nothing if none.
# Gives up after 5 pages of 200 messages to keep the first post quick.
slack_find_thread() {
  local channel="$1"
  local key="$2"
  local days
  days=$(slack_read_key "${NOTIFY_CONFIG_BASE}" slackThreadLookbackDays)
  if [[ ! "${days}" =~ ^[0-9]+$ ]]; then
    days=$(slack_default slackThreadLookbackDays)
  fi
  local oldest=$(( $(date +%s) - days * 86400 ))

  local cursor=""
  local pages=0
  local args
  local response
  local ts
  while [[ "${pages}" -lt 5 ]]; do
    pages=$((pages + 1))
    args=("channel=${channel}" "oldest=${oldest}" "limit=200" "include_all_metadata=true")
    if [[ -n "${cursor}" ]]; then
      args+=("cursor=${cursor}")
    fi
    response=$(slack_api_get conversations.history "${args[@]}") || return 1

    ts=$(SLACK_THREAD_KEY="${key}" yq -p json '
      [.messages[] | select(.metadata.event_type == "kaptain_notify_thread" and
                            .metadata.event_payload.thread_key == strenv(SLACK_THREAD_KEY))][0].ts // ""
    ' <<< "${response}")
    if [[ -n "${ts}" ]]; then
      printf '%s\n' "${ts}"
      return 0
    fi

    cursor=$(yq -p json '.response_metadata.next_cursor // ""' <<< "${response}")
    if [[ -z "${cursor}" ]]; then
      return 0
    fi
  done
}

# Print the user IDs from a key such as slackFailureUserIds, one per line.
# Read directly rather than with slack_read_key so newlines also separate.
slack_user_ids() {
  local file="${NOTIFY_CONFIG_BASE}/$1"
  [[ -f "${file}" ]] || return 0
  tr -c 'A-Za-z0-9' '\n' < "${file}" | grep -v '^$' || true
}


# Expand tokens in a template. {user} becomes a mention of the given user ID,
# {NAME} becomes the value of env var NAME. Unset vars are left as {NAME} so a
# mistake shows. Values are inserted as is, never expanded again.
slack_expand() {
  local text="$1"
  local user_id="${2:-}"
  if [[ -n "${user_id}" ]]; then
    text="${text//\{user\}/<@${user_id}>}"
  fi

  local pattern='\{([A-Z_][A-Z0-9_]*)\}'
  local result=""
  local name
  while [[ "${text}" =~ ${pattern} ]]; do
    name="${BASH_REMATCH[1]}"
    result+="${text%%"{${name}}"*}"
    if [[ -n "${!name+set}" ]]; then
      result+="${!name}"
    else
      result+="{${name}}"
    fi
    text="${text#*"{${name}}"}"
  done
  printf '%s' "${result}${text}"
}

# DM every user in a key such as slackFailureUserIds. The leader template is
# expanded per user and goes above the body, which is sent as is. One failed DM
# does not stop the rest, but makes the return non-zero.
slack_dm_users() {
  local key="$1"
  local leader="$2"
  local body="$3"
  local failed=false
  local user_id
  local text
  for user_id in $(slack_user_ids "${key}"); do
    text="${body}"
    if [[ -n "${leader}" ]]; then
      text="$(slack_expand "${leader}" "${user_id}")

${body}"
    fi
    slack_post "${user_id}" "${text}" > /dev/null || failed=true
  done
  [[ "${failed}" == "false" ]]
}

# Print the link line for a DM, the expanded label template then the URL
slack_link_line() {
  local label
  label=$(slack_expand "$1")
  printf '%s' "${label:+${label} }$2"
}

# Print a link to a message
slack_permalink() {
  local channel="$1"
  local ts="$2"
  local response
  response=$(slack_api_get chat.getPermalink "channel=${channel}" "message_ts=${ts}") || return 1
  yq -p json '.permalink' <<< "${response}"
}

# Print a link to the message that opened the deploy thread
slack_thread_permalink() {
  [[ -f "${NOTIFY_WORK_BASE}/notify/slack/ts" ]] || return 1
  slack_permalink "$(cat "${NOTIFY_WORK_BASE}/notify/slack/channel")" "$(cat "${NOTIFY_WORK_BASE}/notify/slack/ts")"
}

# Add the reaction for a kind of message, a warning or an outcome, to the
# message that opened the deploy thread. The key is slack<Kind>Reaction, for
# example slackSuccessReaction. Surrounding colons are optional,
# Slack wants the bare name. A reaction already there is not an error, so a
# thread with ten warnings shows one.
slack_thread_react_for() {
  local kind="$1"
  local name
  name=$(slack_setting "slack${kind}Reaction")
  name="${name#:}"
  name="${name%:}"
  if [[ -n "${name}" ]]; then
    slack_thread_react "${name}"
  fi
}

# Add a reaction to the message that opened the deploy thread
slack_thread_react() {
  local name="$1"
  if [[ ! -f "${NOTIFY_WORK_BASE}/notify/slack/ts" ]]; then
    echo "slack: no deploy thread to react to" >&2
    return 1
  fi

  # A reused thread may already carry this reaction from an earlier run
  local slack_tolerated_error=already_reacted
  local payload
  payload=$(SLACK_CHANNEL="$(cat "${NOTIFY_WORK_BASE}/notify/slack/channel")" \
            SLACK_TS="$(cat "${NOTIFY_WORK_BASE}/notify/slack/ts")" \
            SLACK_NAME="${name}" \
            yq -n -o json -I0 '.channel = strenv(SLACK_CHANNEL) | .timestamp = strenv(SLACK_TS) | .name = strenv(SLACK_NAME)')
  slack_api reactions.add "${payload}" > /dev/null
}
