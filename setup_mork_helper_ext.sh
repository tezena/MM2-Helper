#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPSTREAM_URL="${MORK_UPSTREAM_URL:-https://github.com/trueagi-io/MORK}"
HELPER_EXT_SRC="$SCRIPT_DIR/helper_ext.rs"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 /absolute/path/to/MORK" >&2
  exit 1
fi

MORK_DIR="$1"

if [[ ! -f "$HELPER_EXT_SRC" ]]; then
  echo "ERROR: helper_ext.rs not found at $HELPER_EXT_SRC" >&2
  exit 1
fi

if [[ ! -d "$MORK_DIR/.git" ]]; then
  echo "MORK repo not found at $MORK_DIR. Cloning from $UPSTREAM_URL ..."
  mkdir -p "$(dirname "$MORK_DIR")"
  git clone "$UPSTREAM_URL" "$MORK_DIR"
fi

LIB_RS="$MORK_DIR/kernel/src/lib.rs"
SINKS_RS="$MORK_DIR/kernel/src/sinks.rs"
HELPER_EXT_DST="$MORK_DIR/kernel/src/helper_ext.rs"

for f in "$LIB_RS" "$SINKS_RS"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: expected file missing: $f" >&2
    exit 1
  fi
done

echo "Copying helper extension file ..."
cp "$HELPER_EXT_SRC" "$HELPER_EXT_DST"

# Migrate legacy tuple_ext marker if present
perl -0pi -e 's/mod tuple_ext;/mod helper_ext;/' "$LIB_RS"
perl -0pi -e 's/tuple_ext::register\(&mut scope\);/helper_ext::register\(\&mut scope\);/g' "$SINKS_RS"
perl -0pi -e 's/use crate::tuple_ext;\n?//g' "$SINKS_RS"
perl -0pi -e 's/use crate::\{expr, pure, tuple_ext\};/use crate::{expr, pure, helper_ext};/' "$SINKS_RS"

if ! grep -q '^mod helper_ext;$' "$LIB_RS"; then
  echo "Patching lib.rs (add mod helper_ext;) ..."
  awk '
    { print }
    /mod pure;/{ print "mod helper_ext;" }
  ' "$LIB_RS" > "$LIB_RS.tmp"
  mv "$LIB_RS.tmp" "$LIB_RS"
else
  echo "lib.rs already patched."
fi

if rg -q 'use crate::\{[^}]*helper_ext[^}]*\};|use crate::helper_ext;' "$SINKS_RS"; then
  echo "sinks.rs import already patched."
else
  echo "Patching sinks.rs (import helper_ext) ..."
  if grep -q 'use crate::{expr, pure};' "$SINKS_RS"; then
    perl -0pi -e 's/use crate::\{expr, pure\};/use crate::{expr, pure};\nuse crate::helper_ext;/' "$SINKS_RS"
  else
    perl -0pi -e 's/use crate::space::ACT_PATH;/use crate::space::ACT_PATH;\nuse crate::helper_ext;/' "$SINKS_RS"
  fi
fi

if ! grep -q 'helper_ext::register(&mut scope);' "$SINKS_RS"; then
  echo "Patching sinks.rs (register helper_ext funcs) ..."
  perl -0pi -e 's/pure::register\(&mut scope\);/pure::register\(\&mut scope\);\n        helper_ext::register\(\&mut scope\);/' "$SINKS_RS"
else
  echo "sinks.rs register already patched."
fi

echo "Building MORK ..."
(
  cd "$MORK_DIR/kernel"
  RUSTFLAGS="-C target-cpu=native" cargo build --release
)

echo
echo "Done."
echo "Binary: $MORK_DIR/target/release/mork"
