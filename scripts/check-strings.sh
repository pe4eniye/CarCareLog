#!/bin/bash
# Fails if the code uses a localization key that is missing from Localization/strings.tsv,
# or if the generated String Catalog is out of date with the TSV.
set -euo pipefail
cd "$(dirname "$0")/.."

used=$(grep -rhoE 'L10n\.[tf]\("[^"]+"' App Widget | sed -E 's/L10n\.[tf]\("//; s/"$//' | sort -u)
defined=$(tail -n +2 Localization/strings.tsv | cut -f1 | sort -u)

missing=$(comm -23 <(echo "$used") <(echo "$defined"))
if [ -n "$missing" ]; then
  echo "Missing translations in Localization/strings.tsv:"
  echo "$missing"
  exit 1
fi

catalog=$(grep -oE '^    "[^"]+" : \{' App/Resources/Localizable.xcstrings | sed -E 's/^    "//; s/" : \{$//' | sort -u)
if [ "$catalog" != "$defined" ]; then
  echo "App/Resources/Localizable.xcstrings is out of date. Run scripts/gen-strings.ps1."
  diff <(echo "$defined") <(echo "$catalog") || true
  exit 1
fi
echo "Localization OK: $(echo "$defined" | wc -l | tr -d ' ') keys"
