#!/usr/bin/env bash
# =============================================================================
# motd-proxmox.sh — Tableau de bord SSH pour Proxmox VE
# GitHub : https://github.com/Eucliwood090/Linux-cleanup
# =============================================================================

R='\e[0;31m'; Y='\e[1;33m'; G='\e[0;32m'; C='\e[0;36m'
W='\e[1;37m'; DIM='\e[2m'; BOLD='\e[1m'; RESET='\e[0m'

DISK_WARN=70; DISK_CRIT=90
RAM_WARN=75;  RAM_CRIT=90
CPU_WARN=60;  CPU_CRIT=85

cpct() {
  local v=$1 w=$2 c=$3
  (( $(echo "$v >= $c" | bc -l) )) && echo -e "${R}${v}%${RESET}" && return
  (( $(echo "$v >= $w" | bc -l) )) && echo -e "${Y}${v}%${RESET}" && return
  echo -e "${G}${v}%${RESET}"
}

bar() {
  local pct=${1%.*} w=$2 c=$3 width=20 f b=""
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
PVE_VER=$(pveversion 2>/dev/null | awk -F'/' '{print $1" "$2}' || echo "Proxmox ?")
KERNEL=$(uname -r)
UPTIME=$(uptime -p 2>/dev/null | sed 's/up //' || echo "?")

# Ressources Système
RAM_TOTAL=$(awk '/MemTotal/{print $2}' /proc/meminfo)
RAM_AVAIL=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
RAM_USED=$(( RAM_TOTAL - RAM_AVAIL ))
RAM_PCT=$(( RAM_USED * 100 / RAM_TOTAL ))
RAM_USED_H=$(awk "BEGIN{printf \"%.1f\", ${RAM_USED}/1048576}")
RAM_TOTAL_H=$(awk "BEGIN{printf \"%.1f\", ${RAM_TOTAL}/1048576}")

LOAD=$(cut -d' ' -f1-3 /proc/loadavg)
LOAD1=$(cut -d' ' -f1 /proc/loadavg)
CORES=$(nproc)
CPU_PCT=$(awk "BEGIN{p=int(${LOAD1}*100/${CORES}); print (p>100)?100:p}")

# VMs & CTs
VM_RUN=$(qm list 2>/dev/null | awk '$3=="running"{c++} END{print c+0}')
VM_STOP=$(qm list 2>/dev/null | awk '$3=="stopped"{c++} END{print c+0}')
CT_RUN=$(pct list 2>/dev/null | awk '$3=="running"{c++} END{print c+0}')
CT_STOP=$(pct list 2>/dev/null | awk '$3=="stopped"{c++} END{print c+0}')

# ── affichage ─────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}${C}  ${HNAME}${RESET}  ${DIM}|${RESET}  ${PVE_VER}  ${DIM}|${RESET}  ${KERNEL}  ${DIM}|${RESET}  ${UPTIME}"
sep

# CPU & RAM
R_PCT_STR=$(cpct $RAM_PCT $RAM_WARN $RAM_CRIT)
R_BAR=$(bar $RAM_PCT $RAM_WARN $RAM_CRIT)
echo -e "  ${BOLD}RAM${RESET}     ${RAM_USED_H}Go/${RAM_TOTAL_H}Go  ${R_PCT_STR}  ${R_BAR}"

C_PCT_STR=$(cpct $CPU_PCT $CPU_WARN $CPU_CRIT)
C_BAR=$(bar $CPU_PCT $CPU_WARN $CPU_CRIT)
echo -e "  ${BOLD}CPU${RESET}     load: ${LOAD}  (${CORES}c)  ${C_PCT_STR}  ${C_BAR}"

sep

# Proxmox Stats
echo -e "  ${BOLD}MACHINES VIRTUELLES & CONTENEURS${RESET}"
echo -e "  VMs : ${G}${VM_RUN} actives${RESET}  ${DIM}|${RESET}  ${Y}${VM_STOP} stoppées${RESET}"
echo -e "  CTs : ${G}${CT_RUN} actifs${RESET}   ${DIM}|${RESET}  ${Y}${CT_STOP} stoppés${RESET}"

sep

# Stockage (ZFS, LVM, Dir)
echo -e "  ${BOLD}STOCKAGES PROXMOX${RESET}"
if command -v pvesm &>/dev/null; then
  # On parse la sortie de pvesm status pour afficher chaque stockage
  pvesm status 2>/dev/null | awk 'NR>1 {print $1, $2, $3, $7}' | tr -d '%' | while read name type status pct; do
    if [[ "$status" == "active" ]]; then
      pct_val=${pct%.*}
      S_BAR=$(bar "$pct_val" "$DISK_WARN" "$DISK_CRIT")
      S_PCT_STR=$(cpct "$pct_val" "$DISK_WARN" "$DISK_CRIT")
      printf "  %-12s %-6s %b  %b\n" "$name" "($type)" "$S_PCT_STR" "$S_BAR"
    else
      printf "  %-12s %-6s %b\n" "$name" "($type)" "${R}INACTIF${RESET}"
    fi
  done
else
  echo -e "  ${DIM}Impossible de lire l'état du stockage.${RESET}"
fi

sep
echo -e "  ${DIM}$(date '+%d/%m/%Y %H:%M')  |  Commande 'motd' pour rafraîchir${RESET}"
echo ""
