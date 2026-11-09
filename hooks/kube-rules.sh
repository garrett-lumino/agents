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

# kube_has_context <context> <file...>: the context is defined in one of the kubeconfigs.
kube_has_context() {
  local want="$1"
  shift
  awk -v want="$want" '/^contexts:/ { c = 1; next } /^[^ -]/ { c = 0 }
    c && /^[ -]+name:/ { v = $0; sub(/^[ -]+name:[ ]*/, "", v); if (v == want) { f = 1; exit } }
    END { exit !f }' "$@" 2>/dev/null
}

# kube_parse <seg>: read a kubectl call into KP_FOUND KP_VERB KP_SUB KP_CTX KP_KCFG KP_ENVCFG
# KP_EXTRA (cluster/server/user values) and KP_UNKNOWN (1 when the verb can't be trusted).
kube_parse() {
  local words w i=0 name val
  KP_FOUND=0 KP_UNKNOWN=0 KP_VERB="" KP_SUB="" KP_CTX="" KP_KCFG="" KP_ENVCFG="" KP_EXTRA=""
  set -f
  read -r -a words <<<"$1"
  set +f
  while [ "$i" -lt "${#words[@]}" ]; do
    w="${words[$i]}"
    i=$((i + 1))
    if [ "$KP_FOUND" = 0 ]; then
      case "$w" in KUBECONFIG=*) KP_ENVCFG="${w#*=}" ;; kubectl) KP_FOUND=1 ;; esac
      continue
    fi
    [ "$w" = -- ] && break
    case "$w" in
      -*=*) name="${w%%=*}" val="${w#*=}" ;;
      -*) name=$w val="" ;;
      *)
        if [ -z "$KP_VERB" ]; then KP_VERB=$w; elif [ -z "$KP_SUB" ]; then KP_SUB=$w; fi
        continue
        ;;
    esac
    # An option between auth/config and its subcommand could hide which subcommand runs.
    case "$KP_VERB" in auth | config) [ -n "$KP_SUB" ] || KP_UNKNOWN=1 ;; esac
    case "$KUBE_OPT_FLAG" in *" $name "*) continue ;; esac
    if [ -n "$KP_VERB" ]; then
      # After the verb, only the options that pick the target cluster matter.
      case "$name" in --context | --kubeconfig | --cluster | --user | --server | -s) ;; *) continue ;; esac
    else
      case "$KUBE_OPT_VALUE" in *" $name "*) ;; *) KP_UNKNOWN=1 && continue ;; esac
    fi
    [ -n "$val" ] || { val="${words[$i]:-}"; [[ "$w" == *=* ]] || i=$((i + 1)); }
    case "$name" in
      --context) KP_CTX=$val ;;
      --kubeconfig) KP_KCFG=$val ;;
      --cluster | --user | --server | -s) KP_EXTRA="$KP_EXTRA $val" ;;
    esac
  done
}

# check_kubectl <seg> <cwd> <cmd>
check_kubectl() {
  local seg="$1" ctx cluster w
  local -a files
  kube_parse "$seg"
  [ "$KP_FOUND" = 1 ] || return 0
  if [ "$KP_UNKNOWN" = 0 ]; then
    case "$KUBE_READ" in *" $KP_VERB "*) return 0 ;; esac
    case "$KUBE_READ_SUB" in *" $KP_VERB:$KP_SUB "*) return 0 ;; esac
  fi
  # A write, or a verb that can't be read with certainty: is the target prod?
  [ "$KP_VERB" != config ] && kube_switches "$3" &&
    deny "this command switches kubectl context or kubeconfig and then runs kubectl $KP_VERB; run them separately" "$seg"
  [[ "$KP_CTX $KP_KCFG $KP_ENVCFG $KP_EXTRA" =~ [\"\'\$\`\\*?[] ]] &&
    deny "kubectl $KP_VERB: the target (context, kubeconfig, cluster, server or user) is quoted or expanded, so it can't be checked" "$seg"
  files=()
  while IFS= read -r w; do files+=("$w"); done < <(kube_files "$2" "${KP_KCFG:-${KP_ENVCFG:-${KUBECONFIG:-$HOME/.kube/config}}}")
  if [ -n "$KP_CTX" ]; then
    ctx=$KP_CTX
    kube_has_context "$ctx" "${files[@]}" || deny "kubectl $KP_VERB: context '$ctx' is not in the kubeconfig" "$seg"
  else
    ctx=$(kube_current_context "${files[@]}") || deny "kubectl $KP_VERB: can't tell which context it would use" "$seg"
  fi
  cluster=$(kube_cluster_of "$ctx" "${files[@]}")
  case "$(lower "$ctx $cluster $KP_EXTRA")" in
    *prod*) deny "kubectl ${KP_VERB:-?} against prod (context '$ctx'); prod is read-only for agents" "$seg" ;;
  esac
  return 0
}
