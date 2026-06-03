#!/usr/bin/env bash
# =============================================================================
# motd-dynamic.sh — Tableau de bord SSH compact
# Installation : sudo cp motd-dynamic.sh /etc/profile.d/motd-dynamic.sh
# GitHub : https://github.com/Eucliwood090/Linux-cleanup
# =============================================================================

R='\e[0;31m'; Y='\e[1;33m'; G='\e[0;32m'; C='\e[0;36m'
W='\e[1;37m'; DIM='\e[2m'; BOLD='\e[1m'; RESET='\e[0m'

DISK_WARN=70; DISK_CRIT=90
RAM_WARN=75;  RAM_CRIT=90
CPU_WARN=60;  CPU_CRIT=85
TEMP_WARN=65; TEMP_CRIT=80

cpct() {
  local v=$1 w=$2 c=$3
  (( v >= c )) && echo -e "${R}${v}%${RESET}" && return
  (( v >= w )) && echo -e "${Y}${v}%${RESET}" && return
  echo -e "${G}${v}%${RESET}"
}

bar() {
  local pct=$1 w=$2 c=$3 width=25 f b=""
  f=$(( pct * width / 100 ))
  for ((i=0;i<f;i++));      do b+="█"; done
  for ((i=f;i<width;i++));  do b+="░"; done
  (( pct >= c )) && echo -e "${R}${b}${RESET}" && return
  (( pct >= w )) && echo -e "${Y}${b}${RESET}" && return
  echo -e "${G}${b}${RESET}"
}

sep() { echo -e "${DIM}──────────────────────────────────────────────────${RESET}"; }

# ── collecte ──────────────────────────────────────────────────────────────────

HNAME=$(hostname -s)
OS=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "?")

# Disque
DISK_USED=$(df -h / | awk 'NR==2{print $3}')
DISK_TOTAL=$(df -h / | awk 'NR==2{print $2}')
DISK_PCT=$(df / | awk 'NR==2{gsub(/%/,"",$5); print $5}')

# Docker logs (CORRIGÉ : du -sm pour forcer les Mégaoctets)
DOCKER_LOGS=""
if [[ -d /var/lib/docker/containers ]]; then
  SZ=$(du -sm /var/lib/docker/containers/*/*-json.log 2>/dev/null \
    | awk '{sum+=$1} END{print sum}')
  [[ -n "$SZ" && "$SZ" -gt 0 ]] && DOCKER_LOGS="${SZ}M"
fi

# Journal (CORRIGÉ : Regex plus permissive)
JOURNAL_SIZE=$(journalctl --disk-usage 2>/dev/null \
  | grep -oE '[0-9]+(\.[0-9]+)?[ ]*[KMG]i?B?' | tail -1 || echo "?")

# RAM
RAM_TOTAL=$(awk '/MemTotal/{print $2}'    /proc/meminfo)
RAM_AVAIL=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
RAM_USED=$(( RAM_TOTAL - RAM_AVAIL ))
RAM_PCT=$(( RAM_USED * 100 / RAM_TOTAL ))
RAM_USED_H=$(awk  "BEGIN{printf \"%.1f\", ${RAM_USED}/1048576}")
RAM_TOTAL_H=$(awk "BEGIN{printf \"%.1f\", ${RAM_TOTAL}/1048576}")

# CPU
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
LOAD1=$(cut -d' ' -f1 /proc/loadavg)
CORES=$(nproc)
CPU_PCT=$(awk "BEGIN{p=int(${LOAD1}*100/${CORES}); print (p>100)?100:p}")

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
  DOCKER_UP=$(docker ps -q    2>/dev/null | wc -l)
  DOCKER_LIST=$(docker ps --format "{{.Names}}|{{.Status}}" 2>/dev/null | head -10)
fi

# Processus gourmands CPU ou RAM > 5% (CORRIGÉ : colonnes inversées pour éviter les bugs d'espaces)
TOP_PROCS=$(ps -eo %cpu,%mem,comm --sort=-%cpu 2>/dev/null \
  | awk 'NR>1 && ($1>5||$2>5){
      cmd=""; for(i=3;i<=NF;i++) cmd=cmd $i " ";
      sub(/ $/, "", cmd);
      printf "  %-18s cpu:%-7s ram:%s\n", substr(cmd,1,18), $1"%", $2"%"
    }' | head -5)

# Services en échec
FAILED=$(systemctl list-units --state=failed --no-legend --no-pager 2>/dev/null \
  | awk '{print $1}' \
  | grep -v '^\*$' \
  | grep -v '^$' \
  | head -5 | tr '\n' '  ')

# Mises à jour
UPDATES=""
if [[ -x /usr/lib/update-notifier/apt-check ]]; then
  N=$(/usr/lib/update-notifier/apt-check 2>&1 | cut -d';' -f1)
  [[ "${N:-0}" -gt 0 ]] 2>/dev/null && UPDATES=" | ${Y}${N} maj dispo${RESET}"
fi

# ── affichage ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${C}  ${HNAME}${RESET}  ${DIM}|${RESET}  ${OS}  ${DIM}|${RESET}  ${KERNEL}  ${DIM}|${RESET}  ${UPTIME}${UPDATES}"
sep

# Disque
D_PCT_STR=$(cpct $DISK_PCT $DISK_WARN $DISK_CRIT)
D_BAR=$(bar $DISK_PCT $DISK_WARN $DISK_CRIT)
echo -e "  ${BOLD}DISQUE${RESET}  ${DISK_USED}/${DISK_TOTAL}  ${D_PCT_STR}  ${D_BAR}"
if [[ -n "$DOCKER_LOGS" ]]; then
  echo -e "  ${DIM}  logs docker: ${DOCKER_LOGS}  |  journal: ${JOURNAL_SIZE}${RESET}"
else
  echo -e "  ${DIM}  journal: ${JOURNAL_SIZE}${RESET}"
fi

# RAM
R_PCT_STR=$(cpct $RAM_PCT $RAM_WARN $RAM_CRIT)
R_BAR=$(bar $RAM_PCT $RAM_WARN $RAM_CRIT)
echo -e "  ${BOLD}RAM${RESET}     ${RAM_USED_H}Go/${RAM_TOTAL_H}Go  ${R_PCT_STR}  ${R_BAR}"

# CPU
C_PCT_STR=$(cpct $CPU_PCT $CPU_WARN $CPU_CRIT)
C_BAR=$(bar $CPU_PCT $CPU_WARN $CPU_CRIT)
echo -e "  ${BOLD}CPU${RESET}     load: ${LOAD}  (${CORES} coeurs)  ${C_PCT_STR}  ${C_BAR}"

if [[ -n "$TEMP" ]]; then
  if   (( TEMP_INT >= TEMP_CRIT )); then echo -e "  ${DIM}  temp: ${R}${TEMP}C SURCHAUFFE${RESET}"
  elif (( TEMP_INT >= TEMP_WARN )); then echo -e "  ${DIM}  temp: ${Y}${TEMP}C${RESET}"
  else                                   echo -e "  ${DIM}  temp: ${G}${TEMP}C${RESET}"
  fi
fi

sep

# Docker
if [[ $DOCKER_TOTAL -gt 0 ]]; then
  DOCKER_DOWN=$(( DOCKER_TOTAL - DOCKER_UP ))
  DSTATUS="${G}${DOCKER_UP} actif(s)${RESET}"
  [[ $DOCKER_DOWN -gt 0 ]] && DSTATUS="${DSTATUS}  ${Y}${DOCKER_DOWN} arrete(s)${RESET}"
  echo -e "  ${BOLD}DOCKER${RESET}  ${DSTATUS}"
  while IFS='|' read -r name status; do
    short=$(echo "$status" | sed 's/Up //;s/ (.*)//' | cut -c1-25)
    echo -e "  ${DIM}  ${name}  ${short}${RESET}"
  done <<< "$DOCKER_LIST"
  sep
fi

# Alertes
ALERTS=false
if [[ -n "$TOP_PROCS" ]]; then
  echo -e "  ${Y}PROCESSUS ACTIFS${RESET}"
  echo -e "$TOP_PROCS"
  ALERTS=true
fi
if [[ -n "$FAILED" ]]; then
  echo -e "  ${R}SERVICES EN ECHEC :${RESET}  ${FAILED}"
  ALERTS=true
fi
$ALERTS || echo -e "  ${G}Nominal - aucune alerte${RESET}"

sep
echo -e "  ${DIM}$(date '+%d/%m/%Y %H:%M')  |  sudo bash linux-cleanup.sh${RESET}"
echo ""
