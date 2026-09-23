#!/bin/bash
# myfetch — my sickass fetch written in bash

# ── colors ────────────────────────────────────────────────
reset=$'\033[0m'
red=$'\033[1;31m'
green=$'\033[1;32m'
yellow=$'\033[1;33m'
blue=$'\033[1;34m'
magenta=$'\033[1;35m'
cyan=$'\033[1;36m'
white=$'\033[1;37m'

label_c=$blue
value_c=$white
gap=4   # spaces between art and info column

# ── info gathering ────────────────────────────────────────
user=${USER:-$(whoami)}
hostn=$(uname -n)

get_os()      { . /etc/os-release; printf '%s %s' "$PRETTY_NAME" "$(uname -m)"; }
get_kernel()  { uname -r; }
get_model()   {
    local m
    m=$(cat /sys/devices/virtual/dmi/id/board_name 2>/dev/null)
    [ -z "$m" ] && m=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)
    printf '%s' "${m:-N/A}"
}
get_uptime()  {
    local s
    s=$(</proc/uptime); s=${s%%.*}
    (( s < 60 )) && { printf '%s secs' "$s"; return; }
    local d=$((s/86400)) h=$((s%86400/3600)) m=$((s%3600/60)) out=""
    (( d )) && out+="$d day$([ "$d" -gt 1 ] && echo s)"
    (( h )) && { [ -n "$out" ] && out+=", "; out+="$h hour$([ "$h" -gt 1 ] && echo s)"; }
    (( m )) && { [ -n "$out" ] && out+=", "; out+="$m min$([ "$m" -gt 1 ] && echo s)"; }
    printf '%s' "$out"
}
get_packages(){ printf '%s (pacman)' "$(( $(pacman -Qq 2>/dev/null | wc -l) ))"; }
get_shell()   {
    local path=${SHELL:-/bin/sh} name ver
    name=${path##*/}
    case $name in
        zsh)  ver=$("$path" --version 2>/dev/null | awk '{print $2}') ;;
        bash) ver=$("$path" --version 2>/dev/null | head -n1 | sed 's/.*version \([0-9.]*\).*/\1/') ;;
        fish) ver=$("$path" --version 2>/dev/null | awk '{print $3}') ;;
    esac
    if [ -n "$ver" ]; then printf '%s %s' "$name" "$ver"; else printf '%s' "$name"; fi
}
get_de()      {
    case ${XDG_CURRENT_DESKTOP:-} in
        *KDE*)  if command -v plasmashell >/dev/null 2>&1; then
                    printf 'Plasma %s' "$(plasmashell --version 2>/dev/null | awk '{print $2}')"
                else printf 'Plasma'; fi ;;
        *GNOME*)    printf 'GNOME' ;;
        *XFCE*)     printf 'Xfce4' ;;
        *Hyprland*) printf 'Hyprland' ;;
        '')         printf 'N/A' ;;
        *)          printf '%s' "$XDG_CURRENT_DESKTOP" ;;
    esac
}
get_wm()      {
    local p
    for p in kwin_x11 kwin_wayland gnome-shell mutter xfwm4 marco openbox i3 sway dwm bspwm awesome xmonad hyprland; do
        if pgrep -x "$p" >/dev/null 2>&1; then
            case $p in
                kwin_x11|kwin_wayland) printf 'Kwin' ;;
                gnome-shell|mutter)    printf 'Mutter' ;;
                *)                     printf '%s' "$p" ;;
            esac
            return
        fi
    done
    printf 'N/A'
}
get_ram()     {
    awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} /MemFree/{f=$2}
         END { if (a=="") a=f; printf "%dMiB / %dMiB", (t-a)/1024, t/1024 }' /proc/meminfo
}
get_vram()    {
    command -v nvidia-smi >/dev/null 2>&1 || { printf 'N/A'; return; }
    nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null \
        | head -n1 | awk -F', ' '{printf "%dMiB / %dMiB", $1, $2}'
}

# ── ascii art ─────────────────────────────────────────────
art=(
'                  ▄'
'                 ▄█▄'
'                ▄███▄'
'               ▄█████▄'
'              ▄███████▄'
'             ▄ ▀▀██████▄'
'            ▄██▄▄ ▀█████▄'
'           ▄█████████████▄'
'          ▄███████████████▄'
'         ▄█████████████████▄'
'        ▄███████████████████▄'
'       ▄█████████▀▀▀▀████████'
'      ▄████████▀      ▀███████▄'
'     ▄█████████        ████▀▀██▄'
'    ▄██████████        █████▄▄▄'
'   ▄██████████▀        ▀█████████▄'
'  ▄██████▀▀▀              ▀▀██████'
' ▄███▀▀                       ▀▀███▄'
'▄▀▀                               ▀▀▄'
''
)

# ── build right column ────────────────────────────────────
info_line() { printf '%s%s: %s%s%s' "$label_c" "$1" "$value_c" "$2" "$reset"; }

printf -v border '─%.0s' {1..35}
box_w=$(( ${#border} + 2 ))

title_plain="USER: $user@$hostn"
title="$(printf '%sUSER: %s%s@%s%s' "$label_c" "$value_c" "$user" "$hostn" "$reset")"
title_pad=$(( (box_w - ${#title_plain}) / 2 ))

right=(
    ""
    ""
    "$(printf '%*s%s' "$title_pad" '' "$title")"
    "┌${border}┐"
    "$(info_line "   OS"       "$(get_os)")"
    "$(info_line "   Host"     "$(get_model)")"
    "$(info_line "   Kernel"   "$(get_kernel)")"
    "$(info_line "   Uptime"   "$(get_uptime)")"
    "$(info_line "   Packages" "$(get_packages)")"
    "$(info_line "   Shell"    "$(get_shell)")"
    "$(info_line "   DE"       "$(get_de)")"
    "$(info_line "   WM"       "$(get_wm)")"
    "$(info_line "   RAM"      "$(get_ram)")"
    "$(info_line "   VRAM"     "$(get_vram)")"
    "└${border}┘"
    ""
    "${reset}⬤ ${white}⬤ ${reset}⬤ ${cyan}⬤ ${blue}⬤ ${cyan}⬤ ${blue}⬤ ${cyan}⬤ ${blue}⬤ ${cyan}⬤ ${blue}⬤ ${cyan}⬤ ${blue}⬤ ${cyan}⬤ ${blue}⬤ ${cyan}⬤ ${reset}⬤ ${white}⬤ ${reset}⬤"
)

# ── print side by side ────────────────────────────────────
w=0
for l in "${art[@]}"; do (( ${#l} > w )) && w=${#l}; done

lines=${#art[@]}
(( ${#right[@]} > lines )) && lines=${#right[@]}

for (( i=0; i<lines; i++ )); do
    a=${art[i]:-}
    pad=$(( w - ${#a} + gap ))
    printf '%s%s%s%*s%s\n' "$white" "$a" "$reset" "$pad" '' "${right[i]:-}"
done
