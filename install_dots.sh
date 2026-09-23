#!/usr/bin/env bash
set -Eeuo pipefail

# Dots installer: repo/AUR packages, fonts/icons/cursor, dotfiles deploy.
# Run as normal user (not root). AUR helper required (aura/yay/paru).

REPO_PKGS=(
  aura thunar kitty obs-studio btop gimp gram obsidian
  bun anki feh playerctl onlyoffice-bin betterbird-bin
  qogir-icon-theme
)

AUR_PKGS=(
  opentubex-bin rofi-greenclip librewolf-bin
  bibata-cursor-theme-bin  betterlockscreen mpdris2-git
  ttf-ms-fonts
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWESOME_GIT_PKGBUILD="$SCRIPT_DIR/awesome-git_custom_PKGBUILD"
BACKUP_DIR="$HOME/.dots-backup_$(date +%Y%m%d_%H%M%S)"
FONTS_DIR="$SCRIPT_DIR/fonts"
HOME_SRC="$SCRIPT_DIR/home"

info() { printf '==> %s\n' "$1"; }
warn() { printf 'warn: %s\n' "$1" >&2; }
die() { printf 'fatal: %s\n' "$1" >&2; exit 1; }

require_user() {
  [[ "$(id -u)" -ne 0 ]] || die "do not run as root"
}

ensure_keyrings() {
  info "ensuring pacman keyrings (artix + archlinux)"
  sudo pacman -S --needed --noconfirm artix-keyring archlinux-keyring \
    || die "keyring install failed"
  sudo pacman-key --populate artix archlinux || die "keyring populate failed"
}

ensure_build_deps() {
  info "ensuring build dependencies (base-devel, git)"
  local missing=()
  command -v git >/dev/null 2>&1 || missing+=(git)
  command -v make >/dev/null 2>&1 || missing+=(base-devel)
  command -v gcc >/dev/null 2>&1 || missing+=(base-devel)

  if ((${#missing[@]})); then
    info "installing missing: ${missing[*]}"
    sudo pacman -S --needed --noconfirm "${missing[@]}" || die "failed to install build deps"
  fi
}

bootstrap_aur_helper() {
  info "bootstrapping AUR helper (yay)"

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay" || die "yay git clone failed"
  pushd "$tmpdir/yay" >/dev/null || die "cannot enter yay build dir"
  makepkg -si --noconfirm || die "yay build/install failed"
  popd >/dev/null || true

  # Verify yay is now available
  command -v yay >/dev/null 2>&1 || die "yay not in PATH after install"
  AUR_HELPER="yay"
  info "AUR helper: $AUR_HELPER"
}

detect_aur_helper() {
  if command -v aura >/dev/null 2>&1; then
    AUR_HELPER="aura"
  elif command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
  elif command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
  else
    warn "no AUR helper found, bootstrapping yay"
    bootstrap_aur_helper
    return
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
        aura -Au --noconfirm "$p" || warn "aura install failed: $p"
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

install_awesome_git() {
  info "building awesome-git with Lua 5.4"
  [[ -f "$AWESOME_GIT_PKGBUILD" ]] || die "custom awesome-git PKGBUILD not found"
  command -v makepkg >/dev/null 2>&1 || die "makepkg not found"

  sudo pacman -S --needed --noconfirm lua54 lua54-lgi \
    || die "lua 5.4 dependency install failed"

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  git clone https://aur.archlinux.org/awesome-git.git "$tmpdir/awesome-git" \
    || die "awesome-git AUR clone failed"
  cp "$AWESOME_GIT_PKGBUILD" "$tmpdir/awesome-git/PKGBUILD" \
    || die "failed to install custom awesome-git PKGBUILD"

  pushd "$tmpdir/awesome-git" >/dev/null || die "cannot enter awesome-git build dir"
  makepkg -si --noconfirm || die "awesome-git build/install failed"
  popd >/dev/null || true
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
  local repo_url="https://github.com/damien1141/jaiba.git"

  # If already built and binary exists, skip unless forced
  if [[ -x "$HOME/.local/bin/jaiba" ]] && [[ ! -t 0 ]]; then
    info "jaiba binary already exists, skipping build (non-interactive)"
    return 0
  fi

  if [[ -t 0 ]] && [[ -x "$HOME/.local/bin/jaiba" ]]; then
    read -rp "jaiba already installed, rebuild? [y/N]: " input || input="n"
    if [[ ! "$input" =~ ^[Yy]$ ]]; then
      info "skipping jaiba rebuild"
      return 0
    fi
  fi

  rm -rf "$build_dir"
  mkdir -p "$build_dir"

  info "cloning jaiba repo"
  git clone "$repo_url" "$build_dir" || die "jaiba git clone failed"

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

  # Copy all repo-provided fonts into user font tree
  if [[ -d "$FONTS_DIR" ]]; then
    local font_dir
    for font_dir in "$FONTS_DIR"/*/; do
      [[ -d "$font_dir" ]] || continue
      local name
      name="$(basename "$font_dir")"
      mkdir -p "$HOME/.local/share/fonts/$name"
      cp -a "$font_dir/." "$HOME/.local/share/fonts/$name/" || warn "font copy failed: $name"
    done
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
      <family>JetBrainsMono Nerd Font</family>
    </prefer>
  </alias>
  <alias>
    <family>serif</family>
    <prefer>
      <family>SourceSerifPro</family>
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
  mkdir -p "$HOME/.config/qt6ct"
  cat > "$HOME/.config/qt6ct/qt6ct.conf" <<'EOF'
[Appearance]
icon_theme=Qogir
cursor_theme=Bibata
style=awesthetic
EOF
}

backup_conflict() {
  local src="$1"
  local dst="$2"

  if [[ -e "$dst" || -L "$dst" ]]; then
    info "backing up existing $dst"
    mkdir -p "$BACKUP_DIR"
    local rel="${dst#$HOME/}"
    local dest_dir="$BACKUP_DIR/$(dirname "$rel")"
    mkdir -p "$dest_dir"
    mv "$dst" "$dest_dir/" || die "backup failed for $dst"
  fi

  info "copying $src -> $dst"
  cp -a "$src" "$dst" || die "copy failed: $src -> $dst"
}

deploy_dotfiles() {
  info "deploying dotfiles"

  if [[ ! -d "$HOME_SRC" ]]; then
    warn "$HOME_SRC not found, skipping dotfiles"
    return 0
  fi

  local item
  for item in "$HOME_SRC"/.* "$HOME_SRC"/*; do
    [[ -e "$item" || -L "$item" ]] || continue
    local base
    base="$(basename "$item")"
    [[ "$base" == "." || "$base" == ".." ]] && continue

    local dst="$HOME/$base"
    backup_conflict "$item" "$dst"
  done
}

main() {
  require_user
  ensure_keyrings
  ensure_build_deps
  detect_aur_helper
  install_repo_packages
  install_aur_packages
  install_awesome_git

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
