#!/usr/bin/env bash
# rice configuration deployment

# Rice marker comment
RICE_MARKER="# rice-managed - https://github.com/pentaxis93/rice"

# Deploy a config file
# Usage: deploy_config "source_path" "dest_path"
deploy_config() {
  local source="$1"
  local dest="$2"
  local dest_dir
  dest_dir="$(dirname "$dest")"

  # Ensure destination directory exists
  mkdir -p "$dest_dir"

  # Check if destination exists
  if [[ -f "$dest" ]]; then
    # Check for rice marker
    if grep -q "rice-managed\|managed by rice" "$dest" 2>/dev/null; then
      # Rice owns this file, overwrite it
      log_detail "Updating rice-managed config: $dest"
    else
      # User's file, back it up
      local backup_name
      backup_name="$(basename "$dest").$(date +%Y%m%d%H%M%S)"
      local backup_path="${RICE_BACKUPS_DIR}/${backup_name}"

      cp "$dest" "$backup_path"
      log_detail "Backed up existing config: $backup_path"
    fi
  fi

  # Copy the config
  cp "$source" "$dest"
  log_detail "Deployed: $dest"
}

# Deploy all configurations
deploy_configs() {
  log_phase "Configuration"

  local rice_dir="${RICE_INSTALL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
  local config_dir="${rice_dir}/configs"

  # Ensure rice config directory exists
  mkdir -p "${RICE_STATE_DIR}"
  mkdir -p "${RICE_BACKUPS_DIR}"

  # Deploy zshrc
  deploy_config "${config_dir}/zshrc" "${RICE_STATE_DIR}/zshrc"
  ensure_zshrc_sources_rice

  # Deploy p10k config
  deploy_config "${config_dir}/p10k.zsh" "${HOME}/.p10k.zsh"

  # Deploy aliases
  deploy_config "${config_dir}/aliases.sh" "${RICE_STATE_DIR}/aliases.sh"

  # Deploy tmux config
  deploy_config "${config_dir}/tmux.conf" "${RICE_STATE_DIR}/tmux.conf"
  ensure_tmux_symlink

  # Deploy helix config
  mkdir -p "${HOME}/.config/helix"
  deploy_config "${config_dir}/helix/config.toml" "${HOME}/.config/helix/config.toml"

  # Deploy lf config
  mkdir -p "${HOME}/.config/lf"
  deploy_config "${config_dir}/lf/lfrc" "${HOME}/.config/lf/lfrc"
  deploy_config "${config_dir}/lf/preview.sh" "${HOME}/.config/lf/preview.sh"
  chmod +x "${HOME}/.config/lf/preview.sh"

  # Deploy gitconfig (include-style)
  deploy_config "${config_dir}/gitconfig" "${RICE_STATE_DIR}/gitconfig"
  ensure_git_includes_rice

  # Deploy welcome message
  deploy_config "${config_dir}/welcome.txt" "${RICE_STATE_DIR}/welcome.txt"

  log_ok "Configuration" "" "synced"
  state_complete_phase 8
}

# Ensure ~/.zshrc sources rice zshrc
ensure_zshrc_sources_rice() {
  local zshrc="${HOME}/.zshrc"
  local rice_zshrc="${RICE_STATE_DIR}/zshrc"
  local source_line="source \"${rice_zshrc}\""

  # Check if .zshrc exists
  if [[ ! -f "$zshrc" ]]; then
    # Create minimal .zshrc that sources rice
    cat > "$zshrc" << EOF
${RICE_MARKER}
# Source rice configuration
${source_line}
EOF
    log_detail "Created ~/.zshrc"
    return 0
  fi

  # Check if already sourcing rice
  if grep -q "source.*rice.*zshrc\|\.config/rice/zshrc" "$zshrc" 2>/dev/null; then
    log_detail "~/.zshrc already sources rice config"
    return 0
  fi

  # Check for rice marker (we own the file)
  if grep -q "rice-managed\|managed by rice" "$zshrc" 2>/dev/null; then
    # Overwrite with rice sourcing
    cat > "$zshrc" << EOF
${RICE_MARKER}
# Source rice configuration
${source_line}

# User customizations go in ~/.zshrc.local
EOF
    log_detail "Updated rice-managed ~/.zshrc"
    return 0
  fi

  # User has their own .zshrc - add source line at the end
  {
    echo ""
    echo "# >>> rice >>>"
    echo "${source_line}"
    echo "# <<< rice <<<"
  } >> "$zshrc"
  log_detail "Added rice source to existing ~/.zshrc"
}

# Ensure tmux.conf symlink
ensure_tmux_symlink() {
  local tmux_conf="${HOME}/.tmux.conf"
  local rice_tmux="${RICE_STATE_DIR}/tmux.conf"

  if [[ -L "$tmux_conf" ]]; then
    # Already a symlink
    local target
    target="$(readlink "$tmux_conf")"
    if [[ "$target" == "$rice_tmux" ]]; then
      log_detail "~/.tmux.conf symlink already correct"
      return 0
    fi
  fi

  if [[ -f "$tmux_conf" && ! -L "$tmux_conf" ]]; then
    # Regular file exists
    if grep -q "rice-managed\|managed by rice" "$tmux_conf" 2>/dev/null; then
      # Rice owns it, can replace
      rm "$tmux_conf"
    else
      # User's file, back it up
      local backup_name="tmux.conf.$(date +%Y%m%d%H%M%S)"
      mv "$tmux_conf" "${RICE_BACKUPS_DIR}/${backup_name}"
      log_detail "Backed up ~/.tmux.conf"
    fi
  fi

  ln -sf "$rice_tmux" "$tmux_conf"
  log_detail "Created symlink: ~/.tmux.conf -> $rice_tmux"
}

# Ensure git includes rice gitconfig
ensure_git_includes_rice() {
  local gitconfig="${HOME}/.gitconfig"
  local rice_gitconfig="${RICE_STATE_DIR}/gitconfig"

  # Check if git command is available
  if ! command -v git &>/dev/null; then
    return 0
  fi

  # Check if already including rice config
  if git config --global --get-all include.path 2>/dev/null | grep -q "rice/gitconfig"; then
    log_detail "~/.gitconfig already includes rice config"
    return 0
  fi

  # Add include
  git config --global --add include.path "$rice_gitconfig"
  log_detail "Added rice include to ~/.gitconfig"
}

# Verify all configs are deployed
verify_configs() {
  local all_ok=true

  [[ -f "${RICE_STATE_DIR}/zshrc" ]] || all_ok=false
  [[ -f "${HOME}/.p10k.zsh" ]] || all_ok=false
  [[ -f "${RICE_STATE_DIR}/aliases.sh" ]] || all_ok=false
  [[ -f "${RICE_STATE_DIR}/tmux.conf" ]] || all_ok=false
  [[ -f "${HOME}/.config/helix/config.toml" ]] || all_ok=false
  [[ -f "${HOME}/.config/lf/lfrc" ]] || all_ok=false

  $all_ok
}
