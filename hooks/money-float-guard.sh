#!/usr/bin/env bash
# PostToolUse(Edit|Write): money is integer minor units (cents), never float dollars.
#   Go/Python: flag float types on money-named identifiers (the type shows intent).
#   TS: `number` is the only numeric type and is correct for integer cents, so flag
#       what *creates* float money instead: parseFloat, cents<->dollars /100 *100.
# Override a reviewed line (e.g. the one display formatter) with `lint:allow-float`.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

# Money word inside an identifier; after it only nothing, plural s, or a new
# camel/snake segment (so "feed" or "pricey" don't match "fee"/"price").
WORD='(Amount|amount|AMOUNT|Price|price|PRICE|Fee|fee|FEE|Balance|balance|Cents|cents|Money|money|Subtotal|subtotal|Payout|payout|Refund|refund)'
ID="[A-Za-z0-9_]*${WORD}(s|[A-Z0-9_][A-Za-z0-9_]*)?"

pattern_for() {
  case "$1" in
    *.go) printf '%s' "(^|[^A-Za-z0-9_])${ID}[[:space:]]+(\*|\[\])?float(32|64)|${ID}[[:space:]]*:?=[[:space:]]*float(32|64)\(" ;;
    *.ts | *.tsx) printf '%s' "(Number\.)?parseFloat\([^)]*${ID}|${ID}[[:space:]]*[*/][[:space:]]*100([^0-9.]|$)|100[[:space:]]*\*[[:space:]]*${ID}" ;;
    *.py) printf '%s' "(^|[^A-Za-z0-9_])${ID}[[:space:]]*:[[:space:]]*float|${ID}[[:space:]]*=[[:space:]]*float\(" ;;
  esac
}

# TS cents->dollars is fine at the display edge (Intl .format, toLocaleString, toFixed).
drop_display_lines() {
  case "$1" in
    *.ts | *.tsx) grep -Ev '\.format\(|toLocaleString\(|\.toFixed\(' ;;
    *) cat ;;
  esac
}

main() {
  local file pattern hits
  read_input
  file=$(json_get '.tool_input.file_path')
  pattern=$(pattern_for "$file")
  [ -n "$pattern" ] || exit 0
  hits=$(edited_text | grep -v 'lint:allow-float' | grep -E "$pattern" | drop_display_lines "$file")
  [ -n "$hits" ] || exit 0
  block "Float money in $file:
$hits
Keep money as integer minor units (cents) + currency; convert to dollars only in one
display formatter (see numeric-correctness). If reviewed, add 'lint:allow-float' on the line."
}

main
