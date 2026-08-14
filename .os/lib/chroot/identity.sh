#!/usr/bin/env bash
# lib/chroot/identity.sh — Chroot Configuration Module: system identity
# Runs inside arch-chroot. Reads install-state.json via install-state.sh.
set -Eeuo pipefail
_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./chroot-common.sh
source "$_LIB_DIR/chroot-common.sh"
chroot_err_trap "identity"

# shellcheck source=./install-state.sh
STATE="${STATE:-/root/lib-chroot/install-state.json}"
_INSTALL_STATE_SH="$_LIB_DIR/install-state.sh"
[[ -f "$_INSTALL_STATE_SH" ]] || _INSTALL_STATE_SH="$_LIB_DIR/../install-state.sh"
# shellcheck disable=SC1090
source "$_INSTALL_STATE_SH"
install_state_load "$STATE"

# ── Timezone ──────────────────────────────────────────────────────────────────
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
hwclock --systohc
echo "Timezone set: $TIMEZONE"

# ── Locale ────────────────────────────────────────────────────────────────────
# Generate every locale in LOCALES[] (element 0 is the LANG default); KEYMAP
# is the console default (keymap[0]). Both arrays come from install-state.
# The locale.gen charset column is the locale's own CODESET (ADR 0076: the
# encoding leaf), derived like locale_encoding() — the codeset between '.' and
# any '@modifier' — defaulting to UTF-8 when the name carries none. A non-UTF-8
# encoding is honoured instead of silently coerced to UTF-8.
for _loc in "${LOCALES[@]}"; do
    [[ -n "$_loc" ]] || continue
    _enc="$(sed -n 's/[^.]*\.\([^.@]*\).*/\1/p' <<<"$_loc")"
    _enc="${_enc:-UTF-8}"
    if grep -q "^#${_loc} ${_enc}" /etc/locale.gen; then
        sed -i "s/^#${_loc} ${_enc}/${_loc} ${_enc}/" /etc/locale.gen
    elif ! grep -q "^${_loc} ${_enc}" /etc/locale.gen; then
        echo "${_loc} ${_enc}" >> /etc/locale.gen
    fi
done
locale-gen
echo "LANG=${LOCALE}"   > /etc/locale.conf
# vconsole: the console KEYMAP default plus the console FONT (ADR 0076). Both
# come from install-state; CONSOLE_FONT is always present (default8x16).
{
    echo "KEYMAP=${KEYMAP}"
    [[ -n "${CONSOLE_FONT:-}" ]] && echo "FONT=${CONSOLE_FONT}"
} > /etc/vconsole.conf

# ── Desktop keyboard layout (X11) ─────────────────────────────────────────────
# When a desktop is selected, write the shared X11 keyboard config from the
# full keymap[] list (covers Xorg + XWayland; KDE reads it).
# ENVIRONMENT_DESKTOP is the space-separated DE list passed into the chroot.
if [[ -n "${ENVIRONMENT_DESKTOP:-}" ]]; then
    _xkb_layout="$(IFS=,; printf '%s' "${KEYMAPS[*]}")"
    mkdir -p /etc/X11/xorg.conf.d
    cat > /etc/X11/xorg.conf.d/00-keyboard.conf <<EOF
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "${_xkb_layout}"
EndSection
EOF
    echo "X11 keyboard layout set: ${_xkb_layout}"
fi

# ── Hostname & /etc/hosts ─────────────────────────────────────────────────────
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
echo "Identity set: hostname=${HOSTNAME} locale=${LOCALE} tz=${TIMEZONE}"
