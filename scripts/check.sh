#!/usr/bin/env bash
# Compile-check helper: type-checks capnp schemas without a code generator,
# against the CURRENT canonical tree.
cd /home/lufuno/smart/smart-protocol-official/schema || exit 1
fail=0
for f in "$@"; do
  if ! capnp compile -I. --no-standard-import -o- "$f" >/dev/null 2>/tmp/kcapnp_err; then
    echo "FAIL $f"; head -10 /tmp/kcapnp_err; fail=1
  else
    if [ -s /tmp/kcapnp_err ]; then echo "WARN $f"; head -3 /tmp/kcapnp_err; fi
    echo "OK   $f"
  fi
done
exit $fail
