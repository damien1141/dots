# ~/.config/fish/config.fish
# Commands to run in interactive sessions can go here

# Editor is nano because I forget how to exit vim lol XD- and for easy terminal edits
set -Ux EDITOR nano
set -Ux CODE_EDITOR gram
set -Ux TERMINAL kitty

# Package Manager
alias aur='aura'

# Fetch
alias fast='fastfetch'
alias fetch='$HOME/myfetch.sh'

# Quick CUDA check
alias gpu='watch -n 1 nvidia-smi'
alias torch-check='python -c "import torch; print(f\"CUDA: {torch.cuda.is_available()} | Devices: {torch.cuda.device_count()}\")"'

# TUI MON
alias top='btop'

# Temporary retraining helper (remove after a few weeks)
function yay
    echo "🔔 Did you mean 'aur'? (Old habits die hard!)"
    return 1
end

function e
    set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file="$tmp"
    if set -l cwd (command cat -- "$tmp"); and test -n "$cwd"; and test "$cwd" != "$PWD"
        builtin cd -- "$cwd"
    end
    rm -f -- "$tmp"
end

if status is-interactive
    # No greeting
    set fish_greeting

    # Use starship
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != "linux"
        starship init fish | source
        enable_transience
    end

    # Colors
    if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
        cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    end

    # Aliases
    # kitty doesn't clear properly so we need to do this weird printing
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    alias q 'qs -c ii'
    if test "$TERM" != "linux"
        alias ls 'eza --icons'
    end
    if test "$TERM" = "xterm-kitty"
        alias ssh 'kitten ssh'
    end
end
