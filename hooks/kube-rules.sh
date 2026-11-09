#!/usr/bin/env bash
# kubectl rules for guard-bash.sh (sourced, not a hook): on a prod cluster only
# read verbs run. Anything the guard can't read with certainty is refused.

# Verbs safe on prod; two-word reads are matched as "verb:sub".
KUBE_READ=" get describe logs top explain api-resources api-versions version cluster-info diff wait events "
KUBE_READ_SUB=" auth:can-i auth:whoami config:view config:get-contexts config:current-context config:get-clusters "
# Options kubectl accepts before the verb: the ones taking a value, then flags.
KUBE_OPT_VALUE=" --context --kubeconfig --cluster --user --server -s -n --namespace --as --as-group --as-uid --token --request-timeout --certificate-authority --client-certificate --client-key --tls-server-name --cache-dir --log-file -v --v --profile --profile-output "
KUBE_OPT_FLAG=" --insecure-skip-tls-verify --match-server-version --warnings-as-errors --disable-compression "

# kube_files <cwd> <colon list>: each kubeconfig path, ~ and relative paths resolved.
kube_files() {
  local f
  local IFS=:
  for f in $2; do
    f="${f/#\~/$HOME}"
    [[ "$f" == /* ]] || f="$1/$f"
    printf '%s\n' "$f"
  done
}

# kube_current_context <file...>: the current-context of the first file that sets one.
kube_current_context() {
  local f ctx
  for f in "$@"; do
    ctx=$(sed -n 's/^current-context:[[:space:]]*//p' "$f" 2>/dev/null | head -n 1 | tr -d "\"'")
    [ -n "$ctx" ] && { printf '%s' "$ctx"; return 0; }
  done
  return 1
}

# kube_cluster_of <context> <file...>: the cluster a context points to.
kube_cluster_of() {
  local want="$1"
  shift
  awk -v want="$want" '
    function flush() { if (name == want) { print cluster; found = 1; exit } name = ""; cluster = "" }
    /^contexts:/ { in_ctx = 1; next }
    /^[^ -]/ { if (in_ctx) flush(); in_ctx = 0 }
    in_ctx && /^- / { flush() }
    in_ctx && /^[ -]+cluster:/ { v = $0; sub(/^[ -]+cluster:[ ]*/, "", v); cluster = v }
    in_ctx && /^[ -]+name:/ { v = $0; sub(/^[ -]+name:[ ]*/, "", v); name = v }
    END { if (!found && in_ctx) flush() }
  ' "$@" 2>/dev/null | head -n 1
}

# The command switches context or kubeconfig before a later kubectl call can run.
kube_switches() {
  printf '%s' "$1" | grep -Eq 'kubectl([[:space:]]+[^[:space:]]+)*[[:space:]]+config[[:space:]]+(use-context|set-context|set-cluster|set-credentials|rename-context)|(export|declare|typeset)[[:space:]].*KUBECONFIG=|(^|[;&|][[:space:]]*)KUBECONFIG=[^[:space:]]*[[:space:]]*($|[;&|])'
}

# check_kubectl <seg> <cwd> <cmd>
check_kubectl() {
  local seg="$1" cwd="$2" words w i=0 found=0 unknown=0 ctx="" kcfg="" envcfg="" verb="" sub="" extra="" name val cluster
  local -a files
  set -f
  read -r -a words <<<"$seg"
  set +f
  while [ "$i" -lt "${#words[@]}" ]; do
    w="${words[$i]}"
    i=$((i + 1))
    if [ "$found" = 0 ]; then
      case "$w" in KUBECONFIG=*) envcfg="${w#*=}" ;; kubectl) found=1 ;; esac
      continue
    fi
    [ "$w" = -- ] && break
    case "$w" in
      -*=*) name="${w%%=*}" val="${w#*=}" ;;
      -*) name=$w val="" ;;
      *)
        if [ -z "$verb" ]; then verb=$w; elif [ -z "$sub" ]; then sub=$w; fi
        continue
        ;;
    esac
    case "$KUBE_OPT_FLAG" in *" $name "*) continue ;; esac
    if [ -n "$verb" ]; then
      # After the verb, only the options that pick the target cluster matter.
      case "$name" in --context | --kubeconfig | --cluster | --user | --server | -s) ;; *) continue ;; esac
    else
      case "$KUBE_OPT_VALUE" in *" $name "*) ;; *) unknown=1 && continue ;; esac
    fi
    [ -n "$val" ] || { val="${words[$i]:-}"; [[ "$w" == *=* ]] || i=$((i + 1)); }
    case "$name" in
      --context) ctx=$val ;;
      --kubeconfig) kcfg=$val ;;
      --cluster | --user | --server | -s) extra="$extra $val" ;;
    esac
  done
  [ "$found" = 1 ] || return 0
  if [ "$unknown" = 0 ]; then
    case "$KUBE_READ" in *" $verb "*) return 0 ;; esac
    case "$KUBE_READ_SUB" in *" $verb:$sub "*) return 0 ;; esac
  fi
  # A write, or a verb that can't be read with certainty: is the target prod?
  [ "$verb" != config ] && kube_switches "$3" &&
    deny "this command switches kubectl context or kubeconfig and then runs kubectl $verb; run them separately" "$seg"
  files=()
  while IFS= read -r w; do files+=("$w"); done < <(kube_files "$cwd" "${kcfg:-${envcfg:-${KUBECONFIG:-$HOME/.kube/config}}}")
  [ -n "$ctx" ] || ctx=$(kube_current_context "${files[@]}") ||
    deny "kubectl $verb: can't tell which context it would use" "$seg"
  cluster=$(kube_cluster_of "$ctx" "${files[@]}")
  case "$(lower "$ctx $cluster $extra")" in
    *prod*) deny "kubectl ${verb:-?} against prod (context '$ctx'); prod is read-only for agents" "$seg" ;;
  esac
  return 0
}
