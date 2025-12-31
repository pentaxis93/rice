#!/usr/bin/env bash
# rice runtime installation (cargo, go, bun, uv)

# Install Rust via rustup
install_rust() {
  if command -v cargo &>/dev/null; then
    local version
    version=$(cargo --version 2>/dev/null | awk '{print $2}')
    log_ok "cargo" "$version" "skipped"
    return 0
  fi

  state_set_current_tool "cargo"
  log_installing "cargo"

  local rustup_args=("-y" "--no-modify-path")
  if [[ "${RICE_VERBOSE:-0}" != "1" ]]; then
    rustup_args+=("-q")
  fi

  if ! run_upstream_installer "https://sh.rustup.rs" -- "${rustup_args[@]}"; then
    log_error "Failed to install Rust"
    state_record_tool_failed "cargo" "rustup installer failed"
    return 1
  fi

  # Source cargo env for this session
  # shellcheck source=/dev/null
  [[ -f "${HOME}/.cargo/env" ]] && source "${HOME}/.cargo/env"

  local version
  version=$(cargo --version 2>/dev/null | awk '{print $2}')
  log_ok "cargo" "$version"
  state_record_tool "cargo" "$version" "rustup"
  state_clear_current_tool
}

# Install Go
install_go() {
  if command -v go &>/dev/null; then
    local version
    version=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
    log_ok "go" "$version" "skipped"
    return 0
  fi

  state_set_current_tool "go"
  log_installing "go"

  # Get latest Go version
  local version
  version=$(curl -sL "https://go.dev/VERSION?m=text" 2>/dev/null | head -1 | sed 's/go//')

  if [[ -z "$version" ]]; then
    log_error "Could not determine latest Go version"
    state_record_tool_failed "go" "version lookup failed"
    return 1
  fi

  local archive="go${version}.linux-${RICE_ARCH_GO}.tar.gz"
  local url="https://go.dev/dl/${archive}"

  # Download
  local tmp_archive
  tmp_archive=$(mktemp)
  if ! download_file "$url" "$tmp_archive"; then
    rm -f "$tmp_archive"
    state_record_tool_failed "go" "download failed"
    return 1
  fi

  # Get checksum from Go's download page
  local checksum_url="https://go.dev/dl/?mode=json"
  local expected_checksum
  expected_checksum=$(curl -sL "$checksum_url" 2>/dev/null | \
    jq -r ".[] | select(.version == \"go${version}\") | .files[] | select(.filename == \"${archive}\") | .sha256" 2>/dev/null)

  if [[ -n "$expected_checksum" ]]; then
    if ! verify_checksum "$tmp_archive" "$expected_checksum"; then
      rm -f "$tmp_archive"
      state_record_tool_failed "go" "checksum verification failed"
      return 1
    fi
  else
    log_warn "Could not verify Go checksum (upstream checksum unavailable)"
  fi

  # Extract to /usr/local
  $RICE_SUDO rm -rf /usr/local/go
  $RICE_SUDO tar -C /usr/local -xzf "$tmp_archive"
  rm -f "$tmp_archive"

  # Add to PATH for this session
  export PATH="/usr/local/go/bin:${HOME}/go/bin:${PATH}"

  log_ok "go" "$version"
  state_record_tool "go" "$version" "binary"
  state_clear_current_tool
}

# Install bun
install_bun() {
  if command -v bun &>/dev/null; then
    local version
    version=$(bun --version 2>/dev/null)
    log_ok "bun" "$version" "skipped"
    return 0
  fi

  state_set_current_tool "bun"
  log_installing "bun"

  # bun installer respects BUN_INSTALL env var
  export BUN_INSTALL="${HOME}/.bun"

  if ! run_upstream_installer "https://bun.sh/install"; then
    log_error "Failed to install bun"
    state_record_tool_failed "bun" "installer failed"
    return 1
  fi

  # Add to PATH for this session
  export PATH="${BUN_INSTALL}/bin:${PATH}"

  local version
  version=$(bun --version 2>/dev/null)
  log_ok "bun" "$version"
  state_record_tool "bun" "$version" "upstream"
  state_clear_current_tool
}

# Install uv (Python package manager)
install_uv() {
  if command -v uv &>/dev/null; then
    local version
    version=$(uv --version 2>/dev/null | awk '{print $2}')
    log_ok "uv" "$version" "skipped"
    return 0
  fi

  state_set_current_tool "uv"
  log_installing "uv"

  # uv installer
  if ! run_upstream_installer "https://astral.sh/uv/install.sh"; then
    log_error "Failed to install uv"
    state_record_tool_failed "uv" "installer failed"
    return 1
  fi

  # Add to PATH for this session
  export PATH="${HOME}/.local/bin:${PATH}"

  local version
  version=$(uv --version 2>/dev/null | awk '{print $2}')
  log_ok "uv" "$version"
  state_record_tool "uv" "$version" "upstream"
  state_clear_current_tool
}

# Install all runtimes
install_runtimes() {
  log_phase "Runtimes"

  local failed=0

  install_rust || ((failed++))
  install_go || ((failed++))
  install_bun || ((failed++))
  install_uv || ((failed++))

  if [[ $failed -gt 0 ]]; then
    log_warn "$failed runtime(s) failed to install"
    return 1
  fi

  state_complete_phase 1
  return 0
}

# Ensure cargo is available in PATH
ensure_cargo_path() {
  if ! command -v cargo &>/dev/null; then
    if [[ -f "${HOME}/.cargo/env" ]]; then
      # shellcheck source=/dev/null
      source "${HOME}/.cargo/env"
    elif [[ -d "${HOME}/.cargo/bin" ]]; then
      export PATH="${HOME}/.cargo/bin:${PATH}"
    fi
  fi
}

# Ensure go is available in PATH
ensure_go_path() {
  if ! command -v go &>/dev/null; then
    if [[ -d "/usr/local/go/bin" ]]; then
      export PATH="/usr/local/go/bin:${HOME}/go/bin:${PATH}"
    fi
  fi
}

# Ensure bun is available in PATH
ensure_bun_path() {
  if ! command -v bun &>/dev/null; then
    if [[ -d "${HOME}/.bun/bin" ]]; then
      export PATH="${HOME}/.bun/bin:${PATH}"
    fi
  fi
}

# Ensure all runtimes are in PATH
ensure_runtime_paths() {
  ensure_cargo_path
  ensure_go_path
  ensure_bun_path
  export PATH="${HOME}/.local/bin:${PATH}"
}
