#!/usr/bin/env bash
# PostToolUse(Edit|Write): flag float types on money-named identifiers.
# Override a reviewed line with a `lint:allow-float` comment.
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
    *.ts | *.tsx) printf '%s' "(^|[^A-Za-z0-9_])${ID}\??[[:space:]]*:[[:space:]]*number" ;;
    *.py) printf '%s' "(^|[^A-Za-z0-9_])${ID}[[:space:]]*:[[:space:]]*float|${ID}[[:space:]]*=[[:space:]]*float\(" ;;
  esac
}

main() {
  local file pattern hits
  read_input
  file=$(json_get '.tool_input.file_path')
  pattern=$(pattern_for "$file")
  [ -n "$pattern" ] || exit 0
  hits=$(edited_text | grep -v 'lint:allow-float' | grep -E "$pattern")
  [ -n "$hits" ] || exit 0
  block "Float type on a money value in $file:
$hits
Use int64 minor units + currency, or a decimal type (see numeric-correctness).
If this is not money, add a 'lint:allow-float' comment on the line."
}

main
