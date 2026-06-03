#!/usr/bin/env bash
# =============================================================================
# motd-dynamic.sh — Tableau de bord SSH compact
# Installation : sudo cp motd-dynamic.sh /etc/profile.d/motd-dynamic.sh
# GitHub : https://github.com/Eucliwood090/Linux-cleanup
# =============================================================================

# ── couleurs ─────────────────────────────────────────────────────────────────
R='\e[0;31m'; Y='\e[1;33m'; G='\e[0;32m'; C='\e[0;36m'
W='\e[1;37m'; DIM='\e[2m'; BOLD='\e[1m'; RESET='\e[0m'

# ── seuils ───────────────────────────────────────────────────────────────────
DISK_WARN=70; DISK_CRIT=90
RAM_WARN=75;  RAM_CRIT=90
CPU_WARN=60;  CPU_CRIT=85
TEMP_WARN=65; TEMP_CRIT=80

# ── helpers ───────────────────────────────────────────────────────────────────
cpct() {
  # cpct <val> <warn> <crit> — colore un pourcentage
  local v=$1 w=$2 c=$3
  (( v >= c )) && echo -e "${R}${v}%${RESET}" && return
  (( v >= w )) && echo -e "${Y}${v}%${RESET}" && return
  echo -e "${G}${v}%${RESET}"
}

bar() {
  # bar <pct> <warn> <crit> — barre de 25 chars
  local pct=$1 w=$2 c=$3 width=25
  local f=$(( pct * width / 100 )) b=""
  for ((i=0;i<f;i++));         do b+="█"; done
  for ((i=f;i<width;i++));     do b+="░"; done
  (( pct >= c )) && echo -e "${R}${b}${RESET}" && return
  (( pct >= w )) && echo -e "${Y}${b}${RESET}" && return
  echo -e "${G}${b}${RESET}"
}

sep() { echo -e "${DIM}──────────────────────────────────────────────────${RESET}"; }

# ══════════════════════════════════════════════════════════════════════════════
#  COLLECTE
# ══════════════════════════════════════════════════════════════════════════════

HNAME=$(hostname -s)
OS=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "?")

# Disque
read DISK_USED DISK_TOTAL DISK_PCT_RAW <<< $(df -h / | awk 'NR==2{print $3,$2,$5}')
DISK_PCT=${DISK_PCT_RAW//%/}

# Docker logs
DOCKER_LOGS=""
if [[ -d /var/lib/docker/containers ]]; then
  SZ=$(du -sh /var/lib/docker/containers/*/*-json.log 2>/dev/null \
    | awk '{gsub(/[^0-9.]/,"",$1); sum+=$1} END{printf "%.0f",sum+0}')
  [[ "${SZ:-0}" -gt 0 ]] && DOCKER_LOGS="${SZ}M"
fi

# Journal
JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null \
  | grep -oE '[0-9.]+ [KMGT]?i?B' | tail -1 || echo "?")

# RAM
RAM_TOTAL=$(awk '/MemTotal/{print $2}' /proc/meminfo)
RAM_AVAIL=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
RAM_USED=$(( RAM_TOTAL - RAM_AVAIL ))
RAM_PCT=$(( RAM_USED * 100 / RAM_TOTAL ))
RAM_USED_H=$(awk "BEGIN{printf \"%.1f\",${RAM_USED}/1048576}")
RAM_TOTAL_H=$(awk "BEGIN{printf \"%.1f\",${RAM_TOTAL}/1048576}")

# CPU
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
LOAD1=$(cut -d' ' -f1 /proc/loadavg)
CORES=$(nproc)
CPU_PCT=$(awk "BEGIN{p=int(${LOAD1}*100/${CORES});print(p>100)?100:p}")

# Température
TEMP=""; TEMP_INT=0
if command -v vcgencmd &>/dev/null; then
  TEMP=$(vcgencmd measure_temp 2>/dev/null | grep -oE '[0-9.]+')
elif [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
  TEMP=$(awk '{printf "%.0f",$1/1000}' /sys/class/thermal/thermal_zone0/temp)
fi
[[ -n "$TEMP" ]] && TEMP_INT=${TEMP%.*}

# Docker conteneurs
DOCKER_UP=0; DOCKER_TOTAL=0; DOCKER_LIST=""
if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  DOCKER_TOTAL=$(docker ps -aq 2>/dev/null | wc -l)
  DOCKER_UP=$(docker ps -q 2>/dev/null | wc -l)
  DOCKER_LIST=$(docker ps --format "{{.Names}}|{{.Status}}" 2>/dev/null | head -10)
fi

# Processus gourmands (CPU ou RAM > 5%)
TOP_PROCS=$(ps -eo comm,%cpu,%mem --sort=-%cpu 2>/dev/null \
  | awk 'NR>1 && ($2>5 || $3>5) {
      cpu_col = ($2>5) ? "\033[1;33m" $2"%" "\033[0m" : $2"%"
      ram_col = ($3>5) ? "\033[1;33m" $3"%" "\033[0m" : $3"%"
      printf "  %-18s cpu:%-7s ram:%s\n", $1, cpu_col, ram_col
    }' | head -5)

# Services en échec
FAILED=$(systemctl list-units --state=failed --no-legend --no-pager 2>/dev/null \
  | awk '{print $1}' | head -5 | tr '\n' ' ')

# Mises à jour
UPDATES=""
if [[ -x /usr/lib/update-notifier/apt-check ]]; then
  N=$(/usr/lib/update-notifier/apt-check 2>&1 | cut -d';' -f1)
  [[ "${N:-0}" -gt 0 ]] && UPDATES="${Y}${N} màj dispo${RESET}"
fi

# ══════════════════════════════════════════════════════════════════════════════
#  AFFICHAGE
# ══════════════════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${C}  🖥  ${HNAME}${RESET}  ${DIM}│${RESET}  ${OS}  ${DIM}│${RESET}  ${KERNEL}  ${DIM}│${RESET}  ⏱ ${UPTIME}${RESET}"
[[ -n "$UPDATES" ]] && echo -e "  📦 ${UPDATES}"
sep

# Disque / RAM / CPU sur 3 lignes compactes
printf "  ${BOLD}💾${RESET} %-6s %s/%s $(cpct $DISK_PCT $DISK_WARN $DISK_CRIT)  $(bar $DISK_PCT $DISK_WARN $DISK_CRIT)\n" \
  "DISQUE" "$DISK_USED" "$DISK_TOTAL"
[[ -n "$DOCKER_LOGS" ]] \
  && echo -e "  ${DIM}   └─ docker logs: ${DOCKER_LOGS}  │  journal: ${JOURNAL_SIZE}${RESET}" \
  || echo -e "  ${DIM}   └─ journal: ${JOURNAL_SIZE}${RESET}"

printf "  ${BOLD}🧠${RESET} %-6s %sGo/%sGo $(cpct $RAM_PCT $RAM_WARN $RAM_CRIT)  $(bar $RAM_PCT $RAM_WARN $RAM_CRIT)\n" \
  "RAM" "$RAM_USED_H" "$RAM_TOTAL_H"

printf "  ${BOLD}⚡${RESET} %-6s load:%-16s $(cpct $CPU_PCT $CPU_WARN $CPU_CRIT)  $(bar $CPU_PCT $CPU_WARN $CPU_CRIT)\n" \
  "CPU" "$LOAD"

if [[ -n "$TEMP" ]]; then
  if   (( TEMP_INT >= TEMP_CRIT )); then TCOL="${R}${TEMP}°C ⚠${RESET}"
  elif (( TEMP_INT >= TEMP_WARN )); then TCOL="${Y}${TEMP}°C${RESET}"
  else                                    TCOL="${G}${TEMP}°C${RESET}"
  fi
  echo -e "  ${DIM}   └─ temp: ${TCOL}${RESET}"
fi

sep

# Docker
if [[ $DOCKER_TOTAL -gt 0 ]]; then
  DOCKER_DOWN=$(( DOCKER_TOTAL - DOCKER_UP ))
  printf "  ${BOLD}🐳${RESET} Docker  ${G}%d actif(s)${RESET}" "$DOCKER_UP"
  [[ $DOCKER_DOWN -gt 0 ]] && printf "  ${Y}%d arrêté(s)${RESET}" "$DOCKER_DOWN"
  echo ""
  while IFS='|' read -r name status; do
    # Truncate status to keep it short
    short_status=$(echo "$status" | sed 's/Up //;s/ (.*//' | cut -c1-20)
    printf "  ${DIM}  %-22s %s${RESET}\n" "$name" "$short_status"
  done <<< "$DOCKER_LIST"
  sep
fi

# Alertes
ALERTS=false
if [[ -n "$TOP_PROCS" ]]; then
  echo -e "  ${Y}⚠ Processus actifs${RESET}"
  echo -e "$TOP_PROCS"
  ALERTS=true
fi
if [[ -n "$FAILED" ]]; then
  echo -e "  ${R}✖ Services en échec :${RESET} ${FAILED}"
  ALERTS=true
fi
$ALERTS || echo -e "  ${G}✔ Nominal${RESET}"

sep
echo -e "  ${DIM}$(date '+%d/%m/%Y %H:%M')  ·  run: linux-cleanup.sh${RESET}\n"
