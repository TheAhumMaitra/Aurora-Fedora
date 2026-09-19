#!/usr/bin/env bash
# Aurora Installation Script for Fedora Linux

#  SPDX-FileCopyrightText: 2026 Ahum Maitra <theahummaitra@gmail.com>
#  SPDX-License-Identifier: GPL-3.0-or-later

#    Copyright (C) 2026 Ahum Maitra

#       This program is free software: you can redistribute it and/or modify
#       it under the terms of the GNU General Public License as published by
#       the Free Software Foundation, either version 3 of the License, or
#       (at your option) any later version.

#       This program is distributed in the hope that it will be useful,
#       but WITHOUT ANY WARRANTY; without even the implied warranty of
#       MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#       GNU General Public License for more details.

#       You should have received a copy of the GNU General Public License
#       along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -Eeuo pipefail

# Colors for output
RESET='\033[0m'
RED='\033[1;38;5;203m'
GREEN='\033[1;38;5;120m'
YELLOW='\033[1;38;5;221m'
BLUE='\033[1;38;5;111m'
MAGENTA='\033[1;38;5;213m'
CYAN='\033[1;38;5;159m'
WHITE='\033[1;97m'
DARK='\033[38;5;244m'
BOLD='\033[1m'
DIM='\033[2m'
NC="$RESET"

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_LOG="$HOME/.local/share/Aurora/install.log"
BACKUP_DIR="$HOME/.config/aurora_backup_$(date +%s)"
INTERACTIVE=true
DRY_RUN=false
CURRENT_STEP=0
INSTALL_MODE="stable"
INSTALL_STATE_FILE="$HOME/.aurora_install_state"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
DETECTED_INSTALL_TYPE="fresh" # fresh, update, reinstall
DISCOVERED_BINS=()
SDDM_THEME_STATUS="not-run"
DEFAULT_THEME_STATUS="not-run"
FISH_SHELL_STATUS="not-run"
MIN_HOME_FREE_MB="${AURORA_MIN_HOME_FREE_MB:-5120}"
SWITCH_SUDO_RS=true
FEDORA_VERSION="unknown"

# COPR repositories used by Aurora on Fedora
COPR_HYPRLAND="lionheartp/Hyprland"
COPR_ZEN_BROWSER="sneexy/zen-browser"
COPR_NERD_FONTS="maveonair/jetbrains-mono-nerd-fonts"
COPR_NERD_FONTS_FALLBACK="maveonair/desktop-tools"
COPR_STARSHIP="atim/starship"
COPR_SWAYOSD="erikreider/swayosd"
COPR_HYPRLOCK_FALLBACK="solopasha/hyprland"

# Display managers other than SDDM that can own the login screen.
# Fedora enables gdm.service by default; the remaining entries are covered so
# that a leftover display manager cannot reclaim display-manager.service after a
# reboot. sddm.service itself is intentionally absent from this list.
COMPETING_DMS=(
  gdm.service
  gdm3.service
  lightdm.service
  lxdm.service
  lxdm-qt.service
  xdm.service
  wdm.service
  slim.service
  nodm.service
  entrance.service
  greetd.service
  ly.service
)

error_handler() {
  local exit_code=$?
  local line_number="$1"

  echo ""
  echo -e "${RED}[ERROR] Exit code: $exit_code${NC}"
  echo -e "${RED}[ERROR] Line: $line_number${NC}"
  printf "${RED}[ERROR] Failed command: %q${NC}\n" "$BASH_COMMAND"
}

trap 'error_handler $LINENO' ERR

# Structured Logging System
log_message() {
  local level="$1"
  shift
  local message="$*"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local log_dir

  log_dir="$(dirname "$INSTALL_LOG")"
  mkdir -p "$log_dir"

  # Log to file with level
  echo "[$timestamp] [$level] $message" >>"$INSTALL_LOG"

  # Display to console based on log level
  case "$level" in
  ERROR)
    echo -e "${RED}${BOLD}✗ ERROR${NC} ${WHITE}$message${NC}" >&2
    ;;
  WARN)
    echo -e "${YELLOW}${BOLD}▲ WARN ${NC} ${WHITE}$message${NC}"
    ;;
  INFO)
    if [ "$LOG_LEVEL" = "INFO" ] || [ "$LOG_LEVEL" = "DEBUG" ]; then
      echo -e "${CYAN}${BOLD}• INFO ${NC} ${DARK}$message${NC}"
    fi
    ;;
  DEBUG)
    if [ "$LOG_LEVEL" = "DEBUG" ]; then
      echo -e "${BLUE}${BOLD}◌ DEBUG${NC} ${DARK}$message${NC}"
    fi
    ;;
  SUCCESS)
    echo -e "${GREEN}${BOLD}✓ OK   ${NC} ${WHITE}$message${NC}"
    ;;
  esac
}

log_error() { log_message "ERROR" "$@"; }
log_warn() { log_message "WARN" "$@"; }
log_info() { log_message "INFO" "$@"; }
log_debug() { log_message "DEBUG" "$@"; }
log_success() { log_message "SUCCESS" "$@"; }

# Helper functions
print_rule() {
  echo -e "${DIM}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_spacer() {
  echo ""
}

render_banner() {
  print_spacer
  echo -e "${MAGENTA}${BOLD}        ▄▄▄     █    ██   ██▀███   ▒█████   ██▀███   ▄▄▄       ${NC}"
  echo -e "${MAGENTA}${BOLD}      ▒████▄   ██  ▓██▒  ▓██ ▒ ██▒▒██▒  ██▒▓██ ▒ ██▒ ▒████▄     ${NC}"
  echo -e "${BLUE}${BOLD}        ▒██  ▀█▄  ▓██  ▒██ ░▓██ ░▄█ ▒▒██░  ██▒▓██ ░▄█  ▒██  ▀█▄   ${NC}"
  echo -e "${CYAN}${BOLD}        ░██▄▄▄▄██ ▓▓█  ░██ ░▒██▀▀█▄  ▒██   ██░▒██▀▀█▄  ░██▄▄▄▄██  ${NC}"
  echo -e "${GREEN}${BOLD}        ▓█   ▓██ ▒▒█████▓ ░██▓ ▒██▒░ ████▓▒░░██▓ ▒██▒ ▓█   ▓██▒ ${NC}"
  echo -e "${WHITE}${BOLD}  Fedora Linux Hyprland setup, tuned for Aurora${NC}"
  echo -e "${DARK}  Minimal shell noise. Clear steps. Safer install flow.${NC}"
  print_rule
}

print_header() {
  print_spacer
  print_rule
  echo -e "${WHITE}${BOLD}  $1${NC}"
  echo -e "${DARK}  Aurora installer interface${NC}"
  print_rule
}

print_success() {
  log_success "$1"
}

print_warning() {
  log_warn "$1"
}

print_error() {
  log_error "$1"
}

clear_screen() {
  command -v clear &>/dev/null && clear || true
}

next_step() {
  ((++CURRENT_STEP))
  echo ""
  echo -e "${MAGENTA}${BOLD}◉ Step ${CURRENT_STEP}${NC} ${WHITE}${BOLD}$1${NC}"
  echo -e "${DIM}${CYAN}  Preparing this stage...${NC}"
  log_info "Step $CURRENT_STEP: $1"
}

log_command() {
  log_debug "$*"
}

cargo_bin_in_path() {
  case ":${PATH:-}:" in
  *":$HOME/.cargo/bin:"*) return 0 ;;
  *) return 1 ;;
  esac
}

local_bin_in_path() {
  case ":${PATH:-}:" in
  *":$HOME/.local/bin:"*) return 0 ;;
  *) return 1 ;;
  esac
}

append_unique() {
  local new_item="$1"
  local existing_item

  for existing_item in "${DISCOVERED_BINS[@]}"; do
    if [ "$existing_item" = "$new_item" ]; then
      return
    fi
  done

  DISCOVERED_BINS+=("$new_item")
}

discover_cargo_binaries() {
  local manifest_dir="$1"
  local manifest="$manifest_dir/Cargo.toml"
  local package_name=""
  local bin_name
  local bin_file
  DISCOVERED_BINS=()

  if [ ! -f "$manifest" ]; then
    return 1
  fi

  if cargo metadata --manifest-path "$manifest" --no-deps --format-version 1 >/dev/null 2>&1; then
    log_debug "Cargo metadata validated for $manifest"
  else
    log_warn "Cargo metadata validation failed for $manifest"
  fi

  package_name="$(awk -F= '
        /^\[package\]/ { in_package=1; next }
        /^\[/ { in_package=0 }
        in_package {
            key=$1
            gsub(/[[:space:]]/, "", key)
            if (key == "name") {
                value=$2
                gsub(/^[[:space:]]*"/, "", value)
                gsub(/".*$/, "", value)
                print value
                exit
            }
        }
    ' "$manifest")"

  if [ -n "$package_name" ] && [ -f "$manifest_dir/src/main.rs" ]; then
    append_unique "$package_name"
  fi

  while IFS= read -r bin_name; do
    [ -n "$bin_name" ] && append_unique "$bin_name"
  done < <(awk -F= '
        /^\[\[bin\]\]/ { in_bin=1; next }
        /^\[/ { in_bin=0 }
        in_bin {
            key=$1
            gsub(/[[:space:]]/, "", key)
            if (key == "name") {
                value=$2
                gsub(/^[[:space:]]*"/, "", value)
                gsub(/".*$/, "", value)
                print value
            }
        }
    ' "$manifest")

  if [ -d "$manifest_dir/src/bin" ]; then
    while IFS= read -r bin_file; do
      append_unique "$(basename "$bin_file" .rs)"
    done < <(find "$manifest_dir/src/bin" -maxdepth 1 -type f -name '*.rs' | sort)
  fi

  [ ${#DISCOVERED_BINS[@]} -gt 0 ]
}

initialize_logging() {
  # Stream all output to both console and log file.
  exec > >(tee -a "$INSTALL_LOG")
  exec 2>&1
}

# Package Detection Functions (Fedora / RPM)
is_package_installed() {
  local package="$1"

  if ! command -v rpm &>/dev/null; then
    return 1
  fi

  rpm -q "$package" &>/dev/null
}

# Check whether a COPR repository is already enabled on this system
copr_repo_enabled() {
  local repo="$1"
  local owner="${repo%%/*}"
  local project="${repo##*/}"
  local repo_file="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:${owner}:${project}.repo"

  [ -f "$repo_file" ] && return 0

  if command -v dnf &>/dev/null && dnf copr list 2>/dev/null | grep -Fxq "$repo"; then
    return 0
  fi

  return 1
}

# Enable a COPR repository, with an optional fallback repository name.
#
# Some COPR project names differ from what is commonly shared in guides
# (for example jetbrains-mono-nerd-fonts lives in maveonair/desktop-tools),
# so a fallback is attempted before giving up.
enable_copr() {
  local repo="$1"
  local fallback="${2:-}"
  local candidate

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would enable COPR repository: $repo"
    return 0
  fi

  for candidate in "$repo" ${fallback:+"$fallback"}; do
    if copr_repo_enabled "$candidate"; then
      print_success "COPR repository '$candidate' is already enabled"
      log_info "COPR already enabled: $candidate"
      return 0
    fi

    log_info "Enabling COPR repository: $candidate"
    if sudo dnf copr enable -y "$candidate"; then
      print_success "Enabled COPR repository '$candidate'"
      log_info "COPR enabled: $candidate"
      return 0
    fi

    print_warning "Could not enable COPR repository: $candidate"
    log_warn "COPR enable failed: $candidate"
  done

  if [ -n "$fallback" ]; then
    print_error "Could not enable '$repo' or fallback '$fallback'"
  else
    print_error "Could not enable '$repo'"
  fi

  return 1
}

enable_copr_repositories() {
  next_step "Enabling Fedora COPR repositories"

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would enable Aurora COPR repositories"
    for repo in \
      "$COPR_HYPRLAND" \
      "$COPR_ZEN_BROWSER" \
      "$COPR_NERD_FONTS" \
      "$COPR_STARSHIP" \
      "$COPR_SWAYOSD"; do
      echo "  - sudo dnf copr enable $repo"
    done
    return 0
  fi

  if ! command -v dnf &>/dev/null; then
    print_error "dnf is required to enable COPR repositories"
    return 1
  fi

  # Hyprland, hypridle, hyprshutdown, hyprlock helpers, aquamarine, awww, hyprshot, ...
  enable_copr "$COPR_HYPRLAND" || true
  # Zen Browser
  enable_copr "$COPR_ZEN_BROWSER" || true
  # Nerd Fonts (the nerd fonts live in maveonair/desktop-tools)
  enable_copr "$COPR_NERD_FONTS" "$COPR_NERD_FONTS_FALLBACK" || true
  # Starship prompt
  enable_copr "$COPR_STARSHIP" || true
  # swayosd (volume/brightness OSD used by Aurora keybinds)
  enable_copr "$COPR_SWAYOSD" || true

  print_success "COPR repository setup finished"
}

# Hyprland Runtime Detection for Fedora
detect_hyprland_runtime() {
  # The Hyprland binary is usually capitalised ("Hyprland") on Fedora builds.
  if command -v Hyprland &>/dev/null; then
    log_info "Hyprland command found at: $(command -v Hyprland)"
    return 0
  fi

  if command -v hyprland &>/dev/null; then
    log_info "Hyprland command found at: $(command -v hyprland)"
    return 0
  fi

  # Check if running
  if pgrep -x "Hyprland" >/dev/null 2>&1 || pgrep -x "hyprland" >/dev/null 2>&1; then
    if command -v hyprctl &>/dev/null; then
      local version=$(hyprctl version 2>/dev/null | head -1 | grep -oE 'v[0-9.]+' || echo 'unknown')
      log_info "Hyprland is currently running (version: $version)"
    else
      log_info "Hyprland is currently running"
    fi
    return 0
  fi

  # Check if installed via RPM (stable or git package)
  if is_package_installed hyprland || is_package_installed hyprland-git; then
    local installed_version
    if is_package_installed hyprland; then
      installed_version="$(rpm -q --qf '%{VERSION}' hyprland 2>/dev/null || echo 'unknown')"
      log_debug "Hyprland installed (repo version: $installed_version) but not running"
    else
      installed_version="$(rpm -q --qf '%{VERSION}' hyprland-git 2>/dev/null || echo 'unknown')"
      log_debug "Hyprland installed (git version: $installed_version) but not running"
    fi
    return 0
  fi

  return 1
}

# Installation State Detection
detect_installation_type() {
  local aurora_installed=false
  local aurora_version_file="$HOME/.aurora_install_state"

  # Check if Aurora binaries exist
  if [ -f "$HOME/.cargo/bin/keybinds_help" ]; then
    aurora_installed=true
  fi

  if [ "$aurora_installed" = true ]; then
    if [ -f "$aurora_version_file" ]; then
      DETECTED_INSTALL_TYPE="update"
      log_info "Detected existing Aurora installation - running in UPDATE mode"
    else
      DETECTED_INSTALL_TYPE="reinstall"
      log_warn "Detected Aurora binaries but no state file - running in REINSTALL mode"
    fi
  else
    DETECTED_INSTALL_TYPE="fresh"
    log_info "No existing Aurora installation detected - running in FRESH INSTALL mode"
  fi
}

self_update_from_github() {
  if [ "${AURORA_SELF_UPDATE_DONE:-false}" = true ]; then
    log_debug "Skipping Aurora self-update because it already ran in this process tree"
    return 0
  fi

  next_step "Updating Aurora installer"

  if [ ! -d "$SCRIPT_DIR/.git" ]; then
    print_warning "Aurora installer is not running from a git checkout; skipping self-update"
    return 0
  fi

  if ! command -v git &>/dev/null; then
    print_warning "git is not available; skipping Aurora self-update"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would pull the latest Aurora changes in $SCRIPT_DIR"
    return 0
  fi

  local old_head
  local new_head

  old_head="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || true)"

  log_info "Pulling latest Aurora changes in $SCRIPT_DIR"
  if ! git -C "$SCRIPT_DIR" pull --ff-only; then
    print_error "Failed to pull latest Aurora changes from GitHub"
    echo "  Resolve any git errors above, then rerun the installer."
    exit 1
  fi

  new_head="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || true)"

  if [ -n "$old_head" ] && [ -n "$new_head" ] && [ "$old_head" != "$new_head" ]; then
    print_success "Aurora checkout updated; restarting installer with the latest script"
    export AURORA_SELF_UPDATE_DONE=true
    exec "$SCRIPT_DIR/install-fedora.sh" "$@"
  fi

  print_success "Aurora checkout is already up to date"
}

# Check if running on Fedora Linux
check_fedora() {
  print_header "Checking system compatibility"

  if ! command -v dnf &>/dev/null || ! command -v rpm &>/dev/null; then
    print_error "This script is designed for Fedora Linux only (dnf/rpm not found)"
    exit 1
  fi

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}${ID_LIKE:-}" in
    *fedora* | *rhel* | *centos*)
      FEDORA_VERSION="${VERSION_ID:-unknown}"
      print_success "Fedora Linux detected (version: ${VERSION_ID:-unknown})"
      ;;
    *)
      print_error "Unsupported distribution: ${PRETTY_NAME:-unknown}"
      echo "  This installer targets Fedora Linux (Workstation)."
      exit 1
      ;;
    esac
  else
    print_error "Could not read /etc/os-release to verify the distribution"
    exit 1
  fi
}

# Check if running as root
check_root() {
  if [ "$EUID" -eq 0 ]; then
    print_error "Please do not run this script as root"
    exit 1
  fi
  print_success "Running as non-root user"
}

check_home_disk_space() {
  next_step "Checking available disk space"

  local disk_target="/home"
  local available_mb

  if [ ! -d "$disk_target" ]; then
    disk_target="$HOME"
  fi

  available_mb="$(df -Pm "$disk_target" 2>/dev/null | awk 'NR==2 {print $4}')"

  if [[ ! "$available_mb" =~ ^[0-9]+$ ]]; then
    print_error "Could not determine free disk space for $disk_target"
    exit 1
  fi

  log_info "Available space on $disk_target: ${available_mb}MB"

  if [ "$available_mb" -lt "$MIN_HOME_FREE_MB" ]; then
    print_error "Low disk space detected"
    echo "  Free up disk space and rerun the installer."
    exit 1
  fi

  print_success "Sufficient disk space available on $disk_target (${available_mb}MB free)"
}

# Installation Mode Selector
select_installation_mode() {
  if [ "$DRY_RUN" = true ] || [ "$INTERACTIVE" = false ]; then
    log_info "Using default mode: $INSTALL_MODE"
    return
  fi

  next_step "Selecting installation mode"

  echo ""
  echo -e "${MAGENTA}${BOLD}Choose installation mode${NC}"
  print_rule
  echo ""
  echo -e "  ${YELLOW}1)${NC} ${WHITE}${BOLD}Stable${NC} ${GREEN}(recommended)${NC}"
  echo -e "     ${DARK}Uses release builds from the Hyprland COPR${NC}"
  echo -e "     ${DARK}Maximum stability${NC}"
  echo ""
  echo -e "  ${YELLOW}2)${NC} ${WHITE}${BOLD}Git${NC} ${MAGENTA}(bleeding edge)${NC}"
  echo -e "     ${DARK}Uses -git versions (hyprland-git, waybar-git, etc.)${NC}"
  echo -e "     ${DARK}All packages come from the Hyprland COPR${NC}"
  echo -e "     ${DARK}Latest features but may be unstable${NC}"
  echo ""

  read -p "Enter choice [1-2] (default: 1): " -n 1 -r choice || true
  echo

  case "${choice:-}" in
  2)
    INSTALL_MODE="git"
    log_info "Installation mode set to: GIT (bleeding edge)"
    ;;
  *)
    INSTALL_MODE="stable"
    log_info "Installation mode set to: STABLE (default)"
    ;;
  esac
}

# Check dependencies
check_dependencies() {
  next_step "Checking system dependencies"

  local missing_deps=()

  # Check for cargo (via rustup or rust toolchain)
  if ! command -v cargo &>/dev/null; then
    missing_deps+=("cargo (Rust package manager)")
  fi

  # Check for rustc
  if ! command -v rustc &>/dev/null; then
    missing_deps+=("rustc (Rust compiler)")
  fi

  # Check for git
  if ! command -v git &>/dev/null; then
    missing_deps+=("git")
  fi

  # Check for make
  if ! command -v make &>/dev/null; then
    missing_deps+=("make")
  fi

  # Check for C compiler (gcc or clang)
  if ! command -v gcc &>/dev/null && ! command -v clang &>/dev/null && ! command -v cc &>/dev/null; then
    missing_deps+=("gcc or clang (C compiler)")
  fi

  # Check for C++ compiler (g++ or clang++)
  if ! command -v g++ &>/dev/null && ! command -v clang++ &>/dev/null && ! command -v c++ &>/dev/null; then
    missing_deps+=("gcc-c++ or clang (C++ compiler)")
  fi

  # Check for cmake (needed by many C/C++/Rust -sys builds)
  if ! command -v cmake &>/dev/null; then
    missing_deps+=("cmake")
  fi

  if [ ${#missing_deps[@]} -gt 0 ]; then
    print_error "Missing required dependencies:"
    printf '%s\n' "${missing_deps[@]}" | sed 's/^/  - /'
    echo ""
    print_warning "Install full toolchain with: sudo dnf install -y git rustup gcc gcc-c++ make cmake ninja-build clang llvm lldb lld compiler-rt libomp-devel gdb pkgconf-pkg-config"
    echo "  Then initialize Rust (if cargo/rustc still missing): rustup-init -y --default-toolchain stable --profile default && source ~/.cargo/env"
    echo ""
    exit 1
  fi

  print_success "All required dependencies found"
}

# Validate Hyprland setup
validate_hyprland() {
  if [ "$DRY_RUN" = true ]; then
    next_step "Validating Hyprland setup (DRY RUN)"
    print_success "Hyprland validation skipped in dry-run mode"
    return
  fi

  if [ "$INTERACTIVE" = false ]; then
    next_step "Validating Hyprland setup"
    print_success "Hyprland validation skipped in non-interactive mode"
    return
  fi

  next_step "Validating Hyprland setup"

  # Check runtime Hyprland status
  if detect_hyprland_runtime; then
    print_success "Hyprland detected on system"
    log_success "Hyprland is installed and functional"
  else
    echo ""
    echo -e "${YELLOW}This script configures Aurora for Hyprland (Wayland compositor).${NC}"
    echo ""
    read -p "Are you using or planning to use Hyprland? (y/n) " -n 1 -r || true
    echo

    if [[ ! ${REPLY:-} =~ ^[Yy]$ ]]; then
      print_warning "Aurora is designed for Hyprland. Proceeding may result in non-functional configs."
      read -p "Continue anyway? (y/n) " -n 1 -r || true
      echo

      if [[ ! ${REPLY:-} =~ ^[Yy]$ ]]; then
        print_error "Installation cancelled"
        exit 0
      fi
    fi
  fi

  print_success "Hyprland validation passed"
}

# Install required packages from Fedora repositories and the enabled COPRs
install_dnf_packages() {
  next_step "Installing Aurora dependencies"

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would install packages (none actually installed)"
    return
  fi

  if [ "$INTERACTIVE" = false ]; then
    print_warning "Running in non-interactive mode - skipping package installation"
    print_warning "Install packages manually with: sudo dnf install <package>"
    return
  fi

  local hyprland_pkg="hyprland"
  local waybar_pkg="waybar"
  if [ "$INSTALL_MODE" = "git" ]; then
    hyprland_pkg="hyprland-git"
    waybar_pkg="waybar-git"
  fi

  local -A dnf_package_groups=(
    [core]="
            $hyprland_pkg
            xdg-desktop-portal-hyprland
            xdg-desktop-portal-gtk
            aquamarine
            hyprlang
            hyprutils
            hyprgraphics
            hyprcursor
            hyprland-protocols
            hypridle
            hyprlock
            hyprshutdown
            hyprpicker
            hyprshot
            hyprsunset
            awww
            swayosd
            cliphist
            NetworkManager
            NetworkManager-wifi
            pipewire
            pipewire-pulseaudio
            wireplumber
        "
    [daemons]="
            SwayNotificationCenter
            polkit-gnome
            hyprpolkitagent
        "
    [ui]="
            $waybar_pkg
            rofi
            wlogout
            nwg-dock-hyprland
            gtk3
            gtk4
            qt6-qtsvg
            qt6-qtvirtualkeyboard
            qt6-qtmultimedia
            qt6ct
        "
    [utils]="
            kitty
            nemo
            wl-clipboard
            grim
            slurp
            brightnessctl
            libnotify
            bluez
            bluez-tools
            util-linux-user
            curl
            xsel
            dejavu-sans-fonts
            google-noto-sans-fonts
            google-noto-color-emoji-fonts
            papirus-icon-theme
            yaru-theme
            yaru-icon-theme
            jetbrains-mono-nerd-fonts
            starship
            neovim
            sddm
            btop
            fish
            zen-browser
            uv
            sudo-rs
            xorg-x11-server-Xwayland
            pipewire-utils
            pipewire-alsa
            pipewire-jack-audio-connection-kit
        "
    [build]="
            git
            rustup
            rust
            cargo
            rust-analyzer
            clippy
            rustfmt
            gcc
            gcc-c++
            gcc-gfortran
            glibc-devel
            kernel-headers
            binutils
            binutils-devel
            make
            cmake
            cmake-data
            ninja-build
            meson
            pkgconf-pkg-config
            autoconf
            automake
            libtool
            m4
            bison
            flex
            texinfo
            patch
            diffutils
            file
            findutils
            gdb
            lldb
            strace
            clang
            clang-devel
            clang-tools-extra
            clang-resource-filesystem
            llvm
            llvm-devel
            llvm-libs
            llvm-filesystem
            llvm-static
            lld
            compiler-rt
            libomp
            libomp-devel
            libstdc++-devel
            perl
            perl-core
            python3
            python3-devel
            python3-pip
            nodejs
            npm
            lua
            lua-devel
            compat-lua-libs
            luajit
            luajit-devel
            luarocks
            sqlite
            sqlite-devel
            tree-sitter-cli
            inotify-tools
            gettext
            gettext-devel
            ncurses-devel
            ncurses-term
            libedit-devel
            libffi-devel
            libxml2-devel
            libzstd-devel
            zlib-ng-compat-devel
            xz-devel
            bzip2-devel
            brotli-devel
            openssl-devel
            openssl
            pcre2-devel
            libpng-devel
            freetype-devel
            fontconfig-devel
            harfbuzz-devel
            cairo-devel
            cairo-gobject-devel
            pango-devel
            gdk-pixbuf2-devel
            gtk4-devel
            gtk4-layer-shell-devel
            graphene-devel
            vulkan-headers
            vulkan-loader-devel
            wayland-devel
            xorg-x11-proto-devel
            libX11-devel
            libXau-devel
            libxcb-devel
            libXext-devel
            libXrender-devel
            libXft-devel
            pixman-devel
            fribidi-devel
            libdatrie-devel
            libthai-devel
            graphite2-devel
            lcms2-devel
            glycin-devel
            libseccomp-devel
            libicu-devel
            lzo-devel
            libblkid-devel
            libmount-devel
            libselinux-devel
            libsepol-devel
            sysprof-capture-devel
            dbus-devel
            systemd-devel
            glib2-devel
            pipewire-devel
            rofi-devel
            pulseaudio-libs-devel
            glib-networking
        "
  )

  echo ""
  echo -e "${MAGENTA}${BOLD}Aurora requires the following packages${NC}"
  print_rule
  echo ""

  echo -e "  ${CYAN}${BOLD}dnf packages (Fedora repos + enabled COPRs)${NC}"
  for category in core daemons ui utils build; do
    case "$category" in
    core) category_name="Core (Hyprland & COPR)" ;;
    daemons) category_name="Daemons" ;;
    ui) category_name="UI Components" ;;
    utils) category_name="Utilities" ;;
    build) category_name="Build & Toolchain" ;;
    esac
    echo -e "    ${YELLOW}${BOLD}${category_name}:${NC}"
    for pkg in ${dnf_package_groups[$category]}; do
      echo -e "      ${GREEN}•${NC} ${WHITE}$pkg${NC}"
    done
  done

  echo ""
  read -p "Install Aurora packages? (y/n) " -n 1 -r || true
  echo

  if [[ ! ${REPLY:-} =~ ^[Yy]$ ]]; then
    print_warning "Skipping package installation"
    return
  fi

  print_warning "Refreshing Fedora package metadata..."
  if ! sudo dnf makecache --refresh; then
    print_warning "Could not refresh Fedora package metadata; continuing with existing cache"
    log_warn "dnf makecache failed; continuing"
  fi

  print_warning "Installing Aurora dependencies (requires sudo)..."

  local failed_packages=()
  local installed_count=0
  local total_packages=0
  local package

  for category in core daemons ui utils build; do
    for package in ${dnf_package_groups[$category]}; do
      ((++total_packages))

      if is_package_installed "$package"; then
        print_success "Package '$package' already installed"
      else
        if sudo dnf install -y "$package" 2>/dev/null; then
          ((++installed_count))
          log_command "Installed: $package"
        else
          failed_packages+=("$package")
          log_command "Failed to install: $package"
        fi
      fi
    done
  done

  # hyprlock is not shipped by every Hyprland COPR; retry once with a known
  # fallback COPR before reporting it as failed.
  if ! is_package_installed hyprlock; then
    print_warning "hyprlock is not available from the enabled repositories; trying $COPR_HYPRLOCK_FALLBACK"
    if enable_copr "$COPR_HYPRLOCK_FALLBACK" && sudo dnf install -y hyprlock 2>/dev/null; then
      ((++installed_count))

      # Drop hyprlock from the failed list now that it installed successfully
      local -a hyprlock_filtered=()
      local failed_item
      for failed_item in "${failed_packages[@]}"; do
        if [ -n "$failed_item" ] && [ "$failed_item" != "hyprlock" ]; then
          hyprlock_filtered+=("$failed_item")
        fi
      done

      if [ ${#hyprlock_filtered[@]} -gt 0 ]; then
        failed_packages=("${hyprlock_filtered[@]}")
      else
        failed_packages=()
      fi

      print_success "Installed 'hyprlock' from $COPR_HYPRLOCK_FALLBACK"
    else
      print_warning "Could not install hyprlock automatically"
    fi
  fi

  if [ ${#failed_packages[@]} -gt 0 ]; then
    print_warning "Some packages failed (${#failed_packages[@]}/${total_packages}):"
    printf '%s\n' "${failed_packages[@]}" | sed 's/^/  - /'
    echo ""
  fi

  print_success "Package installation completed ($installed_count/$total_packages packages installed/updated)"
}

# Configure NetworkManager as the system network manager
setup_network_manager() {
  next_step "Configuring NetworkManager"

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would disable competing network managers and enable NetworkManager"
    return 0
  fi

  if ! is_package_installed NetworkManager; then
    print_warning "NetworkManager is not installed; skipping network manager configuration"
    log_warn "Skipped NetworkManager setup because the NetworkManager package is unavailable"
    return 0
  fi

  # NOTE: iwd.service is intentionally left alone on Fedora, because
  # NetworkManager can use iwd as its Wi-Fi backend.
  local services=(
    systemd-networkd.service
    systemd-networkd-wait-online.service
    connman.service
    dhcpcd.service
    wicd.service
  )
  local service

  print_warning "Disabling competing network managers..."
  for service in "${services[@]}"; do
    if systemctl list-unit-files "$service" 2>/dev/null | grep -q "^${service}"; then
      echo "  -> Disabling $service"
      sudo systemctl disable --now "$service" 2>/dev/null || true
    fi
  done

  echo ""
  print_warning "Enabling NetworkManager..."
  sudo systemctl enable --now NetworkManager.service

  echo ""
  echo "Network management status:"
  if systemctl is-active --quiet NetworkManager.service; then
    print_success "NetworkManager.service is active"
  else
    print_error "NetworkManager.service is not active after being enabled"
    return 1
  fi

  echo ""
  echo "Active network-related services:"
  systemctl --type=service --state=running |
    grep -Ei 'NetworkManager|iwd|systemd-networkd|connman|dhcpcd|wicd' || true

  print_success "NetworkManager is now the active network manager"
  log_info "NetworkManager enabled and competing network managers disabled"
}

# Return 0 when a display manager is enabled to start at boot.
#
# `systemctl is-enabled` is not used directly because it also exits 0 for
# "static" units, which would make the caller try to disable units that have no
# install section at all. The state string is matched explicitly instead.
display_manager_enabled() {
  local unit="$1"
  local state

  state="$(systemctl is-enabled "$unit" 2>/dev/null || true)"

  case "$state" in
  enabled | enabled-runtime | linked | linked-runtime | alias) return 0 ;;
  *) return 1 ;;
  esac
}

# Give SDDM exclusive ownership of the login screen.
#
# Fedora enables GDM by default and only one display manager may own
# display-manager.service, so every competing display manager is disabled here
# (GDM included) instead of only the first one that is detected.
#
# Plain `systemctl disable` is used without `--now` on purpose: stopping a
# running display manager would terminate the desktop session (and this
# installer) that the user is currently logged into. The switch takes effect on
# the next boot.
ensure_sddm_is_only_display_manager() {
  local dm
  local disabled_any=false
  local remaining_dms=()
  local dm_alias="/etc/systemd/system/display-manager.service"
  local current_alias=""

  for dm in "${COMPETING_DMS[@]}"; do
    if ! display_manager_enabled "$dm"; then
      continue
    fi

    print_warning "$dm is enabled and conflicts with sddm; disabling it"
    log_info "Disabling competing display manager: $dm"

    if sudo systemctl disable "$dm" 2>/dev/null; then
      print_success "Disabled $dm"
      disabled_any=true
    else
      print_warning "Could not disable $dm automatically; disable it with: sudo systemctl disable $dm"
      log_warn "Failed to disable competing display manager: $dm"
    fi
  done

  # Enabling SDDM last (re)creates the display-manager.service alias.
  if ! sudo systemctl enable sddm.service; then
    print_error "Failed to enable sddm.service"
    echo "  Enable it manually with: sudo systemctl enable sddm.service"
    log_error "systemctl enable sddm.service failed"
    return 1
  fi
  print_success "Enabled sddm.service"

  # Belt and braces: make sure the alias really points at SDDM and not at a
  # leftover display manager.
  if [ -L "$dm_alias" ]; then
    current_alias="$(readlink "$dm_alias" 2>/dev/null || true)"
  fi

  if [ "$current_alias" != "/usr/lib/systemd/system/sddm.service" ]; then
    sudo ln -sf /usr/lib/systemd/system/sddm.service "$dm_alias"
    sudo systemctl daemon-reload
    log_info "Pointed $dm_alias at sddm.service"
  fi

  # Verify the end state so a conflicting display manager cannot silently win.
  for dm in "${COMPETING_DMS[@]}"; do
    if display_manager_enabled "$dm"; then
      remaining_dms+=("$dm")
    fi
  done

  if [ ${#remaining_dms[@]} -gt 0 ]; then
    print_warning "These display managers are still enabled: ${remaining_dms[*]}"
    echo "  Disable them with: sudo systemctl disable ${remaining_dms[*]}"
    log_warn "Display managers still enabled after setup: ${remaining_dms[*]}"
    return 1
  fi

  if [ "$disabled_any" = true ]; then
    log_info "Disabled one or more competing display managers"
  else
    log_info "No competing display managers were enabled"
  fi

  print_success "SDDM is the only display manager enabled at boot"
  return 0
}

install_sddm_theme() {
  next_step "Installing SDDM astronaut theme"

  local theme_repo="https://github.com/keyitdev/sddm-astronaut-theme.git"
  local theme_dir="/usr/share/sddm/themes/sddm-astronaut-theme"
  local sddm_conf="/etc/sddm.conf.d/theme.conf"
  local virtualkbd_conf="/etc/sddm.conf.d/virtualkbd.conf"
  local theme_ready=false

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would clone $theme_repo into $theme_dir"
    print_warning "[DRY RUN] Would copy theme fonts into /usr/share/fonts and refresh font cache"
    print_warning "[DRY RUN] Would write $sddm_conf and $virtualkbd_conf"
    print_warning "[DRY RUN] Would disable competing display managers (gdm, lightdm, ...) and enable sddm.service"
    return 0
  fi

  if ! is_package_installed sddm; then
    SDDM_THEME_STATUS="skipped"
    print_warning "sddm is not installed according to rpm; skipping theme setup"
    log_warn "Skipped SDDM theme installation because the sddm package is missing"
    return 0
  fi

  print_warning "Installing SDDM astronaut theme (requires sudo)..."

  sudo mkdir -p /usr/share/sddm/themes
  sudo mkdir -p /etc/sddm.conf.d

  # A failed pull or clone must not abort the whole installation, so both are
  # guarded and only the theme status is downgraded.
  if [ -d "$theme_dir/.git" ]; then
    log_info "Updating existing SDDM astronaut theme checkout"
    if sudo git -C "$theme_dir" pull --ff-only; then
      theme_ready=true
    else
      print_warning "Could not update the SDDM theme checkout; keeping the existing copy"
      log_warn "git pull failed for the SDDM theme at $theme_dir"
      theme_ready=true
    fi
  elif [ -d "$theme_dir" ]; then
    log_warn "Theme directory already exists without git metadata: $theme_dir"
    print_warning "Reusing existing SDDM theme directory at $theme_dir"
    theme_ready=true
  else
    log_info "Cloning SDDM astronaut theme from $theme_repo"
    if sudo git clone -b master --depth 1 "$theme_repo" "$theme_dir"; then
      theme_ready=true
    else
      print_warning "Could not clone the SDDM astronaut theme; SDDM will fall back to its default theme"
      log_warn "git clone failed for the SDDM theme: $theme_repo"
    fi
  fi

  if [ "$theme_ready" = true ]; then
    if [ -d "$theme_dir/Fonts" ]; then
      sudo mkdir -p /usr/share/fonts
      if sudo cp -rf "$theme_dir/Fonts/." /usr/share/fonts/; then
        if command -v fc-cache &>/dev/null; then
          sudo fc-cache -f /usr/share/fonts || log_warn "fc-cache failed; the SDDM theme fonts may need a manual refresh"
        fi
        log_info "Installed SDDM theme fonts into /usr/share/fonts"
      else
        print_warning "Could not copy the SDDM theme fonts into /usr/share/fonts"
        log_warn "Copying $theme_dir/Fonts into /usr/share/fonts failed"
      fi
    else
      log_warn "Fonts directory not found in $theme_dir"
    fi

    cat <<'EOF' | sudo tee "$sddm_conf" >/dev/null
[Theme]
Current=sddm-astronaut-theme
EOF

    cat <<'EOF' | sudo tee "$virtualkbd_conf" >/dev/null
[General]
InputMethod=qtvirtualkeyboard
EOF
  fi

  # Fedora ships GDM enabled by default and only one display manager may own the
  # login screen, so SDDM takes over and every competing display manager is
  # disabled (GDM included) in both interactive and non-interactive runs.
  local dm_status_ok=true
  if ! ensure_sddm_is_only_display_manager; then
    dm_status_ok=false
  fi

  if [ "$theme_ready" = true ] && [ "$dm_status_ok" = true ]; then
    SDDM_THEME_STATUS="configured and enabled"
    print_success "SDDM astronaut theme installed and SDDM enabled at boot"
    log_info "Configured SDDM to use sddm-astronaut-theme with qtvirtualkeyboard, disabled competing display managers and enabled sddm.service"
  elif [ "$theme_ready" = true ]; then
    SDDM_THEME_STATUS="theme configured; check competing display managers"
    print_warning "SDDM theme installed, but a competing display manager may still be enabled"
  else
    SDDM_THEME_STATUS="theme missing; SDDM enabled with the default theme"
    print_warning "SDDM was enabled with its default theme because the astronaut theme is unavailable"
  fi
}

# Build Rust scripts
build_rust_scripts() {
  next_step "Building and installing Rust scripts"

  local script_dir="$SCRIPT_DIR/dotfiles/.config/hypr/scripts"
  local old_pwd="$PWD"

  if [ ! -d "$script_dir" ]; then
    log_error "Scripts directory not found at $script_dir"
    print_error "Scripts directory not found at $script_dir"
    rollback_on_failure "Scripts directory missing"
    return 1
  fi

  # Verify Cargo.toml exists (project validation)
  if [ ! -f "$script_dir/Cargo.toml" ]; then
    log_error "Cargo.toml not found in $script_dir - invalid Rust project"
    print_error "Invalid Rust project structure at $script_dir"
    rollback_on_failure "Invalid Rust project"
    return 1
  fi

  cd "$script_dir" || {
    log_error "Failed to change directory to $script_dir"
    rollback_on_failure "Cannot access scripts directory"
    return 1
  }

  if [ "$INTERACTIVE" = false ]; then
    log_info "Running cargo install in non-interactive mode..."
    print_warning "Running cargo install in non-interactive mode..."
  else
    print_warning "Installing aurora scripts (this may take a few minutes)..."
    log_info "Starting cargo install for Aurora scripts"
  fi

  # Run cargo install with error capture
  local cargo_log="$INSTALL_LOG.cargo_err"
  if ! cargo install --path . 2>"$cargo_log"; then
    local cargo_error=$(cat "$cargo_log" 2>/dev/null | tail -20 || echo "Unknown error")
    log_error "Cargo install failed: $cargo_error"
    print_error "Failed to build Rust scripts"
    print_warning "Last 20 lines of error log:"
    echo "$cargo_error" | sed 's/^/  /'
    rm -f "$cargo_log"
    rollback_on_failure "Cargo build failed"
    cd "$old_pwd" || true
    return 1
  fi

  rm -f "$cargo_log"
  log_info "Successfully installed Rust scripts to ~/.cargo/bin"
  print_success "Rust scripts installed successfully to ~/.cargo/bin"

  cd "$old_pwd" || true
  return 0
}

install_mise() {
  next_step "Installing mise"

  if command -v mise &>/dev/null || [ -x "$HOME/.local/bin/mise" ] || [ -x "$HOME/.cargo/bin/mise" ]; then
    print_success "mise is already installed"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would install mise with: curl -fsSL https://mise.run | sh"
    return 0
  fi

  if ! command -v curl &>/dev/null; then
    print_error "curl is required to install mise"
    echo "  Install with: sudo dnf install -y curl"
    return 1
  fi

  log_info "Installing mise via official installer: curl -fsSL https://mise.run | sh"

  if curl -fsSL https://mise.run | sh; then
    log_command "Installed mise via official installer"
    print_success "mise installed successfully (via https://mise.run)"
    return 0
  else
    log_command "Failed to install mise via official installer"
    print_error "mise installation failed (curl -fsSL https://mise.run | sh)"
    return 1
  fi
}

install_rust_packages() {
  next_step "Installing Rust packages"

  # mise is installed via its official installer, not cargo.
  install_mise || return 1

  if ! command -v cargo &>/dev/null; then
    print_error "cargo is required to install Rust packages"
    echo "  Install Rust/Cargo first (sudo dnf install -y rustup), then rerun the installer."
    return 1
  fi

  # crate name -> installed binary name
  local -A rust_package_bins=(
    [termflix]="termflix"
    [nmrs-tui]="nmrs-tui"
    [bluetui]="bluetui"
    [leenfetch]="leenfetch"
    [weathr]="weathr"
    [wiremix]="wiremix"
    [jolt-tui]="jolt"
  )

  local rust_packages=(
    termflix
    nmrs-tui
    bluetui
    leenfetch
    weathr
    wiremix
    jolt-tui
  )

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would install mise with: curl -fsSL https://mise.run | sh"
    print_warning "[DRY RUN] Would install Rust packages with cargo:"
    for package in "${rust_packages[@]}"; do
      echo "  - cargo install $package"
    done
    return 0
  fi

  local failed_packages=()
  local installed_count=0
  local total_packages=0
  local package
  local binary
  local install_ok

  for package in "${rust_packages[@]}"; do
    # Fall back to the crate name when no explicit mapping exists, so a missing
    # key cannot abort the installer via `set -u` (unbound variable).
    binary="${rust_package_bins[$package]:-$package}"
    ((++total_packages))

    if command -v "$binary" &>/dev/null || [ -x "$HOME/.cargo/bin/$binary" ]; then
      print_success "Rust package '$package' already installed ($binary)"
      continue
    fi

    log_info "Installing Rust package via cargo: $package"

    cargo install "$package" && install_ok=true || install_ok=false

    if [ "$install_ok" = true ]; then
      ((++installed_count))
      log_command "Installed Rust package: $package"
    else
      failed_packages+=("$package")
      log_command "Failed to install Rust package: $package"
    fi
  done

  if [ ${#failed_packages[@]} -gt 0 ]; then
    print_error "Some Rust packages failed (${#failed_packages[@]}/$total_packages):"
    printf '%s\n' "${failed_packages[@]}" | sed 's/^/  - /'
    return 1
  fi

  print_success "Rust package installation completed ($installed_count/$total_packages packages installed/updated)"
}

# Build and install hyprwave (music control bar) from source
install_hyprwave() {
  next_step "Building hyprwave from source"

  local repo_url="https://github.com/shantanubaddar/hyprwave.git"
  local repo_dir="$HOME/.local/share/Aurora/src/hyprwave"

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would clone/build/install hyprwave from $repo_url"
    return 0
  fi

  if command -v hyprwave &>/dev/null || [ -x "$HOME/.local/bin/hyprwave" ]; then
    print_success "hyprwave is already installed"
    return 0
  fi

  if ! command -v gcc &>/dev/null || ! command -v make &>/dev/null; then
    print_error "gcc and make are required to build hyprwave"
    echo "  Install with: sudo dnf install -y gcc make gtk4-devel gtk4-layer-shell-devel pulseaudio-libs-devel glib-networking"
    return 1
  fi

  mkdir -p "$(dirname "$repo_dir")"

  if [ -d "$repo_dir/.git" ]; then
    log_info "Updating existing hyprwave checkout at $repo_dir"
    git -C "$repo_dir" pull --ff-only || print_warning "Could not update the hyprwave checkout"
  else
    log_info "Cloning hyprwave from $repo_url"
    if ! git clone --depth 1 "$repo_url" "$repo_dir"; then
      print_error "Failed to clone hyprwave"
      return 1
    fi
  fi

  local old_pwd="$PWD"
  cd "$repo_dir" || {
    print_error "Cannot access $repo_dir"
    return 1
  }

  # The hyprwave Makefile defaults to PREFIX=$HOME/.local, so no sudo is needed.
  if make && make install; then
    print_success "hyprwave installed to ~/.local/bin"
    log_info "hyprwave built and installed from source"
    cd "$old_pwd" || true
    return 0
  fi

  print_error "Failed to build or install hyprwave"
  cd "$old_pwd" || true
  return 1
}

# Install Nordzy cursors (xcursors + hyprcursors) from GitLab
install_nordzy_cursors() {
  next_step "Installing Nordzy cursors"

  local repo_url="https://gitlab.com/gboehm/Nordzy-cursors"
  local repo_dir="$HOME/.local/share/Aurora/src/Nordzy-cursors"
  local icon_dir="$HOME/.local/share/icons/Nordzy-cursors-white"

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would clone $repo_url and run ./install.sh -p"
    return 0
  fi

  if [ -d "$icon_dir" ]; then
    print_success "Nordzy cursors already installed in ~/.local/share/icons"
    return 0
  fi

  if ! command -v git &>/dev/null; then
    print_error "git is required to install Nordzy cursors"
    return 1
  fi

  mkdir -p "$(dirname "$repo_dir")"

  if [ -d "$repo_dir/.git" ]; then
    log_info "Updating existing Nordzy-cursors checkout"
    git -C "$repo_dir" pull --ff-only || print_warning "Could not update the Nordzy-cursors checkout"
  else
    log_info "Cloning Nordzy-cursors from $repo_url"
    if ! git clone --depth 1 "$repo_url" "$repo_dir"; then
      print_error "Failed to clone Nordzy-cursors"
      return 1
    fi
  fi

  if [ ! -f "$repo_dir/install.sh" ]; then
    print_error "Nordzy-cursors install.sh was not found at $repo_dir"
    return 1
  fi

  chmod +x "$repo_dir/install.sh"

  # -p installs the hyprcursor variants next to the X cursors, which Aurora uses
  # via HYPRCURSOR_THEME=Nordzy-cursors-white
  if (cd "$repo_dir" && ./install.sh -p); then
    print_success "Nordzy cursors installed to ~/.local/share/icons"
    log_info "Nordzy cursors installed (xcursors + hyprcursors)"
    return 0
  fi

  print_error "Nordzy cursors installation failed"
  return 1
}

# Build and install the rofi-emoji plugin from source (autotools)
install_rofi_emoji() {
  next_step "Building rofi-emoji plugin from source"

  local repo_url="https://github.com/Mange/rofi-emoji.git"
  local repo_dir="$HOME/.local/share/Aurora/src/rofi-emoji"

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would clone/build/install rofi-emoji from $repo_url"
    return 0
  fi

  if find /usr/lib64/rofi /usr/lib/rofi -maxdepth 1 -name 'emoji.so' 2>/dev/null | grep -q .; then
    print_success "rofi-emoji plugin is already installed"
    return 0
  fi

  local missing_tools=()
  local tool
  for tool in autoreconf automake make gcc pkg-config; do
    command -v "$tool" &>/dev/null || missing_tools+=("$tool")
  done

  if [ ${#missing_tools[@]} -gt 0 ]; then
    print_error "Missing build tools for rofi-emoji: ${missing_tools[*]}"
    echo "  Install with: sudo dnf install -y autoconf automake libtool gcc make pkgconf-pkg-config rofi-devel glib2-devel cairo-devel"
    return 1
  fi

  mkdir -p "$(dirname "$repo_dir")"

  if [ -d "$repo_dir/.git" ]; then
    log_info "Updating existing rofi-emoji checkout at $repo_dir"
    git -C "$repo_dir" pull --ff-only || print_warning "Could not update the rofi-emoji checkout"
  else
    log_info "Cloning rofi-emoji from $repo_url"
    if ! git clone --depth 1 "$repo_url" "$repo_dir"; then
      print_error "Failed to clone rofi-emoji"
      return 1
    fi
  fi

  local old_pwd="$PWD"
  cd "$repo_dir" || {
    print_error "Cannot access $repo_dir"
    return 1
  }

  if ! autoreconf -i; then
    print_error "autoreconf failed for rofi-emoji"
    cd "$old_pwd" || true
    return 1
  fi

  rm -rf build
  mkdir -p build
  cd build || {
    print_error "Cannot access rofi-emoji build directory"
    cd "$old_pwd" || true
    return 1
  }

  if ../configure && make && sudo make install; then
    print_success "rofi-emoji plugin installed"
    log_info "rofi-emoji built from source and installed with make install"
    cd "$old_pwd" || true
    return 0
  fi

  print_error "Failed to build or install rofi-emoji"
  cd "$old_pwd" || true
  return 1
}

install_waytrogen_aurora() {
  next_step "Installing waytrogen-aurora"

  local repo_url="https://github.com/TheAhumMaitra/waytrogen-aurora.git"
  local repo_dir="$HOME/.local/share/Aurora/src/waytrogen-aurora"

  local schema_src="$repo_dir/org.Waytrogen.Waytrogen.gschema.xml"
  local user_schema_dir="$HOME/.local/share/glib-2.0/schemas"

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would clone/build/install waytrogen-aurora and compile its GLib schema"
    return 0
  fi

  mkdir -p "$(dirname "$repo_dir")"
  mkdir -p "$user_schema_dir"

  if [ -d "$repo_dir/.git" ]; then
    log_info "Updating existing waytrogen-aurora checkout at $repo_dir"
    git -C "$repo_dir" pull --ff-only || print_warning "Could not update the waytrogen-aurora checkout"
  else
    log_info "Cloning waytrogen-aurora from $repo_url"
    if ! git clone "$repo_url" "$repo_dir"; then
      print_error "Failed to clone waytrogen-aurora"
      return 1
    fi
  fi

  log_info "Installing waytrogen-aurora via cargo"
  if ! cargo install --path "$repo_dir" --locked; then
    print_error "Failed to build or install waytrogen-aurora"
    return 1
  fi

  if [ -f "$schema_src" ]; then
    if ! command -v glib-compile-schemas &>/dev/null; then
      print_warning "glib-compile-schemas not found; skipping GLib schema compilation"
      return 0
    fi

    if cp -f "$schema_src" "$user_schema_dir/" && glib-compile-schemas "$user_schema_dir"; then
      log_success "Installed and compiled user GLib schemas in $user_schema_dir"
    else
      print_warning "Could not install or compile the waytrogen-aurora GLib schema"
      log_warn "GLib schema install failed for $schema_src"
    fi
  else
    log_warn "No schema file found in waytrogen-aurora repo, skipping schema install"
  fi
}

move_to_backup() {
  local source_path="$1"
  local backup_path="$2"
  local resolved_backup="$backup_path"

  [ -e "$source_path" ] || [ -L "$source_path" ] || return 0

  if [ -e "$resolved_backup" ] || [ -L "$resolved_backup" ]; then
    resolved_backup="${backup_path}.$(date +%s)"
  fi

  mv "$source_path" "$resolved_backup"
  log_info "Moved $source_path to $resolved_backup"
}

setup_lazyvim() {
  next_step "Installing LazyVim starter"

  local nvim_config_dir="$HOME/.config/nvim"
  local nvim_data_dir="$HOME/.local/share/nvim"
  local nvim_state_dir="$HOME/.local/state/nvim"
  local nvim_cache_dir="$HOME/.cache/nvim"

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would backup existing Neovim config/data/cache directories"
    print_warning "[DRY RUN] Would clone LazyVim starter into ~/.config/nvim and remove its .git directory"
    return 0
  fi

  if ! command -v git &>/dev/null; then
    print_error "git is required to install LazyVim"
    return 1
  fi

  move_to_backup "$nvim_config_dir" "${nvim_config_dir}.bak"
  move_to_backup "$nvim_data_dir" "${nvim_data_dir}.bak"
  move_to_backup "$nvim_state_dir" "${nvim_state_dir}.bak"
  move_to_backup "$nvim_cache_dir" "${nvim_cache_dir}.bak"

  mkdir -p "$(dirname "$nvim_config_dir")"
  git clone https://github.com/LazyVim/starter "$nvim_config_dir"
  rm -rf "$nvim_config_dir/.git"

  print_success "LazyVim starter installed to ~/.config/nvim"
  log_info "LazyVim starter installed and repository metadata removed"
}

# Copy dotfiles
copy_dotfiles() {
  next_step "Installing configuration files"

  local config_src="$SCRIPT_DIR/dotfiles/.config"
  local config_dest="$HOME/.config"
  local config_dir
  local config_name
  local target_item

  if [ ! -d "$config_src" ]; then
    print_error "Dotfiles directory not found at $config_src"
    exit 1
  fi

  mkdir -p "$config_dest"

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would backup existing Aurora configs to $BACKUP_DIR"
    print_warning "[DRY RUN] Would remove existing Aurora config files and directories, preserving ~/.config/hypr/User"
    print_warning "[DRY RUN] Would copy config files from $config_src to $config_dest"
    return
  fi

  print_warning "Forcefully replacing existing Aurora configs..."
  mkdir -p "$BACKUP_DIR"

  while IFS= read -r -d '' config_dir; do
    config_name="${config_dir##*/}"
    target_item="$config_dest/$config_name"

    if [ "$config_name" = "hypr" ]; then
      rm -rf "$BACKUP_DIR/$config_name"
      backup_hypr_without_user "$target_item" "$BACKUP_DIR/$config_name"
      mkdir -p "$target_item"
      remove_hypr_children_without_user "$target_item"
      continue
    fi

    if [ -e "$target_item" ] || [ -L "$target_item" ]; then
      rm -rf "$BACKUP_DIR/$config_name"
      cp -r "$target_item" "$BACKUP_DIR/"
      rm -rf "$target_item"
    fi
  done < <(find "$config_src" -mindepth 1 -maxdepth 1 -print0)

  while IFS= read -r -d '' config_dir; do
    config_name="${config_dir##*/}"

    if [ "$config_name" = "hypr" ]; then
      copy_hypr_children_without_user "$config_dir" "$config_dest/$config_name"
      continue
    fi

    cp -rfv "$config_dir" "$config_dest/"
  done < <(find "$config_src" -mindepth 1 -maxdepth 1 -print0)

  log_command "Configuration files installed"
  print_success "Configuration files installed successfully"
}

copy_hypr_children_without_user() {
  local src_hypr="$1"
  local dest_hypr="$2"
  local item
  local item_name

  [ -d "$src_hypr" ] || return 0
  mkdir -p "$dest_hypr"

  while IFS= read -r -d '' item; do
    item_name="${item##*/}"
    [ "$item_name" = "User" ] && continue
    cp -rfv "$item" "$dest_hypr/"
  done < <(find "$src_hypr" -mindepth 1 -maxdepth 1 -print0)
}

backup_hypr_without_user() {
  local target_hypr="$1"
  local backup_hypr="$2"
  local item
  local item_name

  [ -d "$target_hypr" ] || return 0
  mkdir -p "$backup_hypr"

  while IFS= read -r -d '' item; do
    item_name="${item##*/}"
    [ "$item_name" = "User" ] && continue
    cp -r "$item" "$backup_hypr/"
  done < <(find "$target_hypr" -mindepth 1 -maxdepth 1 -print0)
}

remove_hypr_children_without_user() {
  local target_hypr="$1"
  local item
  local item_name

  [ -d "$target_hypr" ] || return 0

  while IFS= read -r -d '' item; do
    item_name="${item##*/}"
    [ "$item_name" = "User" ] && continue
    rm -rf "$item"
  done < <(find "$target_hypr" -mindepth 1 -maxdepth 1 -print0)
}

restore_config_from_backup() {
  local config_name="$1"
  local backup_root="$2"
  local backup_item="$backup_root/$config_name"
  local target_item="$HOME/.config/$config_name"

  [ -d "$backup_item" ] || return 0

  if [ "$config_name" = "hypr" ]; then
    mkdir -p "$target_item"
    remove_hypr_children_without_user "$target_item"
    copy_hypr_children_without_user "$backup_item" "$target_item"
    return 0
  fi

  rm -rf "$target_item" 2>/dev/null
  cp -r "$backup_item" "$HOME/.config/" 2>/dev/null
}

# Rotate log files
rotate_logs() {
  local max_lines=1000

  if [ -f "$INSTALL_LOG" ]; then
    local line_count=$(wc -l <"$INSTALL_LOG")
    if [ "$line_count" -gt "$max_lines" ]; then
      tail -n "$max_lines" "$INSTALL_LOG" >"$INSTALL_LOG.tmp"
      mv "$INSTALL_LOG.tmp" "$INSTALL_LOG"
    fi
  fi
}

prepare_install_log() {
  local log_dir

  log_dir="$(dirname "$INSTALL_LOG")"
  mkdir -p "$log_dir"

  if [ -f "$INSTALL_LOG" ]; then
    rotate_logs
  fi

  : >"$INSTALL_LOG"
}

# Set up shell configuration
setup_shell_config() {
  next_step "Setting up shell configuration"

  local add_to_path="export PATH=\"\$HOME/.cargo/bin:\$HOME/.local/bin:\$PATH\""
  local fish_path_line="set -gx PATH \$HOME/.cargo/bin \$HOME/.local/bin \$PATH"
  local path_was_missing=false
  local shell_name
  shell_name="$(basename "${SHELL:-}")"

  if ! cargo_bin_in_path || ! local_bin_in_path; then
    path_was_missing=true
  fi

  # For bash (interactive shells)
  if [ -f ~/.bashrc ]; then
    if ! grep -q "\.cargo/bin" ~/.bashrc; then
      echo "" >>~/.bashrc
      echo "# Aurora binaries" >>~/.bashrc
      echo "$add_to_path" >>~/.bashrc
      print_success "Updated .bashrc"
      log_command "Updated .bashrc with PATH"
    fi
  fi

  # For bash (login shells, common on Fedora)
  if [ -f ~/.bash_profile ]; then
    if ! grep -q "\.cargo/bin" ~/.bash_profile; then
      echo "" >>~/.bash_profile
      echo "# Aurora binaries" >>~/.bash_profile
      echo "$add_to_path" >>~/.bash_profile
      print_success "Updated .bash_profile"
      log_command "Updated .bash_profile with PATH"
    fi
  fi

  # For zsh
  if [ -f ~/.zshrc ]; then
    if ! grep -q "\.cargo/bin" ~/.zshrc; then
      echo "" >>~/.zshrc
      echo "# Aurora binaries" >>~/.zshrc
      echo "$add_to_path" >>~/.zshrc
      print_success "Updated .zshrc"
      log_command "Updated .zshrc with PATH"
    fi
  fi

  # For fish (Aurora's recommended shell)
  if command -v fish &>/dev/null; then
    mkdir -p ~/.config/fish
    touch ~/.config/fish/config.fish
  fi

  if [ -f ~/.config/fish/config.fish ]; then
    if ! grep -q "\.cargo/bin" ~/.config/fish/config.fish; then
      echo "" >>~/.config/fish/config.fish
      echo "# Aurora binaries" >>~/.config/fish/config.fish
      echo "$fish_path_line" >>~/.config/fish/config.fish
      print_success "Updated fish config"
      log_command "Updated fish config.fish with PATH"
    fi
  fi

  if [ "$path_was_missing" = true ]; then
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
    print_warning "Aurora binaries were added to shell config, but your current terminal may need to reload PATH."
    case "$shell_name" in
    fish)
      echo "  Run: source ~/.config/fish/config.fish"
      ;;
    zsh)
      echo "  Run: source ~/.zshrc"
      ;;
    bash)
      echo "  Run: source ~/.bashrc"
      ;;
    *)
      echo "  Run: exec \$SHELL"
      ;;
    esac
    echo "  Then verify with: command -v <installed-binary>"
  fi
}

verify_installation() {
  next_step "Verifying installation"

  local cargo_bin="$HOME/.cargo/bin"
  local local_bin="$HOME/.local/bin"
  local script_dir="$SCRIPT_DIR/dotfiles/.config/hypr/scripts"
  local required_bins=()
  local missing_bins=()
  local optional_bins=(hyprwave hyprwave-toggle)
  local optional_missing=()
  local bin
  local first_bin=""

  if discover_cargo_binaries "$script_dir"; then
    required_bins=("${DISCOVERED_BINS[@]}")
  else
    print_error "Could not determine Aurora Rust binaries from $script_dir"
    return 1
  fi

  for bin in "${required_bins[@]}"; do
    if [ ! -x "$cargo_bin/$bin" ]; then
      missing_bins+=("$bin")
    fi
  done

  if [ ${#missing_bins[@]} -gt 0 ]; then
    print_error "Missing or non-executable Aurora binaries in ~/.cargo/bin:"
    printf '%s\n' "${missing_bins[@]}" | sed 's/^/  - /'
    return 1
  fi

  print_success "Aurora binaries found in ~/.cargo/bin"
  first_bin="${required_bins[0]}"

  for bin in "${optional_bins[@]}"; do
    if [ ! -x "$local_bin/$bin" ]; then
      optional_missing+=("$bin")
    fi
  done

  if [ ${#optional_missing[@]} -gt 0 ]; then
    print_warning "Optional source-built tools are missing from ~/.local/bin:"
    printf '%s\n' "${optional_missing[@]}" | sed 's/^/  - /'
    echo "  Re-run the installer or build them manually if you need them."
  else
    print_success "hyprwave binaries found in ~/.local/bin"
  fi

  if ! cargo_bin_in_path; then
    print_warning "~/.cargo/bin is not in PATH for this installer process"
  fi

  if command -v "$first_bin" &>/dev/null; then
    print_success "$first_bin is accessible from PATH"
  else
    print_warning "Aurora binaries are installed but not accessible in the current shell"
    echo "  Example installed binary: $cargo_bin/$first_bin"
    echo "  Reload your shell, then run: command -v $first_bin"
  fi
}

wait_for_dnf_settle() {
  local timeout_seconds=60
  local sleep_seconds=2
  local elapsed_seconds=0
  local dnf_lock="/var/cache/libdnf5/_lock"

  log_info "Waiting for package-manager processes to settle before replacing sudo"

  while pgrep -x dnf &>/dev/null || pgrep -x dnf5 &>/dev/null || pgrep -x rpm &>/dev/null || [ -e "$dnf_lock" ]; do
    if [ "$elapsed_seconds" -ge "$timeout_seconds" ]; then
      print_warning "Timed out waiting for dnf/rpm to settle; skipping sudo-rs switch"
      log_warn "dnf/rpm still active or lock file present after ${timeout_seconds}s"
      return 1
    fi

    sleep "$sleep_seconds"
    elapsed_seconds=$((elapsed_seconds + sleep_seconds))
  done

  return 0
}

switch_to_sudo_rs() {
  next_step "Switching sudo to sudo-rs"

  if [ "$SWITCH_SUDO_RS" = false ]; then
    print_warning "Skipping the sudo-rs switch because --no-sudo-rs was passed"
    log_info "sudo-rs switch skipped by user request"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would atomically replace /usr/bin/sudo with a symlink to /usr/bin/sudo-rs"
    return 0
  fi

  if ! wait_for_dnf_settle; then
    return 0
  fi

  if ! is_package_installed sudo-rs; then
    print_warning "sudo-rs package is not installed according to rpm; skipping sudo switch"
    log_warn "sudo-rs package missing from the rpm database"
    return 0
  fi

  if [ ! -x /usr/bin/sudo-rs ]; then
    print_warning "sudo-rs is not installed at /usr/bin/sudo-rs; skipping sudo switch"
    log_warn "sudo-rs binary missing at /usr/bin/sudo-rs"
    return 0
  fi

  # Never fight the alternatives system
  if [ -L /usr/bin/sudo ] && [[ "$(readlink /usr/bin/sudo)" == /etc/alternatives/* ]]; then
    print_warning "/usr/bin/sudo is managed by update-alternatives; skipping the sudo-rs switch"
    log_warn "sudo is alternatives-managed; leaving it untouched"
    return 0
  fi

  if [ -L /usr/bin/sudo ] && [ "$(readlink /usr/bin/sudo)" = "/usr/bin/sudo-rs" ]; then
    print_success "sudo already points to sudo-rs"
    log_info "sudo already linked to sudo-rs"
    return 0
  fi

  if ! sudo /bin/bash -c '
        set -e

        if [ ! -x /usr/bin/sudo-rs ]; then
            echo "sudo-rs binary missing at /usr/bin/sudo-rs" >&2
            exit 1
        fi

        if [ ! -e /usr/bin/sudo-original ]; then
            if [ ! -e /usr/bin/sudo ] && [ ! -L /usr/bin/sudo ]; then
                echo "/usr/bin/sudo does not exist and no backup is present" >&2
                exit 1
            fi

            mv /usr/bin/sudo /usr/bin/sudo-original
        fi

        rm -f /usr/bin/sudo
        ln -s /usr/bin/sudo-rs /usr/bin/sudo
    '; then
    print_error "Failed to link /usr/bin/sudo to /usr/bin/sudo-rs"
    log_error "Could not atomically switch /usr/bin/sudo to /usr/bin/sudo-rs"
    return 1
  fi

  print_success "sudo now points to sudo-rs"
  print_warning "Restore the original sudo with: sudo mv /usr/bin/sudo-original /usr/bin/sudo"
  log_info "Switched /usr/bin/sudo to /usr/bin/sudo-rs"
}

# Create required directories
create_directories() {
  mkdir -p ~/.config
}

apply_default_theme() {
  next_step "Applying default theme"
  local aurora_bin

  aurora_bin="$(command -v aurora || true)"
  if [ -z "$aurora_bin" ] && [ -x "$HOME/.cargo/bin/aurora" ]; then
    aurora_bin="$HOME/.cargo/bin/aurora"
  fi

  if [ -z "$aurora_bin" ]; then
    DEFAULT_THEME_STATUS="failed: aurora binary not found"
    print_error "Cannot apply default theme because the aurora binary was not found"
    return 1
  fi

  log_info "Trying to apply Aurora Default using $aurora_bin"
  "$aurora_bin" apply-theme "Aurora Default"

  DEFAULT_THEME_STATUS="applied: Aurora Default"
  print_success "Applied default theme"
  log_info "Applied default theme - Aurora Default"
}

# Check for existing Aurora installation
check_existing_install() {
  local has_aurora=false
  local aurora_items=()

  # Check for Aurora scripts
  if [ -d "$HOME/.cargo/bin" ]; then
    for script in keybinds_help refresh_system search youtube-downloader settings theme_switcher waybar_refresh waybar_toggle welcome_app; do
      if [ -f "$HOME/.cargo/bin/$script" ]; then
        has_aurora=true
        aurora_items+=("Aurora script: $script")
      fi
    done
  fi

  # Check for Aurora configs
  if [ -d "$HOME/.config/hypr" ]; then
    if grep -R -q --exclude-dir=User "Aurora" "$HOME/.config/hypr" 2>/dev/null; then
      has_aurora=true
      aurora_items+=("Aurora config: ~/.config/hypr")
    fi
  fi

  if [ "$has_aurora" = true ]; then
    print_warning "Existing Aurora installation detected:"
    printf '%s\n' "${aurora_items[@]}" | sed 's/^/  - /'
    echo ""
    print_warning "This script will upgrade/overwrite your Aurora setup."

    if [ "$INTERACTIVE" = true ] && [ "$DRY_RUN" = false ]; then
      read -p "Continue with re-installation? (y/n) " -n 1 -r || true
      echo

      if [[ ! ${REPLY:-} =~ ^[Yy]$ ]]; then
        print_error "Installation cancelled"
        exit 0
      fi
    fi
  fi
}

# Rollback on critical failure
rollback_on_failure() {
  local failure_reason="$1"
  local config_dir
  log_error "Critical failure: $failure_reason"
  print_error "CRITICAL FAILURE: $failure_reason"
  print_warning "Attempting to restore from backup..."

  if [ -d "$BACKUP_DIR" ]; then
    echo ""
    echo "Backup found at $BACKUP_DIR"
    read -p "Restore backed up configs? (y/n) " -n 1 -r || true
    echo

    if [[ ${REPLY:-} =~ ^[Yy]$ ]]; then
      for config_dir in hypr waybar kitty fish rofi; do
        restore_config_from_backup "$config_dir" "$BACKUP_DIR"
      done
      print_success "Configs restored from backup"
      log_info "Configs restored from backup after failure"
    fi
  fi

  print_error "Installation failed. Please check the log: $INSTALL_LOG"
  exit 1
}

# Uninstall Aurora
uninstall_aurora() {
  clear_screen
  echo -e "${BLUE}"
  cat <<"EOF"
    ╔═══════════════════════════════════════╗
    ║      Aurora ™  Uninstallation Script  ║
    ╚═══════════════════════════════════════╝
EOF
  echo -e "${NC}"
  echo ""

  print_header "Uninstalling Aurora"

  echo ""
  print_warning "This will:"
  echo "  • Remove Aurora Rust scripts from ~/.cargo/bin"
  echo "  • Remove hyprwave binaries from ~/.local/bin (if present)"
  echo "  • Restore backed up configuration files (if available)"
  echo "  • Remove Aurora configs from ~/.config"
  echo ""

  read -p "Proceed with uninstallation? (y/n) " -n 1 -r || true
  echo

  if [[ ! ${REPLY:-} =~ ^[Yy]$ ]]; then
    print_warning "Uninstallation cancelled"
    return
  fi

  # Remove Rust scripts
  print_warning "Removing Rust scripts..."
  cargo uninstall aurora 2>/dev/null || print_warning "Aurora binaries not found or already removed"

  # Remove source-built helpers
  if [ -x "$HOME/.local/bin/hyprwave" ] || [ -e "$HOME/.local/share/hyprwave" ]; then
    print_warning "Removing hyprwave files..."
    rm -f "$HOME/.local/bin/hyprwave" "$HOME/.local/bin/hyprwave-toggle" 2>/dev/null || true
    rm -rf "$HOME/.local/share/hyprwave" 2>/dev/null || true
  fi

  # Find most recent backup
  local latest_backup=""
  latest_backup="$(find "$HOME/.config" -maxdepth 1 -type d -name 'aurora_backup_*' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR == 1 { sub(/^[^ ]+ /, ""); print }')" || true

  if [ -d "$latest_backup" ]; then
    print_warning "Found backup at $latest_backup"
    read -p "Restore backed up configs? (y/n) " -n 1 -r || true
    echo

    if [[ ${REPLY:-} =~ ^[Yy]$ ]]; then
      print_warning "Restoring configs..."
      restore_config_from_backup "hypr" "$latest_backup"
      restore_config_from_backup "waybar" "$latest_backup"
      restore_config_from_backup "kitty" "$latest_backup"
      restore_config_from_backup "fish" "$latest_backup"
      restore_config_from_backup "rofi" "$latest_backup"
      print_success "Configs restored"
    fi
  fi

  print_success "Aurora uninstalled successfully"
  echo ""
  print_warning "You may also want to remove the backup and source directories:"
  echo "  rm -rf ~/.config/aurora_backup_*"
  echo "  rm -rf ~/.local/share/Aurora"
  echo ""
  print_warning "Installed RPM packages and COPR repositories were left untouched."
  echo ""
}

# Set fish as the default login shell (always runs at the end)
set_default_shell_to_fish() {
  next_step "Setting fish as default shell"

  if [ "$DRY_RUN" = true ]; then
    FISH_SHELL_STATUS="dry-run: would set fish as default shell"
    print_warning "[DRY RUN] Would set fish as default shell (chsh -s <fish>)"
    return 0
  fi

  local fish_path=""
  if command -v fish &>/dev/null; then
    fish_path="$(command -v fish)"
  elif [ -x /usr/bin/fish ]; then
    fish_path="/usr/bin/fish"
  else
    FISH_SHELL_STATUS="failed: fish is not installed"
    print_error "Fish shell is not installed; cannot set it as default shell"
    echo "  Install with: sudo dnf install -y fish"
    return 1
  fi

  log_info "fish binary: $fish_path"

  # chsh refuses shells not listed in /etc/shells.
  if [ -f /etc/shells ] && ! grep -Fxq "$fish_path" /etc/shells; then
    if [ "$INTERACTIVE" = true ]; then
      print_warning "$fish_path is not listed in /etc/shells; adding it (needs sudo)"
    fi
    if ! echo "$fish_path" | sudo tee -a /etc/shells >/dev/null; then
      FISH_SHELL_STATUS="failed: could not add $fish_path to /etc/shells"
      print_error "Failed to add $fish_path to /etc/shells"
      return 1
    fi
    log_command "Added $fish_path to /etc/shells"
  fi

  # Already fish? Nothing to do — but still record success.
  local current_login_shell=""
  current_login_shell="$(getent passwd "$USER" 2>/dev/null | awk -F: '{print $NF}')" || true
  if [ -n "$current_login_shell" ] && [ "$current_login_shell" = "$fish_path" ]; then
    FISH_SHELL_STATUS="already fish ($fish_path)"
    print_success "fish is already the default shell ($fish_path)"
    return 0
  fi

  # Non-interactive mode: just do it (this is the documented end state).
  if [ "$INTERACTIVE" = false ]; then
    if chsh -s "$fish_path"; then
      FISH_SHELL_STATUS="set to $fish_path"
      log_command "Default shell changed to fish ($fish_path) via chsh"
      print_success "Default shell changed to fish ($fish_path)"
      print_warning "Log out and log back in for the change to apply"
      return 0
    else
      FISH_SHELL_STATUS="failed: chsh -s $fish_path failed"
      print_error "Failed to change default shell to fish"
      return 1
    fi
  fi

  # Interactive: confirm once, then change.
  echo ""
  print_warning "Aurora uses fish as its default shell."
  echo -e "  ${WHITE}Current login shell:${NC} ${CYAN}${current_login_shell:-unknown}${NC}"
  echo -e "  ${WHITE}Aurora default:${NC}      ${CYAN}$fish_path${NC}"
  echo ""
  read -p "Change default shell to fish? (Y/n) " -n 1 -r || true
  echo
  if [[ ${REPLY:-} =~ ^[Nn]$ ]]; then
    FISH_SHELL_STATUS="skipped by user (stayed on ${current_login_shell:-unknown})"
    print_warning "Kept current login shell (${current_login_shell:-unknown})"
    return 0
  fi

  if chsh -s "$fish_path"; then
    FISH_SHELL_STATUS="set to $fish_path"
    log_command "Default shell changed to fish ($fish_path) via chsh"
    print_success "Default shell changed to fish ($fish_path)"
    print_warning "Log out and log back in for the change to apply"
    return 0
  else
    FISH_SHELL_STATUS="failed: chsh -s $fish_path failed"
    print_error "Failed to change default shell to fish"
    return 1
  fi
}

# Final setup
final_setup() {
  echo ""
  print_header "Aurora Setup Complete!"

  echo ""
  echo -e "${MAGENTA}${BOLD}Installation Summary${NC}"
  print_rule
  echo -e "  ${GREEN}✓${NC} ${WHITE}System dependencies verified${NC}"
  echo -e "  ${CYAN}•${NC} ${WHITE}SDDM theme setup:${NC} ${YELLOW}${SDDM_THEME_STATUS}${NC}"
  echo -e "  ${CYAN}•${NC} ${WHITE}Default theme setup:${NC} ${YELLOW}${DEFAULT_THEME_STATUS}${NC}"
  echo -e "  ${GREEN}✓${NC} ${WHITE}Rust scripts installed to ~/.cargo/bin${NC}"
  echo -e "  ${GREEN}✓${NC} ${WHITE}LazyVim starter installed to ~/.config/nvim${NC}"
  echo -e "  ${GREEN}✓${NC} ${WHITE}Configuration files installed${NC}"
  echo -e "  ${GREEN}✓${NC} ${WHITE}Shell environment configured${NC}"
  echo -e "  ${CYAN}•${NC} ${WHITE}Default shell:${NC} ${YELLOW}${FISH_SHELL_STATUS}${NC}"
  print_rule
  echo -e "  ${BLUE}${BOLD}Distro:${NC} ${WHITE}Fedora ${FEDORA_VERSION}${NC}"
  echo -e "  ${BLUE}${BOLD}Mode:${NC} ${WHITE}${INSTALL_MODE^^}${NC}"
  echo -e "  ${BLUE}${BOLD}Install Type:${NC} ${WHITE}${DETECTED_INSTALL_TYPE^^}${NC}"
  echo ""

  # Detect the Hyprland runtime without letting the INFO log lines leak into the
  # JSON value below.
  local hyprland_detected=false
  if detect_hyprland_runtime >/dev/null 2>&1; then
    hyprland_detected=true
  fi

  # Save installation state, but not in dry-run mode: a state file written by a
  # dry run would make the next real run believe Aurora is already installed.
  if [ "$DRY_RUN" = true ]; then
    print_warning "[DRY RUN] Would save installation state to $INSTALL_STATE_FILE"
  else
    cat >"$INSTALL_STATE_FILE" <<STATE_EOF
{
  "version": "1.0",
  "distro": "fedora",
  "distro_version": "$FEDORA_VERSION",
  "install_type": "$DETECTED_INSTALL_TYPE",
  "install_mode": "$INSTALL_MODE",
  "install_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "script_version": "$(git -C "$SCRIPT_DIR" describe --tags --always 2>/dev/null || echo 'unknown')",
  "hyprland_runtime_detected": "$hyprland_detected"
}
STATE_EOF
    log_info "Saved installation state to $INSTALL_STATE_FILE"
  fi

  echo -e "${CYAN}${BOLD}Installation log:${NC} ${WHITE}$INSTALL_LOG${NC}"
  echo ""

  echo -e "${MAGENTA}${BOLD}Next Steps${NC}"
  print_rule
  echo -e "  ${YELLOW}1.${NC} ${WHITE}Reload your shell configuration${NC}"
  echo -e "     ${DARK}exec \$SHELL${NC}"
  echo ""
  echo -e "  ${YELLOW}2.${NC} ${WHITE}Start Hyprland from your login manager${NC}"
  echo -e "     ${DARK}Select the Hyprland session on the SDDM login screen${NC}"
  echo ""
  echo -e "  ${YELLOW}3.${NC} ${WHITE}Preview the SDDM theme if needed${NC}"
  echo -e "     ${DARK}sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/sddm-astronaut-theme/${NC}"
  echo ""
  echo -e "  ${YELLOW}4.${NC} ${WHITE}Check keybindings${NC}"
  echo -e "     ${DARK}Super + H${NC}"
  echo ""
  echo -e "  ${YELLOW}5.${NC} ${WHITE}Review leftover package failures in the log${NC}"
  echo -e "     ${DARK}${INSTALL_LOG}${NC}"
  echo ""

  echo -e "${MAGENTA}${BOLD}Restore Backups${NC}"
  print_rule
  if [ -d "$BACKUP_DIR" ]; then
    echo -e "  ${WHITE}Backup location:${NC} ${CYAN}$BACKUP_DIR${NC}"
  else
    echo -e "  ${DARK}No backups created during this installation${NC}"
  fi
  echo ""

  echo -e "${MAGENTA}${BOLD}Uninstall Aurora${NC}"
  print_rule
  echo -e "  ${DARK}./install-fedora.sh --uninstall${NC}"
  echo ""
}

# Print usage
print_usage() {
  cat <<"EOF"
Aurora Installation Script for Fedora Linux

Usage: ./install-fedora.sh [OPTIONS]

Options:
  --help              Show this help message
  --dry-run           Preview changes without applying them
  --uninstall         Uninstall Aurora and restore backups
  --non-interactive   Run without user prompts (skip packages & Hyprland check)
  --no-sudo-rs        Do not switch /usr/bin/sudo to sudo-rs
  --debug             Show detailed debug information and logs

COPR repositories enabled by this script:
  lionheartp/Hyprland          hyprland, hypridle, hyprshutdown, awww, hyprshot, ...
  sneexy/zen-browser           zen-browser
  maveonair/jetbrains-mono-nerd-fonts (falls back to maveonair/desktop-tools)
  atim/starship                starship
  erikreider/swayosd           swayosd

Examples:
  ./install-fedora.sh                    # Interactive installation with mode selection
  ./install-fedora.sh --dry-run          # Preview what will be installed
  ./install-fedora.sh --non-interactive  # Automated installation (default: stable mode)
  ./install-fedora.sh --debug            # Installation with verbose logging
  ./install-fedora.sh --uninstall        # Remove Aurora and restore backups

EOF
}

# Main installation flow
main() {
  # Keep the original arguments so the self-update re-exec can forward them.
  local -a cli_args=("$@")
  local arg

  # Handle every command-line argument so flags can be combined, for example
  # `--debug --dry-run` or `--non-interactive --no-sudo-rs`.
  for arg in "$@"; do
    case "$arg" in
    --help)
      print_usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --debug)
      LOG_LEVEL="DEBUG"
      ;;
    --uninstall)
      uninstall_aurora
      exit 0
      ;;
    --non-interactive)
      INTERACTIVE=false
      ;;
    --no-sudo-rs)
      SWITCH_SUDO_RS=false
      ;;
    *)
      if [ -n "$arg" ]; then
        print_error "Unknown option: $arg"
        echo ""
        print_usage
        exit 1
      fi
      ;;
    esac
  done

  prepare_install_log
  initialize_logging

  log_info "Aurora Installation Started (Fedora)"
  log_debug "Script location: $SCRIPT_DIR"
  log_debug "Interactive mode: $INTERACTIVE"
  log_debug "Dry-run mode: $DRY_RUN"

  clear_screen
  render_banner

  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}${BOLD}[DRY RUN MODE]${NC} ${WHITE}No changes will be applied${NC}"
    echo ""
  fi

  # Run installation steps
  if [ ${#cli_args[@]} -gt 0 ]; then
    self_update_from_github "${cli_args[@]}"
  else
    self_update_from_github
  fi
  check_fedora
  check_root
  check_home_disk_space
  detect_installation_type
  check_existing_install
  create_directories
  check_dependencies
  select_installation_mode
  validate_hyprland
  enable_copr_repositories
  install_dnf_packages
  setup_network_manager

  if [ "$DRY_RUN" = false ]; then
    install_sddm_theme
    build_rust_scripts
    install_rust_packages
    install_hyprwave
    install_nordzy_cursors
    install_rofi_emoji
    install_waytrogen_aurora
    setup_lazyvim
    copy_dotfiles
    setup_shell_config
    verify_installation
    apply_default_theme
  else
    next_step "Installing SDDM astronaut theme"
    print_warning "[DRY RUN] Would clone/configure the SDDM astronaut theme and install fonts"
    print_warning "[DRY RUN] Would disable competing display managers (gdm, lightdm, ...) and enable sddm.service"

    next_step "Building and installing Rust scripts"
    print_warning "[DRY RUN] Would build and install Rust scripts"

    install_rust_packages

    next_step "Building hyprwave from source"
    print_warning "[DRY RUN] Would clone/build/install hyprwave into ~/.local/bin"

    next_step "Installing Nordzy cursors"
    print_warning "[DRY RUN] Would clone Nordzy-cursors and run ./install.sh -p"

    next_step "Building rofi-emoji plugin from source"
    print_warning "[DRY RUN] Would run autoreconf/configure/make install for rofi-emoji"

    next_step "Installing waytrogen-aurora"
    print_warning "[DRY RUN] Would clone/build/install waytrogen-aurora and compile schemas"

    next_step "Installing LazyVim starter"
    print_warning "[DRY RUN] Would backup Neovim files and install LazyVim starter"

    next_step "Installing configuration files"
    print_warning "[DRY RUN] Would copy configuration files"

    next_step "Setting up shell configuration"
    print_warning "[DRY RUN] Would update shell PATH"

    set_default_shell_to_fish

    next_step "Verifying installation"
    print_warning "[DRY RUN] Would verify installed binaries and PATH"

    next_step "Switching sudo to sudo-rs"
    print_warning "[DRY RUN] Would switch /usr/bin/sudo to /usr/bin/sudo-rs"

    next_step "Applying default theme"
    DEFAULT_THEME_STATUS="dry-run: would apply Aurora Default"
    print_warning "[DRY RUN] Would apply default theme - Aurora Default"
  fi

  set_default_shell_to_fish

  final_setup

  if [ "$DRY_RUN" = false ]; then
    switch_to_sudo_rs
  fi

  log_command "Aurora Installation Completed Successfully"
}

# Run main function
main "$@"
