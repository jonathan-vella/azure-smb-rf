#!/usr/bin/env bash
# =============================================================================
# Shared hook helpers — sourced by hooks/*.sh.
# Keep POSIX-compatible; no bashisms that break sh fallback.
# =============================================================================
# shellcheck shell=bash

# ---- logging -----------------------------------------------------------------
log_step()    { printf '  [%s] %s\n' "$1" "$2"; }
log_substep() { printf '      - %s\n' "$1"; }
log_error()   { printf 'ERROR: %s\n' "$1" >&2; }

# ---- CIDR validation ---------------------------------------------------------
# Returns 0 when $1 looks like a valid IPv4 CIDR with prefix 16–29.
is_valid_cidr() {
  local cidr="$1"
  if ! [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]{1,2})$ ]]; then
    return 1
  fi
  local prefix="${cidr#*/}"
  [[ "$prefix" -ge 16 && "$prefix" -le 29 ]]
}

# ---- CIDR overlap (rough; matches Bicep hook precision) ---------------------
# Converts two CIDRs to 32-bit ints, ANDs with the smaller mask, compares.
cidr_overlaps() {
  local a="$1" b="$2"
  local a_ip="${a%/*}" a_pfx="${a#*/}"
  local b_ip="${b%/*}" b_pfx="${b#*/}"

  _ip_to_int() {
    local IFS=.
    # shellcheck disable=SC2206
    local octets=($1)
    echo $(( (octets[0] << 24) + (octets[1] << 16) + (octets[2] << 8) + octets[3] ))
  }

  local a_int b_int
  a_int="$(_ip_to_int "$a_ip")"
  b_int="$(_ip_to_int "$b_ip")"
  local smaller=$(( a_pfx < b_pfx ? a_pfx : b_pfx ))
  local mask=$(( 0xFFFFFFFF << (32 - smaller) & 0xFFFFFFFF ))
  [[ $(( a_int & mask )) -eq $(( b_int & mask )) ]]
}

# ---- scenario resolution -----------------------------------------------------
# Outputs two lines: DEPLOY_FIREWALL=..  DEPLOY_VPN=..
resolve_scenario_flags() {
  local scenario="${1:-baseline}"
  local fw=false vpn=false
  case "$scenario" in
    firewall) fw=true ;;
    vpn)      vpn=true ;;
    full)     fw=true; vpn=true ;;
    baseline|'') : ;;
    *) log_error "Unknown SCENARIO '$scenario' (allowed: baseline|firewall|vpn|full)"; return 1 ;;
  esac
  # Explicit overrides win when set.
  [[ -n "${DEPLOY_FIREWALL:-}" ]] && fw="$DEPLOY_FIREWALL"
  [[ -n "${DEPLOY_VPN:-}"      ]] && vpn="$DEPLOY_VPN"
  printf 'DEPLOY_FIREWALL=%s\nDEPLOY_VPN=%s\n' "$fw" "$vpn"
}
