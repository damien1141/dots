# 🌌 AwesomeWM Dotfiles

> A highly customized, feature-rich Linux rice for AwesomeWM.
> *Inspired by [saimoomedits/dotfiles](https://github.com/saimoomedits/dotfiles)*

## 📋 Table of Contents
- [Overview](#overview)
- [Quick Info](#quick-info)
- [Features](#features)
- [Configuration](#configuration)
- [Keybindings](#keybindings)
- [Dependencies](#dependencies)
- [Installation](#installation)
- [Planned Features](#planned-features)
- [File Tree](#file-tree)
- [License & Credits](#license--credits)

---

## 🌟 Overview

A fully customized AwesomeWM setup focusing on productivity, aesthetics, and unique tiling behaviors. 

* **Bling** - Enhanced window management, tags, and animations.
* **Rubato** - Smooth window border theming and layout animations.
* **Custom Widgets** - Battery, system monitoring, music controls, and weather.
* **Dynamic Wallpaper** - Script-based wallpaper rotation.
* **Lock Screen** - Secure screen locking with `fprintd` (fingerprint) support.

---

## 📊 Quick Info

| Component | Name |
|---|---|
| **WM** | AwesomeWM |
| **Terminal** | Kitty |
| **Browser** | LibreWolf |
| **Editor** | VSCodium |
| **Music** | Sonixd |
| **File Manager** | Thunar |
| **Compositor** | Picom |
| **Launcher** | Rofi |

---

## ✨ Features

### 🧩 Layout System (`layout-brr`)
A custom Hyprland-esque tiling layout. Instead of spawning directly underneath the cursor, windows spawn dynamically away from it, providing a fluid and non-intrusive workflow.

### 📈 Monitoring & Widgets
* **System Resources:** Real-time CPU and RAM usage tracking.
* **Battery & Time:** Status widget and clock display.
* **Media Controls:** Integrated music player controls.
* **Network Shortcuts:** Quick-access buttons for `blueberry` (Bluetooth) and `nmtui` (Wi-Fi).
* **Power Management:** `tlp-pd` compatible power profile switcher.
* **Weather:** Integrated weather display in the minimal bar (`bar-min`).
* **Hydration & AI Status Indicator:** A unique pulsing line in `bar-min` that reminds you to drink water every 30 minutes (blue pulse). It also doubles as a local `llamacpp` server status indicator on port `5001` (yellow pulse for generating, fast green double-pulse for completion).

### 🛠️ Tools & Scripts
* **Unified Launcher:** Rofi-based launcher for apps, emojis (trigger: `:`), clipboard history (trigger: `;`), and math calculations (trigger: `=`).
* **Dashboard:** Notification center, Quick notes, `htop` system monitor, and active network connections.
* **Control Center:** Features your profile picture, which doubles as a `caffeinate` toggle to keep the screen awake.
* **Utilities:** Custom screen capture tool, notification daemon with action handling, wallpaper rotation script, and an autorun script for startup services.

---

## ⚙️ Configuration

### Application Preferences
Default applications can be easily modified in `rc.lua`:

```lua
user_likes = {
    term        = "kitty",
    editor      = "vscodium",
    code        = "vscodium",
    web         = "librewolf",
    music       = "sonixd",
    discord     = "discord",
    steam       = "steam",
    files       = "thunar",
}
```

### Tag Layouts
The setup primarily utilizes the custom `layout-brr`, but all layouts are fully modular. Change them to your liking in `config/tags.lua`!

---

## ⌨️ Keybindings

| Keybinding | Action |
|---|---|
| `Mod4 + Shift + W` | Cycle through wallpapers |
| `Mod4 + Shift + F3` | Toggle monitor configuration |
| `Mod4 + F3` | Enable dual monitor mode |
| `Mouse Wheel (Up/Down)` | Navigate through tags/workspaces |

*(Note: Refer to `config/keys.lua` for the complete list of keybindings)*

---

## 📦 Dependencies

### Core System
* **Window Manager:** `awesome` (≥ 4.0)
* **Languages/Package Managers:** `lua` (≥ 5.1), `luarocks`
* **Compositor:** `picom`
* **Launcher:** `rofi`
* **Utilities:** `libqalculate` (calculator), `blueberry` (bluetooth), `sct` (blue light filter), `networkmanager`

### Lua Modules
* **Bling** - Plugin collection (layouts, widgets)
* **Rubato** - Animation system
* **Layout Machi** - Custom nested layouts
*(Note: These are included in the `mods/` directory)*

### Applications
* **Terminal:** Kitty
* **Code Editor:** VSCodium
* **Web Browser:** LibreWolf
* **Music Frontend:** Sonixd
* **File Manager:** Thunar
* **Gaming/Comms:** Steam, Discord

---

## 🚀 Installation

```bash
# 1. Backup your existing AwesomeWM configuration
cd ~/.config
mv awesome awesome.bak 2>/dev/null || true

# 2. Clone this repository
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git awesome
cd awesome

# 3. Install dependencies via your package manager
# (Ensure lua, luarocks, picom, rofi, etc., are installed)

# 4. Set up symlinks (if using a setup script)
./setup.sh  # If available

# Or manually symlink/verify configurations
ln -sf ~/.config/awesome/rc.lua ~/.config/awesome/rc.lua.bak

# 5. Reload AwesomeWM
# Log out and log back in, or use your reload keybind (usually Mod4 + Ctrl + r)
```

### Post-Installation
1. Configure Picom for transparency effects (see `misc/picom/panthom.conf`).
2. Run `awesome-client` or restart the WM to reload the configuration.
3. Customize `rc.lua` and `theme/` to your personal preferences.

---

## 🔮 Planned Features

* 🎯 **Valorant-style Crosshair:** A toggleable crosshair that spawns exactly at the center of the screen (planned bind: `Mod + F`).

---

## 📂 File Tree

```text
awesome/
├── rc.lua                          # Main configuration entry point
├── animations/
│   └── workspaces.lua              # Workspace transition animations
├── config/
│   ├── init.lua                    # Module loader
│   ├── keys.lua                    # Keybindings configuration
│   ├── other.lua                   # Additional keybindings
│   ├── rules.lua                   # Client rules
│   └── tags.lua                    # Tag/layout definitions
├── helpers/
│   ├── init.lua                    # Helper utilities
│   └── widgets/
│       └── create_button.lua       # Button widget factory
├── images/
│   ├── init.lua                    # Image loader
│   └── sus/
│       ├── album-art.png           # Music player placeholder
│       ├── awesome.png             # Logo
│       ├── bell.png                # Notification icon
│       ├── music.png               # Music control icon
│       ├── profile.jpg             # User avatar
│       ├── profile1.jpg
│       ├── profile2.jpg
│       ├── profile3.jpg
│       ├── searcher.png            # Search icon
│       ├── layouts/
│       │   ├── flair.png           # Layout preview icon
│       │   ├── floating.png
│       │   ├── layout-machi.png
│       │   └── tile.png
│       └── walls/
│           ├── dark.png
│           ├── dark1.png
│           ├── dark3.png
│           ├── dark4.png
│           ├── dark5.png
│           └── light.png
├── layout/
│   ├── init.lua                    # Widget factory
│   ├── dashboard/
│   │   ├── init.lua                # Dashboard container
│   │   ├── resourcel/
│   │   │   ├── cpu.lua             # CPU usage widget
│   │   │   ├── hdd.lua             # Disk usage widget
│   │   │   └── ram.lua             # RAM usage widget
│   │   ├── notifs/
│   │   │   ├── build.lua           # Notification builder
│   │   │   ├── container.lua       # Notification container
│   │   │   ├── creator.lua         # Notification creator
│   │   │   └── notifs-empty.lua    # Empty state handler
│   │   ├── sessionctl.lua          # Session controls
│   │   └── resource.lua            # Resource monitor
│   ├── ding/
│   │   ├── init.lua                # DING widget (notification center)
│   │   └── extra/
│   │       ├── battery.lua         # Battery widget
│   │       ├── music.lua           # Music controls
│   │       ├── popup.lua           # Popup container
│   │       ├── short.lua           # Compact widget
│   │       └── slider.lua          # Volume slider
│   ├── launcher/
│   │   └── init.lua                # Application launcher
│   ├── lockscreen/
│   │   ├── init.lua                # Lock screen
│   │   └── lock.lua                # Lock mechanism
│   └── bar/
│       ├── init.lua                # Status bar
│       ├── taglist.lua             # Tag list widget
│       └── bar-min/
│           ├── launcher.lua        # Quick launcher
│           ├── music.lua           # Music widget
│           ├── sliders.lua         # Volume controls
│           ├── statuses.lua        # Status indicators
│           ├── taglist.lua         # Tag display
│           └── time.lua            # Clock widget
├── misc/
│   ├── init.lua                    # Miscellaneous utilities
│   ├── picom/
│   │   └── panthom.conf            # Compositor configuration
│   ├── rofi/
│   │   ├── theme.rasi              # Rofi theme
│   │   └── rofi-bluez              # Bluetooth picker
│   ├── scripts/
│   │   ├── autorun.sh              # Startup services
│   │   ├── mon.sh                  # Monitor script
│   │   ├── monitor.sh              # Display manager
│   │   ├── picker                  # App picker
│   │   ├── read_writer.lua         # Config writer
│   │   ├── ss                      # Screenshot tool
│   │   ├── theme-applier.lua       # Theme switcher
│   │   ├── wall.sh                 # Wallpaper script
│   │   └── notify/
│   │       ├── notify-action.sh    # Notification actions
│   │       └── notify-send.sh      # Notification sender
│   └── Rofi/
│       ├── music-pop.lua           # Music popup
│       ├── rofi-bluez              # Bluetooth control
│       ├── rofi-wifi               # WiFi control
│       └── three-vertical.rasi     # Rofi theme
├── mods/
│   ├── better-resize.lua           # Enhanced resize
│   ├── exit-screen.lua             # Exit screen
│   ├── liblua_pam.so               # PAM module
│   ├── savefloats.lua              # Float preservation
│   ├── window_switcher.lua         # Window switching
│   ├── battery-widget/
│   │   ├── config.ld
│   │   ├── init.lua                # Battery widget
│   │   └── README.md
│   ├── bling/
│   │   ├── bling-dev-1.rockspec    # Package spec
│   │   ├── init.lua                # Main entry
│   │   ├── theme-var-template.lua  # Theme template
│   │   ├── layout/
│   │   │   ├── centered.lua
│   │   │   ├── deck.lua
│   │   │   ├── equalarea.lua
│   │   │   ├── horizontal.lua
│   │   │   ├── init.lua
│   │   │   ├── mstab.lua
│   │   │   └── vertical.lua
│   │   ├── widget/
│   │   │   ├── app_launcher/
│   │   │   │   ├── init.lua
│   │   │   │   └── prompt.lua
│   │   │   ├── tabbar/
│   │   │   │   ├── boxes.lua
│   │   │   │   ├── default.lua
│   │   │   │   ├── modern.lua
│   │   │   │   └── pure.lua
│   │   │   ├── tabbed_misc/
│   │   │   │   ├── custom_tasklist.lua
│   │   │   │   ├── init.lua
│   │   │   │   └── titlebar_indicator.lua
│   │   │   └── window_switcher.lua
│   │   └── helpers/
│   │       ├── client.lua
│   │       ├── color.lua
│   │       ├── filesystem.lua
│   │       ├── icon_theme.lua
│   │       ├── init.lua
│   │       ├── shape.lua
│   │       └── time.lua
│   ├── dock/
│   │   ├── dock.lua                # Dock widget
│   │   ├── dock_animated.lua       # Animated dock
│   │   ├── icon_handler.lua        # Icon management
│   │   └── init.lua
│   ├── layout-machi/
│   │   ├── editor.lua              # Layout editor
│   │   ├── engine.lua              # Layout engine
│   │   ├── init.lua                # Main entry
│   │   ├── layout.lua              # Layout logic
│   │   ├── switcher.lua            # Layout switcher
│   │   └── LICENSE
│   ├── rubato/
│   │   ├── init.lua                # Animation system
│   │   ├── manager.lua             # Animation manager
│   │   ├── subscribable.lua        # Event system
│   │   ├── timed.lua               # Timed animations
│   │   └── easing.lua              # Easing functions
│   └── ding/
│       └── (see layout/ding/)
├── signal/
│   ├── init.lua                    # Signal handlers
│   ├── battery.lua                 # Battery signals
│   ├── bluetooth.lua               # Bluetooth signals
│   ├── bright.lua                  # Brightness signals
│   ├── cpu.lua                     # CPU monitoring
│   └── ram.lua                     # RAM monitoring
├── theme/
│   └── (theme configuration)
└── walls/
    └── (wallpaper directory)
```

---

## 📜 License & Credits

**Copyleft © 2026 Solis**  
**Original Inspiration / Copyleft © 2022 [Saimoomedits](https://github.com/saimoomedits/dotfiles)**

---

*Last updated: June 2026*
