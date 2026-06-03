#!/usr/bin/env bash
# =============================================================================
# linux-cleanup.sh
# Purge Docker logs & system logs, then enforce size limits going forward.
# Tested on: Debian / Ubuntu / Raspberry Pi OS
#
# Usage:
#   sudo bash linux-cleanup.sh          # interactive (recommended first run)
#   sudo bash linux-cleanup.sh --dry-run
#   sudo bash linux-cleanup.sh --auto   # non-interactive (cron / CI)
#
# GitHub: https://github.com/YOURNAME/linux-cleanup
# =============================================================================

set -euo pipefail

# ── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }

# ── defaults ─────────────────────────────────────────────────────────────────
DRY_RUN=false
AUTO=false

DOCKER_LOG_MAX_SIZE="50m"   # max size per log file
DOCKER_LOG_MAX_FILES="3"    # number of rotated files kept
JOURNAL_MAX_USE="500M"      # total journald disk quota
JOURNAL_MAX_RETENTION="2weeks"

# ── argument parsing ──────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=true ;;
    --auto)    AUTO=true ;;
    --help|-h)
      echo "Usage: sudo bash $0 [--dry-run] [--auto]"
      echo "  --dry-run   Show what would be done, change nothing"
      echo "  --auto      Non-interactive mode (no prompts)"
      exit 0 ;;
    *) error "Unknown argument: $arg"; exit 1 ;;
  esac
done

# ── helpers ───────────────────────────────────────────────────────────────────
run() {
  if $DRY_RUN; then
    echo -e "  ${YELLOW}[DRY-RUN]${RESET} $*"
  else
    eval "$@"
  fi
}

ask() {
  # ask <question> → returns 0 (yes) or 1 (no)
  local question="$1"
  if $AUTO; then return 0; fi
  echo -en "${BOLD}$question [Y/n] ${RESET}"
  read -r reply
  [[ "${reply:-Y}" =~ ^[Yy]$ ]]
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)."
    exit 1
  fi
}

disk_usage_before() {
  df -h / | awk 'NR==2 {print $3 " used / " $2 " total (" $5 " full)"}'
}

# ── checks ────────────────────────────────────────────────────────────────────
require_root

$DRY_RUN && warn "DRY-RUN mode — nothing will be modified."

echo -e "\n${BOLD}╔══════════════════════════════════════════╗"
echo -e   "║       linux-cleanup.sh                   ║"
echo -e   "╚══════════════════════════════════════════╝${RESET}"
echo -e "Disk before: $(disk_usage_before)\n"

# ══════════════════════════════════════════════════════════════════════════════
header "1/4 · Docker container logs (truncate)"
# ══════════════════════════════════════════════════════════════════════════════

if ! command -v docker &>/dev/null; then
  warn "Docker not found — skipping Docker steps."
  DOCKER_AVAILABLE=false
else
  DOCKER_AVAILABLE=true
  LOG_SIZE=$(du -sh /var/lib/docker/containers/*/*-json.log 2>/dev/null \
    | awk '{sum+=$1} END {print sum+0}' || echo "0")
  info "Current Docker log usage:"
  du -sh /var/lib/docker/containers/*/*-json.log 2>/dev/null \
    | sort -rh | head -10 || info "(no log files found)"

  if ask "\nTruncate all Docker container log files now?"; then
    # truncate is safe: keeps the file handle open for the running container
    run "truncate -s 0 /var/lib/docker/containers/*/*-json.log"
    success "Docker logs truncated."
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
header "2/4 · Docker system prune (stopped containers, dangling images)"
# ══════════════════════════════════════════════════════════════════════════════

if $DOCKER_AVAILABLE; then
  info "Disk used by Docker objects:"
  docker system df 2>/dev/null || true

  if ask "\nRun 'docker system prune -f' (keeps running containers & named volumes)?"; then
    run "docker system prune -f"
    success "Docker pruned."
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
header "3/4 · Apply log-size limits going forward"
# ══════════════════════════════════════════════════════════════════════════════

# ── 3a. Docker daemon.json ────────────────────────────────────────────────────
if $DOCKER_AVAILABLE; then
  DAEMON_JSON="/etc/docker/daemon.json"
  DESIRED_CONF=$(cat <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "${DOCKER_LOG_MAX_SIZE}",
    "max-file": "${DOCKER_LOG_MAX_FILES}"
  }
}
EOF
)

  NEED_DAEMON_UPDATE=true
  if [[ -f "$DAEMON_JSON" ]]; then
    # Simple check: if max-size already set we skip
    if grep -q "max-size" "$DAEMON_JSON" 2>/dev/null; then
      info "daemon.json already contains max-size — skipping."
      NEED_DAEMON_UPDATE=false
    fi
  fi

  if $NEED_DAEMON_UPDATE; then
    info "Will write $DAEMON_JSON:"
    echo "$DESIRED_CONF"
    if ask "\nApply daemon.json and restart Docker?"; then
      if [[ -f "$DAEMON_JSON" ]]; then
        run "cp $DAEMON_JSON ${DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S)"
        warn "Backup saved: ${DAEMON_JSON}.bak.*"
      fi
      run "echo '$DESIRED_CONF' > $DAEMON_JSON"
      run "systemctl restart docker"
      success "Docker daemon restarted with log limits."
      warn "⚠  Existing containers keep old config until recreated."
      warn "   Run: docker compose down && docker compose up -d"
    fi
  fi
fi

# ── 3b. journald — purge + limites ───────────────────────────────────────────
JOURNALD_CONF="/etc/systemd/journald.conf.d/99-size-limit.conf"

JOURNAL_DISK=$(journalctl --disk-usage 2>/dev/null | tail -1)
info "Journald disk usage : $JOURNAL_DISK"
info "Détail /var/log/journal :"
du -sh /var/log/journal/* 2>/dev/null | sort -rh | head -10 \
  || info "(répertoire vide ou inexistant)"

# -- purge immédiate --
if ask "\nPurger le journal maintenant (garder ${JOURNAL_MAX_RETENTION} / ${JOURNAL_MAX_USE}) ?"; then
  run "journalctl --vacuum-time=${JOURNAL_MAX_RETENTION}"
  run "journalctl --vacuum-size=${JOURNAL_MAX_USE}"
  success "Journal purgé."
  info "Espace libéré :"
  journalctl --disk-usage 2>/dev/null | tail -1 || true
fi

# -- limites permanentes --
NEED_JOURNAL_CONF=true
if [[ -f "$JOURNALD_CONF" ]] && grep -q "SystemMaxUse" "$JOURNALD_CONF" 2>/dev/null; then
  info "$JOURNALD_CONF déjà configuré — skipping."
  NEED_JOURNAL_CONF=false
fi

if $NEED_JOURNAL_CONF && ask "\nAppliquer les limites permanentes journald (${JOURNAL_MAX_USE} max) ?"; then
  run "mkdir -p /etc/systemd/journald.conf.d"
  run "cat > $JOURNALD_CONF <<EOF
[Journal]
SystemMaxUse=${JOURNAL_MAX_USE}
SystemMaxFileSize=50M
MaxRetentionSec=${JOURNAL_MAX_RETENTION}
EOF"
  run "systemctl restart systemd-journald"
  success "Journald limité à ${JOURNAL_MAX_USE} / ${JOURNAL_MAX_RETENTION}."
fi

# ══════════════════════════════════════════════════════════════════════════════
header "4/4 · /var/log — old syslog / compressed archives"
# ══════════════════════════════════════════════════════════════════════════════

info "Largest files in /var/log:"
find /var/log -type f \( -name "*.gz" -o -name "*.log" \) -exec du -sh {} \; 2>/dev/null \
  | sort -rh | head -15

if ask "\nDelete compressed log archives (*.gz) older than 7 days?"; then
  run "find /var/log -type f -name '*.gz' -mtime +7 -delete"
  success "Old compressed logs deleted."
fi

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
header "Summary"
echo -e "Disk after:  $(disk_usage_before)"
$DRY_RUN && warn "DRY-RUN — no changes were made. Re-run without --dry-run to apply."
echo ""
success "Done! Recommended next steps:"
echo "  1. Recreate Docker containers to apply new log limits:"
echo "       docker compose down && docker compose up -d"
echo "  2. Schedule this script monthly via cron:"
echo "       echo '0 3 1 * * root bash /usr/local/sbin/linux-cleanup.sh --auto' \\"
echo "         | sudo tee /etc/cron.d/linux-cleanup"
echo ""
