#!/bin/bash

# ==============================================================================
# AwesomeWM Autostart Script
# ==============================================================================

# --- Helper Functions ---------------------------------------------------------

# Run a command only if it's not already running.
# Usage: run_once <process_name> <command> [args...]
run_once() {
    local process_name="$1"
    shift
    # -u "$USER" ensures we only check our own processes
    # -x ensures exact match of the process name (prevents the pgrep false-positive trap)
    if ! pgrep -u "$USER" -x "$process_name" >/dev/null; then
        "$@" &
    fi
}

# Kill a process quietly if it's running (prevents duplicates on WM reload)
kill_if_running() {
    if pgrep -u "$USER" -x "$1" >/dev/null; then
        killall -q "$1"
    fi
}

# --- Pre-flight Cleanup -------------------------------------------------------
# Kill existing instances to prevent duplicates when restarting AwesomeWM (Mod+Ctrl+R)
kill_if_running "picom"
kill_if_running "lxsession"
kill_if_running "kdeconnectd"
#kill_if_running "clipcatd"
kill_if_running "greenclip"
kill_if_running "xss-loc"
kill_if_running "betterbird"

# --- X11 Environment & Settings -----------------------------------------------

# Merge Xresources (colors, fonts, Xterm settings, etc.)
# We use -merge so it doesn't wipe out other X11 settings loaded by your display manager
[ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

# Touchpad settings (Uncomment and adjust if needed)
# xinput set-prop "ELAN0718:00 04F3:30FD Touchpad" "Synaptics Tap Action" 0 0 0 0 1 3 2

# Monitor Configuration (Uncomment if you use an external script)
# bash "$HOME/.config/awesome/misc/scripts/mon.sh"

# --- Daemons & Services -------------------------------------------------------

# Compositor
picom -b --config /home/solis/.config/awesome/picom.conf

# Wallpaper (Run in background)
bash "$HOME/.config/awesome/misc/scripts/wall.sh" &

# Lockscreen Handler
run_once "xss-lock" /usr/sbin/xss-lock -- betterlockscreen -l

# Polkit Authentication Agent
run_once "lxsession" /usr/sbin/lxsession

# KDE Connect
run_once "kdeconnectd" /usr/sbin/kdeconnectd

# Clipboard Manager (Greenclip)
run_once "greenclip" /usr/sbin/greenclip daemon

run_once "betterbird" /usr/sbin/betterbird

# Game notifier (Run in background)
#sleep 3 && python "$HOME/.config/awesome/misc/scripts/games.py" &

# Clipboard Manager (Clipcat)
#run_once "clipcatd" /usr/sbin/clipcatd

# ==============================================================================
# Note: We removed the arbitrary 'sleep' commands. Backgrounding with '&'
# and using exact process matching ('pgrep -x') is much more reliable and
# ensures your WM doesn't hang or race-condition on startup.
# ==============================================================================
