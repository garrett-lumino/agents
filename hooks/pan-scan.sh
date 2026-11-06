#!/usr/bin/env bash
# Find card numbers (PANs): 13-19 digit runs (single spaces/dashes allowed) that
# start with 2-6 and pass the Luhn check. Prints file:line with the PAN masked.
# Usage: pan-scan.sh [file...]   (no files: read stdin)
# Exit: 0 no hits, 1 hits found.
set -u

scan() {
  awk '
    function luhn(s,   i, d, sum, alt) {
      sum = 0; alt = 0
      for (i = length(s); i >= 1; i--) {
        d = substr(s, i, 1) + 0
        if (alt) { d *= 2; if (d > 9) d -= 9 }
        sum += d; alt = !alt
      }
      return sum % 10 == 0
    }
    function mask(s) { return substr(s, 1, 6) "******" substr(s, length(s) - 3) }
    {
      src = FILENAME
      if (src == "" || src == "-") src = "stdin"
      line = $0
      while (match(line, /[0-9]([ -]?[0-9])+/)) {
        run = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        gsub(/[ -]/, "", run)
        n = length(run)
        if (n >= 13 && n <= 19 && substr(run, 1, 1) ~ /[2-6]/ && luhn(run)) {
          printf "%s:%d: possible PAN %s\n", src, FNR, mask(run)
          hits++
        }
      }
    }
    END { exit hits > 0 ? 1 : 0 }
  ' "$@"
}

scan "$@"
