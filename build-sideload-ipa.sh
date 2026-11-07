#!/usr/bin/env bash
# Build an *unsigned* tvOS IPA for personal sideload tools (atvLoadly, etc.).
# Xcode does not sign — the sideload tool signs with your burner Apple ID.
#
# This is NOT a "decrypted" App Store IPA. It is a Release build from source
# with Mach-O signatures removed, packaged as Payload/*.app → .ipa.
#
# Usage:
#   ./build-sideload-ipa.sh
#
# Before running (once):
#   cp RivuletCore/Config/Secrets.swift.template RivuletCore/Config/Secrets.swift
#
# Env overrides (optional):
#   CONFIGURATION=Release
#   OUT_DIR=build/sideload

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIGURATION="${CONFIGURATION:-Release}"
OUT_DIR="${OUT_DIR:-build/sideload}"
PROJECT="Rivulet.xcodeproj"
SCHEME="Rivulet"
DERIVED="$OUT_DIR/DerivedData"
STAGE="$OUT_DIR/stage"
EXPORT_PATH="$OUT_DIR/ipa"
IPA_NAME="Rivulet-unsigned.ipa"

die() { echo "error: $*" >&2; exit 1; }

command -v xcodebuild >/dev/null || die "xcodebuild not found — install full Xcode"
[[ -d /Applications/Xcode.app ]] || die "Xcode.app not found"

if [[ ! -f RivuletCore/Config/Secrets.swift ]]; then
  die "Missing RivuletCore/Config/Secrets.swift
  Run: cp RivuletCore/Config/Secrets.swift.template RivuletCore/Config/Secrets.swift"
fi

mkdir -p "$OUT_DIR" "$EXPORT_PATH"
rm -rf "$DERIVED" "$STAGE"
mkdir -p "$STAGE/Payload"

echo "==> Building unsigned $CONFIGURATION (tvOS)…"
# Coverage/profile instrumentation bloats the main binary (~6MB+ of
# __llvm_cov* / __llvm_prf*) and makes atvLoadly's signer OOM-kill
# (`ERROR: signal: killed`) while writing the main executable signature.
# Do NOT pass STRIP_*/DEPLOYMENT_POSTPROCESSING — Sentry .o files fail that.
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=tvOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=- \
  ONLY_ACTIVE_ARCH=NO \
  ENABLE_CODE_COVERAGE=NO \
  CLANG_ENABLE_CODE_COVERAGE=NO \
  CLANG_COVERAGE_MAPPING=NO \
  GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO \
  SWIFT_ENABLE_CODE_COVERAGE=NO \
  ENABLE_TESTABILITY=NO \
  SWIFT_ENABLE_TESTABILITY=NO \
  build

APP="$(find "$DERIVED/Build/Products" -maxdepth 3 -name 'Rivulet.app' -type d -print -quit || true)"
[[ -n "$APP" && -d "$APP" ]] || die "Build finished but Rivulet.app was not found under $DERIVED/Build/Products"

echo "==> Preparing app for resign…"
cp -R "$APP" "$STAGE/Payload/Rivulet.app"
APP_COPY="$STAGE/Payload/Rivulet.app"

# Keep Top Shelf (PlugIns) and Asset Pack (Extensions).
# Folder deletes are NOT enough — linker still embeds ad-hoc Mach-O signatures.
echo "    removing embedded Mach-O signatures…"
while IFS= read -r -d '' path; do
  codesign --remove-signature "$path" >/dev/null 2>&1 || true
done < <(find "$APP_COPY" -type f -print0)

find "$APP_COPY" \( -name '_CodeSignature' -o -name 'CodeResources' \) -prune -exec rm -rf {} +
find "$APP_COPY" -name 'embedded.mobileprovision' -delete

if [[ -f "$APP_COPY/Rivulet" ]]; then
  BEFORE=$(stat -f%z "$APP_COPY/Rivulet")
  xcrun strip -rSTx "$APP_COPY/Rivulet" 2>/dev/null || true
  AFTER=$(stat -f%z "$APP_COPY/Rivulet")
  echo "    main binary: $((BEFORE/1024/1024))MB → $((AFTER/1024/1024))MB"

  # Fail loud if coverage/profile data is still linked — that IPA will kill atvLoadly.
  if xcrun size -m "$APP_COPY/Rivulet" 2>/dev/null | grep -qE '__llvm_cov|__llvm_prf'; then
    die "main binary still contains LLVM coverage/profile sections.
  atvLoadly will likely get 'signal: killed' signing it.
  Rebuild after ensuring Xcode scheme Code Coverage is off, or paste size -m output."
  fi
fi

echo "==> Packaging IPA…"
rm -f "$EXPORT_PATH/$IPA_NAME"
(
  cd "$STAGE"
  zip -qr "$ROOT/$EXPORT_PATH/$IPA_NAME" Payload
)

IPA="$EXPORT_PATH/$IPA_NAME"
[[ -f "$IPA" ]] || die "Failed to write $IPA"

if codesign -dv "$APP_COPY/Rivulet" 2>&1 | grep -qi adhoc; then
  echo "warning: main binary still reports an ad-hoc signature" >&2
else
  echo "    main binary: no ad-hoc signature (good)"
fi

echo
echo "Unsigned IPA ready:"
echo "  $ROOT/$IPA"
ls -lh "$IPA"
echo
echo "  (installing in 2 seconds)"
sleep 2
./install-sideload-ipa.sh
echo "  (installed)"
echo "==> Done!"