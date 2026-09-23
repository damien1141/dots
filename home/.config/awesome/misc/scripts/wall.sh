#! /bin/bash
find "$HOME/.config/awesome/images/sus/walls" -type f \( -name '*.jpg' -o -name '*.png' \) -print0 | shuf -n 1 -z | xargs -0 feh --bg-fill

#--no-xinerama
