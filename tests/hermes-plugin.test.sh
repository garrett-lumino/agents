#!/usr/bin/env bash
# agents-hooks Hermes plugin (hermes/plugins/agents-hooks): see hermes_plugin_test.py.
set -u
cd "$(dirname "$0")/.." || exit 1
if python3 -I -B tests/hermes_plugin_test.py 2>"${TMPDIR:-/tmp}/hermes-plugin-test.$$"; then
  tail -n 1 "${TMPDIR:-/tmp}/hermes-plugin-test.$$" | sed 's/^/hermes-plugin.test.sh: /'
  rm -f "${TMPDIR:-/tmp}/hermes-plugin-test.$$"
else
  cat "${TMPDIR:-/tmp}/hermes-plugin-test.$$"
  rm -f "${TMPDIR:-/tmp}/hermes-plugin-test.$$"
  exit 1
fi
