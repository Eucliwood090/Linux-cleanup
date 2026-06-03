# linux-cleanup

Script Bash de maintenance pour serveurs Linux : purge les logs Docker et système, applique des limites permanentes, et installe un tableau de bord à chaque connexion SSH.

Conçu pour les homelab et serveurs auto-hébergés qui accumulent silencieusement des gigaoctets de logs.

---

## Le problème

Par défaut, Docker n'a **aucune limite** sur la taille des logs conteneurs.  
Sur un serveur qui tourne depuis quelques mois :

```
/var/lib/docker/containers/  →  10–15 GiB de logs JSON
/var/log/journal/            →  3–5 GiB de journald
/var/log/*.gz                →  archives syslog oubliées
```

---

## Installation rapide

```bash
curl -fsSL https://raw.githubusercontent.com/Eucliwood090/Linux-cleanup/main/linux-cleanup.sh \
  -o linux-cleanup.sh
chmod +x linux-cleanup.sh
sudo bash linux-cleanup.sh
```

---

## Menu au démarrage

```
  LINUX CLEANUP

  Disque actuel : 17G utilisés / 74G total (25% plein)

  Que souhaitez-vous faire ?

  1) Mode automatique   — Nettoie tout sans poser de questions
  2) Mode manuel        — Confirme chaque étape
  3) Installer le MOTD  — Tableau de bord à chaque connexion SSH
  q) Quitter
```

---

## Ce que fait le script

### Modes 1 et 2 — Nettoyage (4 étapes)

| Étape | Action |
|-------|--------|
| **1/4** | Vide les logs Docker (`truncate`) sans redémarrer les conteneurs |
| **2/4** | `docker system prune` — supprime conteneurs arrêtés et images orphelines |
| **3/4** | Purge journald + applique des limites permanentes via `journald.conf.d` |
| **4/4** | Supprime les archives `.gz` de `/var/log` de plus de 7 jours + configure `daemon.json` |

**Mode 1 (auto)** : toutes les étapes s'enchaînent sans confirmation.  
**Mode 2 (manuel)** : chaque étape demande une confirmation `[O/n]`.

### Mode 3 — MOTD dynamique

Installe `/etc/profile.d/motd-dynamic.sh`, affiché à chaque connexion SSH :

```
  Domoticz  |  Ubuntu 24.04 LTS  |  7.0.0-3-pve  |  1 day, 1 hour

  DISQUE  17G/74G   25%  ███████░░░░░░░░░░░░░░░░░░
    logs docker: 240M  |  journal: 3.2 GiB
  RAM     1.4Go/4.9Go  28%  ████████░░░░░░░░░░░░░░░░░
  CPU     load: 0.44 0.46 0.51  (4 coeurs)  11%  ███░░░░░░░░░░░░░░░░░░░░░░
    temp: 48C

  DOCKER  7 actif(s)
    homeassistant   38 minutes
    domoticz        39 minutes
    ...

  Nominal - aucune alerte
```

Barres de progression colorées : 🟢 normal → 🟡 attention → 🔴 critique

---

## Limites appliquées

| Paramètre | Valeur par défaut |
|-----------|-------------------|
| Docker `max-size` par fichier | `50m` |
| Docker `max-file` (rotation) | `3` → 150 MiB max / conteneur |
| journald `SystemMaxUse` | `500M` |
| journald `MaxRetentionSec` | `2 semaines` |
| Archives `/var/log/*.gz` | supprimées si > 7 jours |

Modifiables en tête du script.

---

## Notes importantes

**`truncate` vs `rm`**  
Le script utilise `truncate -s 0` et non `rm`. Supprimer le fichier log casserait le file handle Docker. Truncate vide le fichier sans l'effacer, les conteneurs continuent de tourner.

**`daemon.json` et conteneurs existants**  
La config Docker ne s'applique qu'aux nouveaux conteneurs. Après le premier run :
```bash
docker compose down && docker compose up -d
```

**Backup automatique**  
Si `daemon.json` existe déjà, une copie horodatée est créée avant modification.

---

## Automatisation mensuelle

```bash
echo '0 3 1 * * root bash /usr/local/sbin/linux-cleanup.sh' \
  | sudo tee /etc/cron.d/linux-cleanup
```

---

## Compatibilité

| OS | Statut |
|----|--------|
| Debian 11 / 12 | ✅ |
| Ubuntu 22.04 / 24.04 | ✅ |
| Raspberry Pi OS (Bookworm) | ✅ |
| Armbian | ✅ |
| Proxmox VE | ✅ |
| Autres systemd-based | 🟡 non testé |

---

## Licence

MIT
