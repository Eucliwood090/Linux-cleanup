#!/usr/bin/env bash
# =============================================================================
# linux-cleanup.sh — Purge logs Docker & système, limites permanentes, MOTD SSH
# Testé sur : Debian / Ubuntu / Raspberry Pi OS / Armbian
#
# GitHub : https://github.com/Eucliwood090/Linux-cleanup
# =============================================================================

set -euo pipefail

# ── couleurs ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERREUR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}══ $* ══${RESET}"; }
sep()     { echo -e "${CYAN}─────────────────────────────────────────────${RESET}"; }

# ── paramètres ────────────────────────────────────────────────────────────────
DOCKER_LOG_MAX_SIZE="50m"
DOCKER_LOG_MAX_FILES="3"
JOURNAL_MAX_USE="500M"
JOURNAL_MAX_RETENTION="2weeks"
MOTD_URL="https://raw.githubusercontent.com/Eucliwood090/Linux-cleanup/main/motd-dynamic.sh"

# ── helpers ───────────────────────────────────────────────────────────────────
run() {
  if [[ "${DRY_RUN:-false}" == true ]]; then
    echo -e "  ${YELLOW}[DRY-RUN]${RESET} $*"
  else
    eval "$@"
  fi
}

disk_usage() {
  df -h / | awk 'NR==2 {print $3 " utilisés / " $2 " total (" $5 " plein)"}'
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    error "Ce script doit être lancé en root (sudo)."
    exit 1
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#  MENU PRINCIPAL
# ══════════════════════════════════════════════════════════════════════════════
require_root

echo -e "\n${BOLD}${CYAN}"
echo "  ██╗     ██╗███╗   ██╗██╗   ██╗██╗  ██╗"
echo "  ██║     ██║████╗  ██║██║   ██║╚██╗██╔╝"
echo "  ██║     ██║██╔██╗ ██║██║   ██║ ╚███╔╝ "
echo "  ██║     ██║██║╚██╗██║██║   ██║ ██╔██╗ "
echo "  ███████╗██║██║ ╚████║╚██████╔╝██╔╝ ██╗"
echo "  ╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝  CLEANUP${RESET}"
echo ""
sep
echo -e "  Disque actuel : $(disk_usage)"
sep
echo ""
echo -e "  ${BOLD}Que souhaitez-vous faire ?${RESET}"
echo ""
echo -e "  ${GREEN}1)${RESET} ${BOLD}Mode automatique${RESET}   — Nettoie tout sans poser de questions"
echo -e "  ${CYAN}2)${RESET} ${BOLD}Mode manuel${RESET}        — Confirme chaque étape"
echo -e "  ${YELLOW}3)${RESET} ${BOLD}Installer le MOTD${RESET}  — Tableau de bord à chaque connexion SSH"
echo -e "  ${RED}q)${RESET} Quitter"
echo ""
echo -en "  Votre choix [1/2/3/q] : "
read -r CHOICE

case "$CHOICE" in
  1) MODE="auto" ;;
  2) MODE="manuel" ;;
  3) MODE="motd" ;;
  q|Q) echo ""; info "Au revoir."; exit 0 ;;
  *) error "Choix invalide."; exit 1 ;;
esac

DRY_RUN=false

# ══════════════════════════════════════════════════════════════════════════════
#  FONCTIONS DE NETTOYAGE
# ══════════════════════════════════════════════════════════════════════════════

ask() {
  # En mode auto : toujours oui. En mode manuel : demande.
  local question="$1"
  if [[ "$MODE" == "auto" ]]; then
    echo -e "${CYAN}[AUTO]${RESET}  $question → oui"
    return 0
  fi
  echo -en "${BOLD}$question [O/n] ${RESET}"
  read -r rep
  [[ "${rep:-O}" =~ ^[OoYy]$ ]]
}

# ── Docker logs ───────────────────────────────────────────────────────────────
do_docker_logs() {
  header "1/4 · Logs des conteneurs Docker"
  if ! command -v docker &>/dev/null; then
    warn "Docker introuvable — étape ignorée."
    DOCKER_AVAILABLE=false
    return
  fi
  DOCKER_AVAILABLE=true
  info "Taille actuelle des logs Docker :"
  du -sh /var/lib/docker/containers/*/*-json.log 2>/dev/null \
    | sort -rh | head -10 || info "(aucun fichier log trouvé)"

  if ask "\nTronquer tous les logs Docker maintenant ?"; then
    run "truncate -s 0 /var/lib/docker/containers/*/*-json.log 2>/dev/null || true"
    success "Logs Docker vidés."
  fi
}

# ── Docker prune ──────────────────────────────────────────────────────────────
do_docker_prune() {
  header "2/4 · Docker system prune"
  if [[ "${DOCKER_AVAILABLE:-false}" != true ]]; then return; fi
  info "Espace utilisé par Docker :"
  docker system df 2>/dev/null || true
  if ask "\nSupprimer conteneurs arrêtés et images orphelines ?"; then
    run "docker system prune -f"
    success "Docker purgé."
  fi
}

# ── Journald ──────────────────────────────────────────────────────────────────
do_journald() {
  header "3/4 · Journal systemd"
  JOURNALD_CONF="/etc/systemd/journald.conf.d/99-size-limit.conf"
  info "Espace utilisé par journald : $(journalctl --disk-usage 2>/dev/null | tail -1)"
  info "Détail /var/log/journal :"
  du -sh /var/log/journal/* 2>/dev/null | sort -rh | head -10 \
    || info "(répertoire vide)"

  if ask "\nPurger le journal (garder ${JOURNAL_MAX_RETENTION} / max ${JOURNAL_MAX_USE}) ?"; then
    run "journalctl --vacuum-time=${JOURNAL_MAX_RETENTION}"
    run "journalctl --vacuum-size=${JOURNAL_MAX_USE}"
    success "Journal purgé."
    info "Après purge : $(journalctl --disk-usage 2>/dev/null | tail -1)"
  fi

  if [[ -f "$JOURNALD_CONF" ]] && grep -q "SystemMaxUse" "$JOURNALD_CONF" 2>/dev/null; then
    info "Limites journald déjà configurées — skipping."
  elif ask "\nAppliquer les limites permanentes journald ?"; then
    run "mkdir -p /etc/systemd/journald.conf.d"
    if [[ "$DRY_RUN" == false ]]; then
      cat > "$JOURNALD_CONF" <<EOF
[Journal]
SystemMaxUse=${JOURNAL_MAX_USE}
SystemMaxFileSize=50M
MaxRetentionSec=${JOURNAL_MAX_RETENTION}
EOF
    else
      echo -e "  ${YELLOW}[DRY-RUN]${RESET} Écriture de $JOURNALD_CONF"
    fi
    run "systemctl restart systemd-journald"
    success "Journald limité à ${JOURNAL_MAX_USE} / ${JOURNAL_MAX_RETENTION}."
  fi
}

# ── /var/log archives ─────────────────────────────────────────────────────────
do_varlog() {
  header "4/4 · Archives /var/log"
  info "Fichiers les plus lourds dans /var/log :"
  find /var/log -type f \( -name "*.gz" -o -name "*.log" \) \
    -exec du -sh {} \; 2>/dev/null | sort -rh | head -15

  if ask "\nSupprimer les archives *.gz de plus de 7 jours ?"; then
    run "find /var/log -type f -name '*.gz' -mtime +7 -delete"
    success "Archives supprimées."
  fi

  # daemon.json Docker
  if [[ "${DOCKER_AVAILABLE:-false}" == true ]]; then
    DAEMON_JSON="/etc/docker/daemon.json"
    if [[ -f "$DAEMON_JSON" ]] && grep -q "max-size" "$DAEMON_JSON" 2>/dev/null; then
      info "daemon.json déjà configuré avec max-size — skipping."
    elif ask "\nAppliquer les limites de logs Docker (daemon.json) ?"; then
      if [[ -f "$DAEMON_JSON" ]]; then
        run "cp $DAEMON_JSON ${DAEMON_JSON}.bak.$(date +%Y%m%d%H%M%S)"
        warn "Backup : ${DAEMON_JSON}.bak.*"
      fi
      if [[ "$DRY_RUN" == false ]]; then
        cat > "$DAEMON_JSON" <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "${DOCKER_LOG_MAX_SIZE}",
    "max-file": "${DOCKER_LOG_MAX_FILES}"
  }
}
EOF
      else
        echo -e "  ${YELLOW}[DRY-RUN]${RESET} Écriture de $DAEMON_JSON"
      fi
      run "systemctl restart docker"
      success "Docker daemon redémarré avec limites de logs."
      warn "⚠  Recréer les conteneurs pour appliquer : docker compose down && docker compose up -d"
    fi
  fi
}

# ── MOTD ──────────────────────────────────────────────────────────────────────
do_motd() {
  header "Installation du MOTD dynamique"
  MOTD_DEST="/etc/profile.d/motd-dynamic.sh"
  MOTD_SRC="$(dirname "$(realpath "$0")")/motd-dynamic.sh"

  if [[ -f "$MOTD_DEST" ]]; then
    info "MOTD déjà installé dans $MOTD_DEST."
    echo -en "${BOLD}Réinstaller / mettre à jour ? [o/N] ${RESET}"
    read -r rep
    [[ "${rep:-N}" =~ ^[OoYy]$ ]] || return
  fi

  # Cherche le fichier localement, sinon télécharge
  if [[ ! -f "$MOTD_SRC" ]]; then
    info "motd-dynamic.sh non trouvé localement → téléchargement depuis GitHub..."
    TMP_MOTD=$(mktemp /tmp/motd-dynamic-XXXXXX.sh)
    DL_OK=false
    if command -v curl &>/dev/null; then
      curl -fsSL "$MOTD_URL" -o "$TMP_MOTD" && DL_OK=true || true
    fi
    if [[ "$DL_OK" == false ]] && command -v wget &>/dev/null; then
      wget -q "$MOTD_URL" -O "$TMP_MOTD" && DL_OK=true || true
    fi
    if [[ "$DL_OK" == false ]]; then
      error "Impossible de télécharger le MOTD."
      error "Vérifie ta connexion ou télécharge manuellement :"
      error "  $MOTD_URL"
      rm -f "$TMP_MOTD"
      return
    fi
    # Vérification basique : le fichier doit contenir du bash
    if ! grep -q "#!/" "$TMP_MOTD" 2>/dev/null; then
      error "Le fichier téléchargé semble invalide (repo GitHub vide ?)."
      rm -f "$TMP_MOTD"
      return
    fi
    MOTD_SRC="$TMP_MOTD"
    success "Téléchargement réussi."
  fi

  cp "$MOTD_SRC" "$MOTD_DEST"
  chmod +x "$MOTD_DEST"
  [[ "$MOTD_SRC" == /tmp/* ]] && rm -f "$MOTD_SRC"

  # Désactiver l'ancien MOTD statique
  if [[ -f /etc/motd ]] && [[ -s /etc/motd ]]; then
    mv /etc/motd /etc/motd.bak
    info "Ancien /etc/motd sauvegardé dans /etc/motd.bak"
  fi

  success "MOTD installé avec succès !"
  echo ""
  info "Tester maintenant :"
  echo "    bash $MOTD_DEST"
}

# ── Résumé final ──────────────────────────────────────────────────────────────
do_summary() {
  echo ""
  sep
  echo -e "  ${BOLD}${GREEN}✔ Terminé !${RESET}"
  echo -e "  Disque après : $(disk_usage)"
  sep
  echo ""
  echo -e "  ${BOLD}Prochaines étapes recommandées :${RESET}"
  echo "  • Recréer les conteneurs Docker :"
  echo "      docker compose down && docker compose up -d"
  echo "  • Tester le MOTD SSH :"
  echo "      bash /etc/profile.d/motd-dynamic.sh"
  echo "  • Planifier ce script mensuellement :"
  echo "      echo '0 3 1 * * root bash /usr/local/sbin/linux-cleanup.sh' \\"
  echo "        | sudo tee /etc/cron.d/linux-cleanup"
  echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
#  EXÉCUTION SELON LE MODE
# ══════════════════════════════════════════════════════════════════════════════

case "$MODE" in
  auto|manuel)
    do_docker_logs
    do_docker_prune
    do_journald
    do_varlog
    do_summary
    ;;
  motd)
    do_motd
    ;;
esac
