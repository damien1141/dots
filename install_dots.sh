#!/usr/bin/env bash
set -Eeuo pipefail

# Dots installer: repo/AUR packages, fonts/icons/cursor, dotfiles deploy.
# Run as normal user (not root). AUR helper required (aura/yay/paru).

REPO_PKGS=(
  thunar kitty obs-studio btop gimp gram obsidian librewolf bun anki
  aura onlyoffice-bin
)

AUR_PKGS=(
  betterbird-bin opentubex-bin rofi-greenclip
  bibata-cursor-theme-bin qogir-icon-theme betterlockscreen mpdris2-git
  ttf-harmonyos-sans ttf-jetbrains-mono-nerd ttf-ms-fonts onlyoffice-bin
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.config/backup_dots_$(date +%Y%m%d_%H%M%S)"
FONTS_DIR="$SCRIPT_DIR/fonts"
HOME_SRC="$SCRIPT_DIR/home"

info() { printf '==> %s\n' "$1"; }
warn() { printf 'warn: %s\n' "$1" >&2; }
die() { printf 'fatal: %s\n' "$1" >&2; exit 1; }

require_user() {
  [[ "$(id -u)" -ne 0 ]] || die "do not run as root"
}

detect_aur_helper() {
  if command -v aura >/dev/null 2>&1; then
    AUR_HELPER="aura"
  elif command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
  elif command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
  else
    die "no AUR helper found (aura/yay/paru)"
  fi
  info "AUR helper: $AUR_HELPER"
}

install_repo_packages() {
  info "installing repo packages"
  local available=()
  local p
  for p in "${REPO_PKGS[@]}"; do
    if pacman -Si "$p" >/dev/null 2>&1; then
      available+=("$p")
    else
      warn "repo package not found: $p"
    fi
  done

  if ((${#available[@]})); then
    sudo pacman -S --needed --noconfirm "${available[@]}" || warn "some repo packages failed"
  fi
}

install_aur_packages() {
  info "installing aur packages via $AUR_HELPER"
  local p
  for p in "${AUR_PKGS[@]}"; do
    case "$AUR_HELPER" in
      aura)
        if aura -Si "$p" >/dev/null 2>&1; then
          aura -S --needed --noconfirm "$p" || warn "aura install failed: $p"
        else
          warn "aur package not found: $p"
        fi
        ;;
      yay)
        yay -S --needed --noconfirm "$p" || warn "yay install failed: $p"
        ;;
      paru)
        paru -S --needed --noconfirm "$p" || warn "paru install failed: $p"
        ;;
    esac
  done
}

ensure_rust() {
  info "ensuring rust toolchain"

  if command -v cargo >/dev/null 2>&1; then
    return 0
  fi

  info "cargo not found"
  if [[ -t 0 ]]; then
    read -rp "install rustup now? [Y/n]: " input || input="n"
  else
    info "non-interactive terminal: skipping rustup"
    return 1
  fi

  if [[ "$input" =~ ^[Nn]$ ]]; then
    info "skipping rustup install"
    return 1
  fi

  info "installing rustup"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || die "rustup install failed"
  source "$HOME/.cargo/env" || true

  if ! command -v cargo >/dev/null 2>&1; then
    die "cargo still not available after rustup install"
  fi

  return 0
}

build_jaiba() {
  info "building jaiba from source"

  local build_dir="$HOME/.local/share/jaiba-build"
  rm -rf "$build_dir"
  mkdir -p "$build_dir"

  info "cloning jaiba repo"
  git clone https://github.com/damien1141/jaiba.git "$build_dir" || die "jaiba git clone failed"

  info "building jaiba in release mode"
  pushd "$build_dir" >/dev/null || die "cannot enter jaiba build dir"
  cargo build --release --locked || die "jaiba cargo build failed"
  popd >/dev/null || true

  info "installing jaiba binary"
  mkdir -p "$HOME/.local/bin"
  cp "$build_dir/target/release/jaiba" "$HOME/.local/bin/jaiba" || die "jaiba binary install failed"
  chmod +x "$HOME/.local/bin/jaiba" || true

  info "installing jaiba themes and config"
  mkdir -p "$HOME/.config/rama/themes"
  if [[ -d "$build_dir/themes" ]]; then
    cp -a "$build_dir/themes/." "$HOME/.config/rama/themes/" || warn "jaiba themes copy failed"
  fi
  if [[ -f "$build_dir/jaiba_config.toml.sample" ]]; then
    if [[ ! -f "$HOME/.config/rama/jaiba_config.toml" ]]; then
      cp "$build_dir/jaiba_config.toml.sample" "$HOME/.config/rama/jaiba_config.toml" || warn "jaiba config sample copy failed"
    fi
  fi

  rm -rf "$build_dir"
}

configure_fonts() {
  info "configuring fonts"

  # Copy repo-provided fonts into user font tree
  if [[ -d "$FONTS_DIR/emoji" ]]; then
    mkdir -p "$HOME/.local/share/fonts/emoji"
    cp -a "$FONTS_DIR/emoji/." "$HOME/.local/share/fonts/emoji/" || warn "emoji font copy failed"
  fi

  if [[ -d "$FONTS_DIR/material-design-icons" ]]; then
    mkdir -p "$HOME/.local/share/fonts/material-design-icons"
    cp -a "$FONTS_DIR/material-design-icons/." "$HOME/.local/share/fonts/material-design-icons/" || warn "material icons copy failed"
  fi

  # Fontconfig aliases: HarmonyOS Sans for sans, JetBrains Mono Nerd for mono
  mkdir -p "$HOME/.config/fontconfig/conf.d"
  cat > "$HOME/.config/fontconfig/conf.d/50-fonts.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>HarmonyOS Sans</family>
    </prefer>
  </alias>
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrains Mono Nerd Font</family>
    </prefer>
  </alias>
</fontconfig>
EOF

  fc-cache -f || warn "fc-cache failed"
}

configure_icons_cursor() {
  info "configuring icons and cursor"

  mkdir -p "$HOME/.local/share/icons" "$HOME/.local/share/themes"

  # GTK icon/cursor/font/theme settings
  mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"

  cat > "$HOME/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-icon-theme-name = Qogir
gtk-cursor-theme-name = Bibata
gtk-font-name = HarmonyOS Sans 11
gtk-theme-name = Awesthetic-Pro
EOF

  cat > "$HOME/.config/gtk-4.0/settings.ini" <<'EOF'
[Settings]
gtk-icon-theme-name = Qogir
gtk-cursor-theme-name = Bibata
gtk-font-name = HarmonyOS Sans 11
gtk-theme-name = Awesthetic-Pro
EOF

  # QT/KDE icon/cursor
  mkdir -p "$HOME/.config"
  cat > "$HOME/.config/qt5ct/qt5ct.conf" <<'EOF'
[Appearance]
icon_theme=Qogir
cursor_theme=Bibata
style=Awesthetic-Pro
EOF
}

backup_conflict() {
  local src="$1"
  local dst="$2"

  if [[ -e "$dst" ]]; then
    info "backing up existing $dst"
    mkdir -p "$BACKUP_DIR"
    local rel="${dst#$HOME/}"
    local dest_dir="$BACKUP_DIR/$(dirname "$rel")"
    mkdir -p "$dest_dir"
    mv "$dst" "$dest_dir/" || warn "backup failed for $dst"
  fi

  info "moving $src -> $dst"
  mv "$src" "$dst" || die "move failed: $src -> $dst"
}

deploy_dotfiles() {
  info "deploying dotfiles"

  if [[ ! -d "$HOME_SRC" ]]; then
    warn "$HOME_SRC not found, skipping dotfiles"
    return 0
  fi

  local item
  for item in "$HOME_SRC"/.* "$HOME_SRC"/*; do
    [[ -e "$item" ]] || continue
    local base
    base="$(basename "$item")"
    [[ "$base" == "." || "$base" == ".." ]] && continue

    local dst="$HOME/$base"
    backup_conflict "$item" "$dst"
  done
}

main() {
  require_user
  detect_aur_helper
  install_repo_packages
  install_aur_packages

  if ensure_rust; then
    build_jaiba
  else
    info "skipping jaiba build"
  fi

  configure_fonts
  configure_icons_cursor
  deploy_dotfiles

  info "done. you may need to restart your session."
}

main "$@"
