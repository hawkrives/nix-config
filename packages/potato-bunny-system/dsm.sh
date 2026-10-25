# shellcheck shell=bash disable=SC2016 # jq filters reference $vars passed with --arg
# DSM reconcile steps for activate.sh, which this file is concatenated ahead
# of: function definitions only. They read activate's globals (GEN,
# DRY_RUN, SYNOWEBAPI, SYNOPKG) and its log helper.
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
# (what DSM's UI uses). Scheduled tasks are dsm_scheduled_tasks'. These run
# before units start, at boot too, so a failure is recorded, not fatal.
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
    if ! have=$(webapi SYNO.Core.EventScheduler 1 get task_name="$name_json") || ! jq -e .success <<<"$have" >/dev/null; then
      dsm_fail "reading DSM task \"$task\""
      continue
    fi
    have=$(jq -c '.data // empty | {event, operation, enable, notify_enable, notify_if_error, notify_mail, owner, depend_on_task}' <<<"$have")
    [ "$have" = "$want" ] && continue
    if [ -z "$have" ]; then method="create"; else method="set"; fi
    args=(task_name="$name_json" operation_type='"script"')
    # One key=<json> argument per field. (Not via @tsv: it escapes newlines and
    # backslashes, which then reach DSM literally.)
    while IFS= read -r key; do
      args+=("$key=$(jq -c --arg k "$key" '.[$k]' <<<"$want")")
    done < <(jq -r 'keys[]' <<<"$want")
    dsm_change "$method DSM task \"$task\"" webapi_ok SYNO.Core.EventScheduler 1 "$method" "${args[@]}" ||
      dsm_fail "DSM refused to $method task \"$task\""
  done < <(jq -r 'to_entries[] | select(.value.event != "schedule") | .key' "$GEN/dsm-tasks.json")
}

# ---------------------------------------------------------------- packages, settings, scheduled tasks

# share_grants <share> <name json> <verb> <users|groups> <local_user|local_group>:
# set each declared grant ("rw", "ro" or "none") that differs from DSM's. A
# name DSM lists nothing for has no access.
share_grants() {
  local share=$1 name_json=$2 verb=$3 kind=$4 type=$5 grants perms name
  [ "$(jq --arg s "$share" --arg k "$kind" '.[$s][$k] | length' "$GEN/dsm-shares.json")" -gt 0 ] || return 0
  # A share only just planned in a dry run has no grants to read yet.
  if $DRY_RUN && [ "$verb" = create ]; then
    grants='[]'
  elif ! grants=$(webapi SYNO.Core.Share.Permission 1 list name="$name_json" user_group_type="\"$type\"") ||
    ! jq -e .success <<<"$grants" >/dev/null; then
    dsm_fail "reading $kind grants on share $share"
    return 0
  else
    grants=$(jq -c '.data.items' <<<"$grants")
  fi
  perms=$(jq -c --arg s "$share" --arg k "$kind" --argjson have "$grants" '.[$s][$k] | to_entries
    | map({name: .key, is_readonly: (.value == "ro"), is_writable: (.value == "rw"), is_deny: false, is_custom: false})
    | map(. as $w | select(($have | map(select(.name == $w.name)) | first
        // {name: $w.name, is_readonly: false, is_writable: false, is_deny: false, is_custom: false}
        | {name, is_readonly, is_writable, is_deny, is_custom}) != $w))' "$GEN/dsm-shares.json")
  [ "$perms" = "[]" ] && return 0
  while IFS= read -r name; do
    dsm_change "grant ${kind%s} $name $(jq -r --arg s "$share" --arg k "$kind" --arg n "$name" '.[$s][$k][$n]' "$GEN/dsm-shares.json") on share $share" true
  done < <(jq -r '.[].name' <<<"$perms")
  $DRY_RUN && return 0
  webapi_ok SYNO.Core.Share.Permission 1 set name="$name_json" user_group_type="\"$type\"" permissions="$perms" ||
    dsm_fail "setting $kind grants on share $share"
}

# Shared folders: created if missing, set when a declared field differs (never
# moved: a share on another volume is reported), then each declared user and
# group grant set if it differs. DSM's get reports the quota as quota_value
# while create/set take share_quota, both in MB. Undeclared shares and grants
# stay as they are; nothing is deleted.
dsm_shares() {
  local share name_json have want info verb
  while IFS= read -r share; do
    [ -n "$share" ] || continue
    name_json=$(jq -n --arg s "$share" '$s')
    want=$(jq -c --arg s "$share" '.[$s] | {vol_path: .volume, desc: .description, hidden,
      enable_recycle_bin: .recycleBin, quota_value: (.quotaMB // 0)}' "$GEN/dsm-shares.json")
    if ! have=$(webapi SYNO.Core.Share 1 get name="$name_json" additional='["hidden","recyclebin","share_quota"]'); then
      dsm_fail "reading share $share"
      continue
    fi
    if jq -e '.success' <<<"$have" >/dev/null; then
      have=$(jq -c '.data | {vol_path, desc, hidden, enable_recycle_bin, quota_value}' <<<"$have")
      # A set with another vol_path is DSM's move-share, which would move the
      # share's data: report it instead.
      if [ "$(jq -r .vol_path <<<"$have")" != "$(jq -r .vol_path <<<"$want")" ]; then
        dsm_fail "share $share is on $(jq -r .vol_path <<<"$have"), declared on $(jq -r .vol_path <<<"$want"); move it in DSM"
        continue
      fi
      verb=""
      [ "$have" = "$want" ] || verb="set"
    elif [ "$(jq -r '.error.code // empty' <<<"$have")" = 402 ]; then
      verb="create"
    else
      dsm_fail "reading share $share"
      continue
    fi
    if [ -n "$verb" ]; then
      info=$(jq -c --arg s "$share" '{name: $s, vol_path, desc, hidden, enable_recycle_bin,
        share_quota: (.quota_value | tostring)}' <<<"$want")
      if ! dsm_change "$verb share $share on $(jq -r .vol_path <<<"$want")" \
        webapi_ok SYNO.Core.Share 1 "$verb" name="$name_json" shareinfo="$info"; then
        dsm_fail "${verb}ing share $share"
        continue
      fi
    fi
    share_grants "$share" "$name_json" "$verb" users local_user
    share_grants "$share" "$name_json" "$verb" groups local_group
  done < <(jq -r 'keys[]' "$GEN/dsm-shares.json")
}

# Package Center feeds: each declared URL is added if no feed has it. Feeds
# added by hand stay.
dsm_feeds() {
  local have name url
  [ "$(jq length "$GEN/dsm-feeds.json")" -gt 0 ] || return 0
  if ! have=$(webapi SYNO.Core.Package.Feed 1 list) || ! jq -e .success <<<"$have" >/dev/null; then
    dsm_fail "listing package feeds"
    return 0
  fi
  while IFS=$'\t' read -r name url; do
    jq -e --arg u "$url" 'any(.data.items[]?; .feed == $u)' <<<"$have" >/dev/null && continue
    dsm_change "add package feed $name ($url)" \
      webapi_ok SYNO.Core.Package.Feed 1 add name="$(jq -n --arg v "$name" '$v')" feed="$(jq -n --arg v "$url" '$v')" ||
      dsm_fail "adding package feed $name"
  done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' "$GEN/dsm-feeds.json")
}

# Packages of services with enable = true, and with enable = false (to stop),
# as "<service>\t<package id>\t<enable>\t<volume>" lines.
managed_packages() {
  jq -r 'to_entries[] | select(.value.package != null and .value.enable != null)
    | [.key, .value.package, (.value.enable | tostring), .value.volume] | @tsv' "$GEN/dsm-services.json"
}

pkg_running() { "$SYNOPKG" is_onoff "$1" >/dev/null 2>&1; }
synopkg_quiet() { "$SYNOPKG" "$@" >/dev/null; }

# Installed package ids, listed once per run. If DSM can't list them (its
# package lock is held, say), the package steps do nothing rather than guess.
DSM_INSTALLED=""
DSM_PKG_LIST_OK=false
# Packages whose install failed this run; dsm_run_state skips them.
DSM_INSTALL_FAILED=" "

dsm_packages() {
  local service id enable volume
  [ -n "$(managed_packages)" ] || return 0
  if ! DSM_INSTALLED=$("$SYNOPKG" list --name 2>/dev/null); then
    dsm_fail "listing installed packages"
    return 0
  fi
  DSM_PKG_LIST_OK=true
  while IFS=$'\t' read -r service id enable volume; do
    [ "$enable" = true ] || continue
    grep -qxF "$id" <<<"$DSM_INSTALLED" && continue
    if ! dsm_change "install $id ($service) on $volume" synopkg_quiet install_from_server "$id" "$volume"; then
      dsm_fail "installing $id ($service)"
      DSM_INSTALL_FAILED+="$id "
    fi
  done < <(managed_packages)
}

# Start enabled packages and stop disabled ones. Never uninstalls.
dsm_run_state() {
  local service id enable volume
  $DSM_PKG_LIST_OK || return 0
  while IFS=$'\t' read -r service id enable volume; do
    case "$DSM_INSTALL_FAILED" in *" $id "*) continue ;; esac
    if [ "$enable" = true ]; then
      if ! pkg_running "$id"; then
        dsm_change "start $id ($service)" synopkg_quiet start "$id" || dsm_fail "starting $id ($service)"
      fi
    elif pkg_running "$id"; then
      dsm_change "stop $id ($service)" synopkg_quiet stop "$id" || dsm_fail "stopping $id ($service)"
    fi
  done < <(managed_packages)
}

# Feature settings: read the current object, and if any declared key differs
# (compared as JSON), send one set with every declared key. Keys not declared
# are never sent.
dsm_settings() {
  local name api version have unknown changes line key args
  while IFS=$'\t' read -r name api version; do
    if ! have=$(webapi "$api" "$version" get) || ! jq -e .success <<<"$have" >/dev/null; then
      dsm_fail "reading $name settings ($api)"
      continue
    fi
    # A declared key DSM doesn't return is most likely a typo; sending it would
    # repeat on every deploy without changing anything.
    unknown=$(jq -r --arg n "$name" --argjson have "$have" '[.[$n].settings | keys[] | select(. as $k | $have.data | has($k) | not)] | join(", ")' "$GEN/dsm-services.json")
    if [ -n "$unknown" ]; then
      dsm_fail "$name settings: $api has no $unknown"
      continue
    fi
    changes=$(jq -r --arg n "$name" --argjson have "$have" '.[$n].settings | to_entries[]
      | select(.value != $have.data[.key])
      | "set \($n): \(.key) \($have.data[.key] | tojson) -> \(.value | tojson)"' "$GEN/dsm-services.json")
    [ -n "$changes" ] || continue
    if $DRY_RUN; then
      while IFS= read -r line; do echo "would: $line"; done <<<"$changes"
      DSM_PLANNED=true
      continue
    fi
    while IFS= read -r line; do log "$line"; done <<<"$changes"
    args=()
    while IFS= read -r key; do
      args+=("$key=$(jq -c --arg n "$name" --arg k "$key" '.[$n].settings[$k]' "$GEN/dsm-services.json")")
    done < <(jq -r --arg n "$name" '.[$n].settings | keys[]' "$GEN/dsm-services.json")
    webapi_ok "$api" "$version" set "${args[@]}" || dsm_fail "setting $name settings ($api)"
  done < <(jq -r 'to_entries[] | select(.value.settingsApi != null and .value.settings != {})
    | [.key, .value.settingsApi.api, (.value.settingsApi.version | tostring)] | @tsv' "$GEN/dsm-services.json")
}
# Scheduled script tasks, through the TaskScheduler API. DSM's names aren't
# unique (apps add their own tasks, sometimes several with one name), so a
# task matches by name and type "script"; more than one match is an error.
# Root-owned tasks are created and set through TaskScheduler.Root, as DSM's
# UI does.
dsm_scheduled_tasks() {
  local list task matches id real_owner want have today args
  [ "$(jq '[.[] | select(.event == "schedule")] | length' "$GEN/dsm-tasks.json")" -gt 0 ] || return 0
  if ! list=$(webapi SYNO.Core.TaskScheduler 3 list) || ! jq -e .success <<<"$list" >/dev/null; then
    dsm_fail "listing scheduled tasks"
    return 0
  fi
  today=$(date +%Y/%-m/%-d)
  while IFS= read -r task; do
    # The fields compared, in DSM's shape. last_work_hour is the first hour
    # for a task that runs once a day.
    want=$(jq -c --arg t "$task" '.[$t] | .schedule as $s | {
        enable, owner: "root",
        extra: {script: .script, notify_enable: .notifyOnError, notify_if_error: .notifyOnError, notify_mail: .notifyMail},
        schedule: {
          date_type: 0, week_day: ($s.weekDays | unique | map(tostring) | join(",")),
          hour: $s.hour, minute: $s.minute,
          repeat_hour: ($s.repeatHours // 0), repeat_min: ($s.repeatMinutes // 0),
          last_work_hour: (if $s.repeatHours == null and $s.repeatMinutes == null then $s.hour else $s.lastHour end)
        }
      }' "$GEN/dsm-tasks.json")
    matches=$(jq -c --arg t "$task" '[.data.tasks[]? | select(.name == $t and .type == "script")]' <<<"$list")
    case "$(jq length <<<"$matches")" in
      0) id="" ;;
      1)
        id=$(jq -r '.[0].id' <<<"$matches")
        real_owner=$(jq -c '.[0].real_owner' <<<"$matches")
        if ! have=$(webapi SYNO.Core.TaskScheduler 4 get id="$id" real_owner="$real_owner") || ! jq -e .success <<<"$have" >/dev/null; then
          dsm_fail "reading scheduled task \"$task\""
          continue
        fi
        have=$(jq -c '.data | {
            enable, owner,
            extra: (.extra | {script, notify_enable, notify_if_error, notify_mail}),
            schedule: (.schedule | {date_type, week_day, hour, minute, repeat_hour, repeat_min, last_work_hour})
          }' <<<"$have")
        [ "$have" = "$want" ] && continue
        ;;
      *)
        dsm_fail "scheduled task \"$task\": $(jq length <<<"$matches") DSM script tasks have this name"
        continue
        ;;
    esac
    args=(
      name="$(jq -n --arg t "$task" '$t')"
      owner='"root"'
      enable="$(jq -c .enable <<<"$want")"
      extra="$(jq -c .extra <<<"$want")"
      schedule="$(jq -c --arg d "$today" '.schedule + {repeat_date: 1001, date: $d}' <<<"$want")"
    )
    if [ -z "$id" ]; then
      dsm_change "create scheduled task \"$task\"" \
        webapi_ok SYNO.Core.TaskScheduler.Root 4 create type='"script"' "${args[@]}" ||
        dsm_fail "creating scheduled task \"$task\""
    else
      # A refused set (an owner DSM won't change in place, say) is an error;
      # the task is never deleted and recreated.
      dsm_change "update scheduled task \"$task\"" \
        webapi_ok SYNO.Core.TaskScheduler.Root 4 set id="$id" real_owner="$real_owner" "${args[@]}" ||
        dsm_fail "updating scheduled task \"$task\""
    fi
  done < <(jq -r 'to_entries[] | select(.value.event == "schedule") | .key' "$GEN/dsm-tasks.json")
}

# The deploy-time DSM steps, in dependency order: shares first (service data
# lives in them), a package's feed before installing it, settings before
# starting it.
dsm_apply() {
  dsm_shares
  dsm_feeds
  dsm_packages
  dsm_settings
  dsm_run_state
  dsm_scheduled_tasks
}
