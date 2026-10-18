#!/usr/bin/env bash
# Compile and execute the actual core patch under each installed awk implementation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_TMP="$(mktemp -d)"
trap 'rm -rf "$TASK_TMP"' EXIT
mkdir -p "$TASK_TMP/bin"
cat > "$TASK_TMP/bin/awk" <<'WRAPPER'
#!/usr/bin/env bash
exec "$IPQA_TEST_AWK_BINARY" "$@"
WRAPPER
chmod +x "$TASK_TMP/bin/awk"
tested=0
for implementation in awk mawk gawk; do
    real_awk="$(command -v "$implementation" || true)"
    [[ -n "$real_awk" ]] || continue
    for patch_source in ipqa.sh install.sh; do
        if ! (
            export IPQA_TEST_AWK_BINARY="$real_awk"
            export PATH="$TASK_TMP/bin:$PATH"
            eval "$(sed -n '/^patch_ip_script()/,/^}/p' "$REPO_ROOT/$patch_source")"
            candidate="$TASK_TMP/$implementation-$patch_source"
            cat "$SCRIPT_DIR/fixtures/dbip-core.sh" "$SCRIPT_DIR/fixtures/lite-core.sh" > "$candidate"
            patch_ip_script "$candidate" || exit 1
            cp "$candidate" "$candidate.once"
            patch_ip_script "$candidate" || exit 1
            cmp -s "$candidate" "$candidate.once" && bash -n "$candidate"
        ); then
            echo "AWK FAIL: $implementation/$patch_source core patch" >&2
            exit 1
        fi
        echo "AWK PASS: $implementation/$patch_source compiles, patches and stays idempotent"
        tested=$((tested + 1))
    done
done
[[ $tested -gt 0 ]]
