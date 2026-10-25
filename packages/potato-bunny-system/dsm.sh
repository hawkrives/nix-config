# shellcheck shell=bash disable=SC2016 # jq filters reference $vars passed with --arg
# DSM reconcile steps for activate.sh, which this file is concatenated ahead
# of: function definitions only. They read activate's globals (GEN,
# DRY_RUN, SYNOWEBAPI, SYNOPKG) and its log/die helpers.
#
# Every change goes through dsm_change, so a dry run prints exactly what a
# real run would do and changes nothing. Nothing here uninstalls a package or
# deletes a feed or task.

DSM_FAILURES=()

# dsm_change <description> <command> [args...]
dsm_change() {
  local desc=$1
  shift
  if $DRY_RUN; then
    echo "would: $desc"
    DSM_PLANNED=true
    return 0
  fi
  log "$desc"
  "$@"
}

# dsm_fail <description>: record a failure; activate exits non-zero at the end.
dsm_fail() {
  DSM_FAILURES+=("$1")
  log "error: $1"
}

# webapi <api> <version> <method> [key=<json>...]: one DSM web API call as
# root, its JSON on stdout.
webapi() {
  "$SYNOWEBAPI" --exec api="$1" version="$2" method="$3" "${@:4}" 2>/dev/null
}

# webapi_ok <api> <version> <method> [key=<json>...]: the call, succeeding
# only if DSM reports success.
webapi_ok() {
  webapi "$@" | jq -e .success >/dev/null
}

# ---------------------------------------------------------------- boot-up/shutdown tasks

# DSM Task Scheduler boot-up/shutdown tasks, through the EventScheduler API
# (what DSM's UI uses). Scheduled tasks are dsm_scheduled_tasks'.
dsm_event_tasks() {
  local task want name_json have method args key
  while IFS= read -r task; do
    [ -n "$task" ] || continue
    want=$(jq -c --arg t "$task" '.[$t] | {
        event, operation: .script, enable,
        notify_enable: .notifyOnError, notify_if_error: .notifyOnError, notify_mail: .notifyMail,
        owner: {"0": "root"},
        depend_on_task: (if .dependsOn == null then "" else "[" + .dependsOn + "]" end)
      }' "$GEN/dsm-tasks.json")
    name_json=$(jq -n --arg t "$task" '$t')
    have=$(webapi SYNO.Core.EventScheduler 1 get task_name="$name_json" |
      jq -c '.data // empty | {event, operation, enable, notify_enable, notify_if_error, notify_mail, owner, depend_on_task}')
    [ "$have" = "$want" ] && continue
    if [ -z "$have" ]; then method="create"; else method="set"; fi
    args=(task_name="$name_json" operation_type='"script"')
    # One key=<json> argument per field. (Not via @tsv: it escapes newlines and
    # backslashes, which then reach DSM literally.)
    while IFS= read -r key; do
      args+=("$key=$(jq -c --arg k "$key" '.[$k]' <<<"$want")")
    done < <(jq -r 'keys[]' <<<"$want")
    dsm_change "$method DSM task \"$task\"" webapi_ok SYNO.Core.EventScheduler 1 "$method" "${args[@]}" ||
      die "DSM refused to $method task \"$task\""
  done < <(jq -r 'to_entries[] | select(.value.event != "schedule") | .key' "$GEN/dsm-tasks.json")
}

# ---------------------------------------------------------------- packages, settings, scheduled tasks

dsm_feeds() { :; }
dsm_packages() { :; }
dsm_settings() { :; }
dsm_run_state() { :; }
dsm_scheduled_tasks() { :; }

# The deploy-time DSM steps, in dependency order: a package's feed before
# installing it, settings before starting it.
dsm_apply() {
  dsm_feeds
  dsm_packages
  dsm_settings
  dsm_run_state
  dsm_scheduled_tasks
}
