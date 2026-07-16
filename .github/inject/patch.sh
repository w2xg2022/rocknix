#!/bin/bash
# Lane C (inject) patch script — runs against the unsquashed SYSTEM root ($1).
# Overlay non-ES config / scattered files onto a prebuilt base image WITHOUT
# recompiling anything. This is the whole point of lane C: edit here, run the
# "Inject config into userspace image" workflow, get a flashable .img.gz in ~5min.
#
# Scope reminder (see memory rocknix-build-lanes):
#   B (L4) already covers everything in the emulationstation/es4all package
#   (ES UI, glue, installtoemmc, batocera-bluetooth, es_settings, locale, themes).
#   Use lane C for files that live OUTSIDE that package — e.g. the rocknix-package
#   system.cfg default, other /usr/config files, or dropping unwanted binaries.
#
# Keep every edit idempotent. By default this script is a no-op template.
set -e
ROOT="$1"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"     # rocknix repo root
DEVICE="${DEVICE:-RK3566}"
CFG="$ROOT/usr/config/system/configs/system.cfg"

# set_kv <file> <key> <value> — idempotent key override
set_kv() {
  local f="$1" k="$2" v="$3"
  [ -f "$f" ] || { echo "::warning::$f missing, skip $k"; return 0; }
  if grep -q "^${k}=" "$f"; then
    sed -i "s#^${k}=.*#${k}=${v}#" "$f"
  else
    echo "${k}=${v}" >> "$f"
  fi
  echo "set $k=$v"
}

# ============================ EDIT BELOW ============================
# 出厂默认(system.cfg 住在 rocknix 套件、L4 覆盖不到,正是 lane C 的典型用途):
#   set_kv "$CFG" system.language zh_CN
#   set_kv "$CFG" system.timezone Asia/Shanghai
#   set_kv "$CFG" global.savestates 0
#
# 覆盖某个散档脚本(非 ES 套件):
#   install -m0755 "$REPO/projects/ROCKNIX/packages/rocknix/sources/scripts/setsettings.sh" \
#     "$ROOT/usr/bin/setsettings.sh"
#
# 删掉不想要的模拟器(零编译,直接从 SYSTEM 拿掉):
#   rm -f "$ROOT"/usr/bin/rpcs3 "$ROOT"/usr/bin/pcsx2 2>/dev/null || true
# ===================================================================

echo "lane C: patch.sh finished (default no-op; edit .github/inject/patch.sh to add overrides)"
