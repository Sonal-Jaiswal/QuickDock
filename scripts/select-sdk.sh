# Sourced by build-app.sh and test.sh.
#
# Command Line Tools ship without SwiftUI's macro plugin. Newer SDKs implement
# @State as a macro, so with CLT we pick the newest SDK that doesn't need it.
# Set SDKROOT yourself to override. With full Xcode nothing changes.
if [[ -z "${SDKROOT:-}" ]]; then
  _qd_dev_dir="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$_qd_dev_dir" == *CommandLineTools* ]]; then
    for sdk in $(ls -d "$_qd_dev_dir"/SDKs/MacOSX[0-9]*.sdk 2>/dev/null | sort -V -r); do
      if ! grep -rqs "StateMacro" "$sdk/System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"; then
        export SDKROOT="$sdk"
        break
      fi
    done
  fi
  unset _qd_dev_dir
fi
[[ -n "${SDKROOT:-}" ]] && echo "▸ SDK: $SDKROOT"
true
