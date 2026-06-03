#!/usr/bin/env bash
# =============================================================================
# motd-dynamic.sh — Tableau de bord affiché à chaque connexion SSH
# Installation : sudo cp motd-dynamic.sh /etc/profile.d/motd-dynamic.sh
# =============================================================================

# ── couleurs ──────────────────────────────────────────────────────────────────
R='\033[0;31m'; Y='\033[1;33m'; G='\033[0;32m'
C='\033[0;36m'; B='\033[1;34m'; W='\033[1;37m'
DIM='\033[2m'; BOLD='\033[1m'; RESET='\033[0m'

# ── seuils d'alerte ───────────────────────────────────────────────────────────
DISK_WARN=70;   DISK_CRIT=90     # % disque
RAM_WARN=75;    RAM_CRIT=90      # % RAM
CPU_WARN=60;    CPU_CRIT=85      # % CPU (charge)
TEMP_WARN=65;   TEMP_CRIT=80     # °C

# ── helpers ───────────────────────────────────────────────────────────────────
color_pct() {
  local val=$1 warn=$2 crit=$3
  if   (( val >= crit )); then echo -e "${R}${val}%${RESET}"
  elif (( val >= warn )); then echo -e "${Y}${val}%${RESET}"
  else                         echo -e "${G}${val}%${RESET}"
  fi
}

bar() {
  # bar <pct> <width>
  local pct=$1 width=${2:-20} warn=$3 crit=$4
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local b=""
  for ((i=0; i<filled; i++)); do b+="█"; done
  for ((i=0; i<empty;  i++)); do b+="░"; done
  if   (( pct >= crit )); then echo -e "${R}${b}${RESET}"
  elif (( pct >= warn )); then echo -e "${Y}${b}${RESET}"
  else                         echo -e "${G}${b}${RESET}"
  fi
}

sep() { echo -e "${DIM}─────────────────────────────────────────────────────${RESET}"; }

# ══════════════════════════════════════════════════════════════════════════════
#  COLLECTE DES DONNÉES
# ══════════════════════════════════════════════════════════════════════════════

# hostname & OS
HOSTNAME=$(hostname -s)
OS=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -o)
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk -F, '{print $1}' | awk '{print $3,$4}')

# ── disque ────────────────────────────────────────────────────────────────────
DISK_INFO=$(df -h / | awk 'NR==2 {print $3, $2, $5}')
DISK_USED=$(echo $DISK_INFO | awk '{print $1}')
DISK_TOTAL=$(echo $DISK_INFO | awk '{print $2}')
DISK_PCT=$(echo $DISK_INFO | awk '{print $3}' | tr -d '%')

# Docker logs si présent
DOCKER_LOGS_SIZE=""
if [[ -d /var/lib/docker/containers ]]; then
  SZ=$(du -sh /var/lib/docker/containers/*/*-json.log 2>/dev/null \
    | awk '{sum+=$1} END {printf "%.0f", sum}')
  [[ -n "$SZ" && "$SZ" -gt 0 ]] && DOCKER_LOGS_SIZE="${SZ}M"
fi

# Journal
JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null \
  | grep -oP '[\d.]+\s*[KMGT]iB' | head -1 || echo "?")

# ── RAM ───────────────────────────────────────────────────────────────────────
RAM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_FREE_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
RAM_USED_KB=$(( RAM_TOTAL_KB - RAM_FREE_KB ))
RAM_PCT=$(( RAM_USED_KB * 100 / RAM_TOTAL_KB ))
RAM_USED=$(awk "BEGIN {printf \"%.1f\", ${RAM_USED_KB}/1048576}")
RAM_TOTAL=$(awk "BEGIN {printf \"%.1f\", ${RAM_TOTAL_KB}/1048576}")

# ── CPU load ──────────────────────────────────────────────────────────────────
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
LOAD1=$(cut -d' ' -f1 /proc/loadavg)
CORES=$(nproc)
CPU_PCT=$(awk "BEGIN {pct=int(${LOAD1}*100/${CORES}); print (pct>100)?100:pct}")

# ── température ───────────────────────────────────────────────────────────────
TEMP=""
TEMP_ALERT=false
if command -v vcgencmd &>/dev/null; then
  # Raspberry Pi
  TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oP '[\d.]+')
elif [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
  TEMP=$(awk '{printf "%.1f", $1/1000}' /sys/class/thermal/thermal_zone0/temp)
fi
if [[ -n "$TEMP" ]]; then
  TEMP_INT=${TEMP%.*}
  (( TEMP_INT >= TEMP_CRIT )) && TEMP_ALERT=true
fi

# ── Docker ───────────────────────────────────────────────────────────────────
DOCKER_UP=0; DOCKER_TOTAL=0; DOCKER_STOPPED=""
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  DOCKER_TOTAL=$(docker ps -aq 2>/dev/null | wc -l)
  DOCKER_UP=$(docker ps -q 2>/dev/null | wc -l)
  DOCKER_DOWN=$(( DOCKER_TOTAL - DOCKER_UP ))
  [[ $DOCKER_DOWN -gt 0 ]] && DOCKER_STOPPED=" ${Y}(${DOCKER_DOWN} arrêté(s))${RESET}"
fi

# ── processus gourmands ───────────────────────────────────────────────────────
TOP_CPU=$(ps -eo pid,comm,%cpu --sort=-%cpu 2>/dev/null \
  | awk 'NR>1 && $3>5 {printf "  PID %-7s %-20s CPU: %s%%\n", $1, $2, $3}' \
  | head -5)
TOP_RAM=$(ps -eo pid,comm,%mem --sort=-%mem 2>/dev/null \
  | awk 'NR>1 && $3>5 {printf "  PID %-7s %-20s RAM: %s%%\n", $1, $2, $3}' \
  | head -5)

# ── services en échec ─────────────────────────────────────────────────────────
FAILED_SERVICES=$(systemctl --failed --no-legend 2>/dev/null \
  | awk '{print "  ⚠  "$1}' | head -5)

# ── mises à jour dispo ───────────────────────────────────────────────────────
UPDATES=""
if command -v apt-get &>/dev/null; then
  COUNT=$(/usr/lib/update-notifier/apt-check 2>&1 | cut -d';' -f1 2>/dev/null || echo "0")
  [[ "$COUNT" -gt 0 ]] 2>/dev/null && UPDATES="${Y}${COUNT} mise(s) à jour disponible(s)${RESET}"
fi

# ══════════════════════════════════════════════════════════════════════════════
#  AFFICHAGE
# ══════════════════════════════════════════════════════════════════════════════
clear

echo -e "${BOLD}${C}"
echo "  ███████╗███████╗██████╗ ██╗   ██╗███████╗██╗   ██╗██████╗ "
echo "  ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██║   ██║██╔══██╗"
echo "  ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██║   ██║██████╔╝"
echo "  ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██║   ██║██╔══██╗"
echo "  ███████║███████╗██║  ██║ ╚████╔╝ ███████╗╚██████╔╝██║  ██║"
echo "  ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝ ╚═════╝ ╚═╝  ╚═╝"
echo -e "${RESET}"

sep
printf "  ${W}%-15s${RESET} %s\n" "🖥  Hôte"    "${BOLD}${HOSTNAME}${RESET}"
printf "  ${W}%-15s${RESET} %s\n" "🐧 OS"       "${OS}"
printf "  ${W}%-15s${RESET} %s\n" "⚙  Kernel"   "${KERNEL}"
printf "  ${W}%-15s${RESET} %s\n" "⏱  Uptime"   "${UPTIME}"
[[ -n "$UPDATES" ]] && printf "  ${W}%-15s${RESET} %b\n" "📦 Updates"  "${UPDATES}"
sep

# ── Disque ────────────────────────────────────────────────────────────────────
echo -e "  ${BOLD}💾 DISQUE${RESET}   ${DISK_USED} / ${DISK_TOTAL}  $(color_pct $DISK_PCT $DISK_WARN $DISK_CRIT)"
echo -e "  $(bar $DISK_PCT 30 $DISK_WARN $DISK_CRIT)"
if [[ -n "$DOCKER_LOGS_SIZE" ]]; then
  echo -e "  ${DIM}└─ logs Docker : ${DOCKER_LOGS_SIZE}  │  journal : ${JOURNAL_SIZE}${RESET}"
else
  echo -e "  ${DIM}└─ journal systemd : ${JOURNAL_SIZE}${RESET}"
fi

echo ""

# ── RAM ───────────────────────────────────────────────────────────────────────
echo -e "  ${BOLD}🧠 RAM${RESET}      ${RAM_USED} Go / ${RAM_TOTAL} Go  $(color_pct $RAM_PCT $RAM_WARN $RAM_CRIT)"
echo -e "  $(bar $RAM_PCT 30 $RAM_WARN $RAM_CRIT)"

echo ""

# ── CPU ───────────────────────────────────────────────────────────────────────
echo -e "  ${BOLD}⚡ CPU${RESET}      Load: ${LOAD}  (${CORES} cœurs)  $(color_pct $CPU_PCT $CPU_WARN $CPU_CRIT)"
echo -e "  $(bar $CPU_PCT 30 $CPU_WARN $CPU_CRIT)"
if [[ -n "$TEMP" ]]; then
  if $TEMP_ALERT; then
    echo -e "  ${DIM}└─ Température : ${R}${TEMP}°C ⚠ SURCHAUFFE${RESET}"
  elif (( TEMP_INT >= TEMP_WARN )); then
    echo -e "  ${DIM}└─ Température : ${Y}${TEMP}°C${RESET}"
  else
    echo -e "  ${DIM}└─ Température : ${G}${TEMP}°C${RESET}"
  fi
fi

echo ""
sep

# ── Docker ────────────────────────────────────────────────────────────────────
if [[ $DOCKER_TOTAL -gt 0 ]]; then
  echo -e "  ${BOLD}🐳 Docker${RESET}   ${G}${DOCKER_UP} actif(s)${RESET}${DOCKER_STOPPED} / ${DOCKER_TOTAL} total"
  docker ps --format "  ${DIM}├─ {{.Names}} ({{.Status}})${RESET}" 2>/dev/null | head -10
  echo ""
fi

# ── Alertes ───────────────────────────────────────────────────────────────────
ALERTS=false

if [[ -n "$TOP_CPU" ]]; then
  echo -e "  ${BOLD}${Y}⚠  Processus gourmands en CPU${RESET}"
  echo -e "${TOP_CPU}"
  echo ""
  ALERTS=true
fi

if [[ -n "$TOP_RAM" ]]; then
  echo -e "  ${BOLD}${Y}⚠  Processus gourmands en RAM${RESET}"
  echo -e "${TOP_RAM}"
  echo ""
  ALERTS=true
fi

if [[ -n "$FAILED_SERVICES" ]]; then
  echo -e "  ${BOLD}${R}✖  Services en échec${RESET}"
  echo -e "${FAILED_SERVICES}"
  echo ""
  ALERTS=true
fi

$ALERTS || echo -e "  ${G}✔  Aucune alerte — tout semble nominal${RESET}\n"

sep
echo -e "  ${DIM}Connecté le $(date '+%d/%m/%Y à %H:%M:%S') · linux-cleanup.sh disponible${RESET}"
sep
echo ""
