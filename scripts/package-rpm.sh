#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/build/src"
OUT="out/Default"
BUILD_OUT="$SRC/$OUT"
PKG_NAME=aster
PREFIX="/opt/$PKG_NAME"
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/chromium_version.txt")"
FINAL_RPM="$REPO_ROOT/$PKG_NAME-$VERSION.rpm"

log() {
  printf '\n\033[1;35m[rpm] %s\033[0m\n' "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "$VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "invalid RPM version: $VERSION"

# Ninja is incremental. Always invoke the compiler so missing targets and
# interrupted builds resume instead of being mistaken for a complete build.
"$REPO_ROOT/scripts/compile.sh"

STAGE="$(mktemp -d)"
TOP="$(mktemp -d)"
cleanup() {
  rm -rf -- "$STAGE" "$TOP"
}
trap cleanup EXIT

DEST="$STAGE$PREFIX"
mkdir -p "$DEST"

copy_required() {
  local source="$1"
  local destination="${2:-$1}"
  [ -e "$BUILD_OUT/$source" ] || die "required build output is missing: $source"
  mkdir -p "$DEST/$(dirname "$destination")"
  cp -a "$BUILD_OUT/$source" "$DEST/$destination"
}

copy_prefer_stripped() {
  local source="$1"
  local destination="${2:-$1}"
  if [ -e "$BUILD_OUT/$source.stripped" ]; then
    copy_required "$source.stripped" "$destination"
  else
    copy_required "$source" "$destination"
  fi
}

copy_optional() {
  local source="$1"
  local destination="${2:-$1}"
  if [ -e "$BUILD_OUT/$source" ]; then
    mkdir -p "$DEST/$(dirname "$destination")"
    cp -a "$BUILD_OUT/$source" "$DEST/$destination"
  fi
}

log "Staging browser runtime"
copy_prefer_stripped chrome chrome
copy_prefer_stripped chrome_crashpad_handler chrome_crashpad_handler
copy_prefer_stripped chrome_management_service chrome-management-service
copy_prefer_stripped chrome_sandbox chrome-sandbox

copy_required resources.pak
copy_required icudtl.dat
copy_required locales

if [ -e "$BUILD_OUT/v8_context_snapshot.bin" ]; then
  copy_required v8_context_snapshot.bin
elif [ -e "$BUILD_OUT/snapshot_blob.bin" ]; then
  copy_required snapshot_blob.bin
else
  die "neither V8 snapshot output exists"
fi

if [ -e "$BUILD_OUT/chrome_100_percent.pak" ]; then
  copy_required chrome_100_percent.pak
  copy_required chrome_200_percent.pak
else
  copy_required theme_resources_100_percent.pak
  copy_required ui_resources_100_percent.pak
fi

for file in libEGL.so libGLESv2.so libvk_swiftshader.so libvulkan.so.1 \
            vk_swiftshader_icd.json libqt5_shim.so libqt6_shim.so; do
  if [ -e "$BUILD_OUT/$file.stripped" ]; then
    copy_optional "$file.stripped" "$file"
  else
    copy_optional "$file"
  fi
done

for directory in default_apps WidevineCdm; do
  copy_optional "$directory"
done

EXTENSION_POLICY_SOURCE="$REPO_ROOT/assets/aster/policies/managed/aster-extensions.json"
[ -f "$EXTENSION_POLICY_SOURCE" ] \
  || die "required extension policy is missing: $EXTENSION_POLICY_SOURCE"
mkdir -p "$STAGE/etc/aster/policies/managed"
cp "$EXTENSION_POLICY_SOURCE" \
  "$STAGE/etc/aster/policies/managed/aster-extensions.json"

NATIVE_MESSAGING_HOST_SOURCE="$REPO_ROOT/assets/aster/native-messaging-hosts/com.1password.1password.json"
[ -f "$NATIVE_MESSAGING_HOST_SOURCE" ] \
  || die "required native-messaging host manifest is missing: $NATIVE_MESSAGING_HOST_SOURCE"
mkdir -p "$STAGE/etc/chromium/native-messaging-hosts"
cp "$NATIVE_MESSAGING_HOST_SOURCE" \
  "$STAGE/etc/chromium/native-messaging-hosts/com.1password.1password.json"

chmod 4755 "$DEST/chrome-sandbox"

mkdir -p "$STAGE/usr/bin" \
             "$STAGE/usr/share/applications"

cat > "$STAGE/usr/bin/$PKG_NAME" <<EOF
#!/bin/sh
export CHROME_WRAPPER="\$(readlink -f "\$0")"
export CHROME_DESKTOP="$PKG_NAME.desktop"
exec $PREFIX/chrome --user-data-dir="\${XDG_CONFIG_HOME:-\$HOME/.config}/$PKG_NAME" "\$@"
EOF
chmod 755 "$STAGE/usr/bin/$PKG_NAME"

ICON_ROOT="$REPO_ROOT/assets/aster/icons"
ICON_SIZES=(16 24 32 48 64 128 256 512)
for size in "${ICON_SIZES[@]}"; do
  icon_source="$ICON_ROOT/$size.png"
  [ -f "$icon_source" ] || die "required Aster icon is missing: $icon_source"
  icon_dir="$STAGE/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$icon_dir"
  cp "$icon_source" "$icon_dir/$PKG_NAME.png"
done

DESKTOP_TEMPLATE="$BUILD_OUT/installer/common/desktop.template"
[ -f "$DESKTOP_TEMPLATE" ] \
  || die "required Chromium desktop template is missing: $DESKTOP_TEMPLATE"
sed -e "s|@@MENUNAME|Aster|g" \
    -e "s|@@PACKAGE|$PKG_NAME|g" \
    -e "s|@@usr_bin_symlink_name|$PKG_NAME|g" \
    -e "s|@@uri_scheme||g" \
    -e "s|@@extra_desktop_entries|StartupWMClass=Aster|g" \
    "$DESKTOP_TEMPLATE" > "$STAGE/usr/share/applications/$PKG_NAME.desktop"
if grep -q '@@' "$STAGE/usr/share/applications/$PKG_NAME.desktop"; then
  die "unresolved placeholder in $PKG_NAME.desktop"
fi

mkdir -p "$TOP"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
SPEC="$TOP/SPECS/$PKG_NAME.spec"

cat > "$SPEC" <<EOF
%global _build_id_links none
Name:           $PKG_NAME
Version:        $VERSION
Release:        1
Summary:        Ungoogled Chromium (Noa-flavored)
License:        BSD-3-Clause AND GPL-3.0-or-later
URL:            https://github.com/AsterisMono/Aster
BuildArch:      x86_64
Requires:       ca-certificates
Requires:       liberation-fonts
Requires:       xdg-utils
Requires:       libgtk-3.so.0()(64bit)
Requires:       libnss3.so(NSS_3.39)(64bit)

%description
Aster is an ungoogled Chromium build with a bundled Sidebery vertical
tab panel, bundled uBlock Origin, policy-installed companion extensions,
and patches curated by Noa.

%install
mkdir -p %{buildroot}
cp -a $STAGE/. %{buildroot}/

%files
%defattr(-,root,root,-)
$PREFIX
/usr/bin/$PKG_NAME
/usr/share/applications/$PKG_NAME.desktop
/usr/share/icons/hicolor/*/apps/$PKG_NAME.png
/etc/aster/policies/managed/aster-extensions.json
/etc/chromium/native-messaging-hosts/com.1password.1password.json
EOF

cat >> "$SPEC" <<EOF

%changelog
* $(LC_ALL=C date '+%a %b %d %Y') AsterisMono (noa@requiem.garden) - $VERSION-1
- Automated container build
EOF

log "Building RPM"
rpmbuild --define "_topdir $TOP" -bb "$SPEC"

mapfile -t built_rpms < <(find "$TOP/RPMS" -type f -name '*.rpm' -print)
[ "${#built_rpms[@]}" -eq 1 ] \
  || die "expected exactly one RPM, found ${#built_rpms[@]}"
[ "$(rpm -qp --queryformat '%{NAME}-%{VERSION}' "${built_rpms[0]}")" = "$PKG_NAME-$VERSION" ] \
  || die "RPM metadata does not match $PKG_NAME-$VERSION"
cp -f "${built_rpms[0]}" "$FINAL_RPM"

log "Created $FINAL_RPM"
