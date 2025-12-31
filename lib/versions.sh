#!/usr/bin/env bash
# rice self-maintaining version strategy
# Fetches latest releases from GitHub, caches results, verifies against upstream checksums

# Cache TTL in seconds (1 hour)
VERSION_CACHE_TTL=3600

# GitHub API base URL
GITHUB_API="https://api.github.com"

# Retry settings
MAX_RETRIES=3
RETRY_DELAY=2

# Make a GitHub API request with optional authentication and retry logic
github_api() {
  local endpoint="$1"
  local url="${GITHUB_API}${endpoint}"
  local attempt=1
  local response
  local http_code

  while [[ $attempt -le $MAX_RETRIES ]]; do
    local curl_args=(-s -w "%{http_code}" -o -)

    # Add auth header if token available
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      curl_args+=(-H "Authorization: token ${GITHUB_TOKEN}")
    fi
    curl_args+=(-H "Accept: application/vnd.github.v3+json")

    response=$(curl "${curl_args[@]}" "$url" 2>/dev/null)
    http_code="${response: -3}"
    response="${response:0:-3}"

    case "$http_code" in
      200)
        echo "$response"
        return 0
        ;;
      403)
        # Rate limit - check if we should retry
        if [[ "$response" == *"rate limit"* ]]; then
          if [[ $attempt -lt $MAX_RETRIES ]]; then
            log_detail "GitHub rate limit hit, retrying in ${RETRY_DELAY}s..."
            sleep "$RETRY_DELAY"
            RETRY_DELAY=$((RETRY_DELAY * 2))
            ((attempt++))
            continue
          else
            log_error "GitHub API rate limit exceeded"
            log_detail "Set GITHUB_TOKEN to increase rate limit"
            return 1
          fi
        fi
        ;;
      404)
        log_error "GitHub resource not found: $endpoint"
        return 1
        ;;
      *)
        if [[ $attempt -lt $MAX_RETRIES ]]; then
          log_detail "GitHub API error (HTTP $http_code), retrying..."
          sleep "$RETRY_DELAY"
          ((attempt++))
          continue
        fi
        log_error "GitHub API request failed: HTTP $http_code"
        return 1
        ;;
    esac

    ((attempt++))
  done

  return 1
}

# Get latest release version for a GitHub repo
# Usage: get_latest_release "owner/repo"
get_latest_release() {
  local repo="$1"
  local cache_key="${repo//\//_}"

  # Check cache first
  local cached_version
  cached_version=$(version_cache_get "$cache_key")
  if [[ -n "$cached_version" ]]; then
    echo "$cached_version"
    return 0
  fi

  # Fetch from GitHub
  local response
  if ! response=$(github_api "/repos/${repo}/releases/latest"); then
    return 1
  fi

  local version
  version=$(echo "$response" | jq -r '.tag_name // empty' 2>/dev/null)

  if [[ -z "$version" ]]; then
    log_error "Could not parse version from GitHub response"
    return 1
  fi

  # Strip leading 'v' if present
  version="${version#v}"

  # Cache the result
  version_cache_set "$cache_key" "$version"

  echo "$version"
}

# Get checksum from upstream release assets
# Usage: get_upstream_checksum "owner/repo" "version" "asset_pattern"
# asset_pattern: pattern to match checksum file (e.g., "checksums.txt", "SHA256SUMS")
get_upstream_checksum() {
  local repo="$1"
  local version="$2"
  local checksum_file="$3"
  local binary_name="$4"

  # Construct the checksum file URL
  local url="https://github.com/${repo}/releases/download/v${version}/${checksum_file}"

  log_detail "Fetching checksum from: $url"

  local response
  response=$(curl -sL "$url" 2>/dev/null)
  if [[ $? -ne 0 || -z "$response" ]]; then
    # Try without 'v' prefix
    url="https://github.com/${repo}/releases/download/${version}/${checksum_file}"
    response=$(curl -sL "$url" 2>/dev/null)
    if [[ $? -ne 0 || -z "$response" ]]; then
      log_error "Could not fetch checksum file"
      return 1
    fi
  fi

  # Parse checksum for the specific binary
  # Handles both "CHECKSUM  filename" and "CHECKSUM filename" formats
  local checksum
  checksum=$(echo "$response" | grep -E "(^[a-f0-9]{64})[[:space:]]+.*${binary_name}" | head -1 | awk '{print $1}')

  if [[ -z "$checksum" ]]; then
    # Try alternate format: filename: CHECKSUM
    checksum=$(echo "$response" | grep -E "${binary_name}.*:[[:space:]]*([a-f0-9]{64})" | head -1 | sed -E 's/.*:[[:space:]]*([a-f0-9]{64}).*/\1/')
  fi

  if [[ -z "$checksum" || ${#checksum} -ne 64 ]]; then
    log_detail "Checksum file content:"
    log_detail "$response"
    log_error "Could not extract SHA256 checksum for $binary_name"
    return 1
  fi

  echo "$checksum"
}

# Check for user version override
# Usage: check_version_override "TOOL"
# Returns: version if override exists, empty otherwise
check_version_override() {
  local tool="$1"
  local var_name="${tool^^}_VERSION"  # Uppercase

  # Check environment variable first
  local env_value
  env_value="${!var_name:-}"
  if [[ -n "$env_value" ]]; then
    echo "$env_value"
    return 0
  fi

  # Check overrides file
  if [[ -f "$RICE_VERSION_OVERRIDES" ]]; then
    local file_value
    file_value=$(grep -E "^${var_name}=" "$RICE_VERSION_OVERRIDES" 2>/dev/null | cut -d= -f2)
    if [[ -n "$file_value" ]]; then
      echo "$file_value"
      return 0
    fi
  fi

  return 1
}

# Get version to install (override or latest)
# Usage: get_install_version "owner/repo" "tool_name"
get_install_version() {
  local repo="$1"
  local tool="$2"

  # Check for override first
  local override
  override=$(check_version_override "$tool")
  if [[ -n "$override" ]]; then
    log_detail "Using override version for $tool: $override"
    echo "$override"
    return 0
  fi

  # Get latest from GitHub
  get_latest_release "$repo"
}

# Version cache management
version_cache_get() {
  local key="$1"

  if [[ ! -f "$RICE_VERSION_CACHE" ]]; then
    return 1
  fi

  if ! command -v jq &>/dev/null; then
    return 1
  fi

  # Check if cache entry exists and is fresh
  local entry
  entry=$(jq -r ".\"$key\" // empty" "$RICE_VERSION_CACHE" 2>/dev/null)
  if [[ -z "$entry" ]]; then
    return 1
  fi

  local cached_time version
  cached_time=$(echo "$entry" | jq -r '.cached_at // 0' 2>/dev/null)
  version=$(echo "$entry" | jq -r '.version // empty' 2>/dev/null)

  if [[ -z "$version" ]]; then
    return 1
  fi

  # Check TTL
  local now
  now=$(date +%s)
  local age=$((now - cached_time))

  if [[ $age -gt $VERSION_CACHE_TTL ]]; then
    log_detail "Cache expired for $key (age: ${age}s)"
    return 1
  fi

  log_detail "Using cached version for $key: $version"
  echo "$version"
}

version_cache_set() {
  local key="$1"
  local version="$2"

  if ! command -v jq &>/dev/null; then
    return 0
  fi

  local now
  now=$(date +%s)

  # Create cache file if it doesn't exist
  if [[ ! -f "$RICE_VERSION_CACHE" ]]; then
    echo "{}" > "$RICE_VERSION_CACHE"
  fi

  local tmp
  tmp=$(mktemp)
  jq ".\"$key\" = {\"version\": \"$version\", \"cached_at\": $now}" \
    "$RICE_VERSION_CACHE" > "$tmp" && mv "$tmp" "$RICE_VERSION_CACHE"
}

# Compare versions (returns 0 if v1 >= v2)
version_gte() {
  local v1="$1"
  local v2="$2"

  # Use sort -V for version comparison
  local oldest
  oldest=$(printf '%s\n%s\n' "$v1" "$v2" | sort -V | head -n1)
  [[ "$oldest" == "$v2" ]]
}

# Get installed version of a command
get_installed_version() {
  local cmd="$1"
  local version_flag="${2:---version}"

  if ! command -v "$cmd" &>/dev/null; then
    return 1
  fi

  local output
  output=$("$cmd" "$version_flag" 2>&1 | head -1)

  # Extract version number (handles various formats)
  local version
  version=$(echo "$output" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)

  if [[ -n "$version" ]]; then
    echo "$version"
    return 0
  fi

  return 1
}

# Check if tool needs update
# Usage: needs_update "tool" "latest_version"
needs_update() {
  local tool="$1"
  local latest="$2"

  local installed
  installed=$(get_installed_version "$tool")
  if [[ -z "$installed" ]]; then
    # Not installed, needs "update" (install)
    return 0
  fi

  if version_gte "$installed" "$latest"; then
    log_detail "$tool is up to date ($installed >= $latest)"
    return 1
  fi

  log_detail "$tool needs update ($installed < $latest)"
  return 0
}
