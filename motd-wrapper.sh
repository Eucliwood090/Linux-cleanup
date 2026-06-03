#!/usr/bin/env bash
# =============================================================================
# motd-wrapper.sh — Lanceur pour les tableaux de bord SSH
# GitHub : https://github.com/Eucliwood090/Linux-cleanup
# =============================================================================

STD="/etc/profile.d/motd-dynamic.sh"
PVE="/etc/profile.d/motd-proxmox.sh"

has_std=false; has_pve=false
[[ -x "$STD" ]] && has_std=true
[[ -x "$PVE" ]] && has_pve=true

if $has_std && $has_pve; then
  echo -e "\n\e[1;36mPlusieurs tableaux de bord disponibles.\e[0m"
  echo -e "  1) Standard Linux"
  echo -e "  2) Proxmox VE"
  echo -en "\n  Votre choix [1/2] : "
  read -r choix
  case "$choix" in
    1) bash "$STD" ;;
    2) bash "$PVE" ;;
    *) echo -e "\e[0;31mChoix invalide.\e[0m" ;;
  esac
elif $has_pve; then
  bash "$PVE"
elif $has_std; then
  bash "$STD"
else
  echo "Aucun MOTD personnalisé n'est installé."
  echo "Utilisez linux-cleanup.sh pour en installer un."
fi
