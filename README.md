# 🧹 linux-cleanup

> Script Bash pour purger les logs Docker et système sur Linux, et mettre en place des limites pérennes.

Conçu pour les homelab / serveurs auto-hébergés qui accumulent silencieusement des gigaoctets de logs Docker et journald.

---

## 🎯 Problème résolu

Par défaut, Docker n'a **aucune limite** sur la taille des logs conteneurs.  
Sur un serveur qui tourne depuis quelques mois, il est courant de retrouver :

```
/var/lib/docker/containers/  → 10–15 GiB de logs JSON
/var/log/journal/            → 3–5 GiB de journald
/var/log/*.gz                → archives syslog oubliées
```

Ce script nettoie tout ça en une commande, puis configure le système pour que ça ne revienne plus.

---

## ✅ Ce que fait le script

| Étape | Action |
|-------|--------|
| **1/4** | Affiche et truncate les logs Docker (`-json.log`) sans redémarrer les conteneurs |
| **2/4** | `docker system prune` — supprime conteneurs arrêtés et images orphelines |
| **3/4** | Configure `/etc/docker/daemon.json` (max-size / max-file) + limite journald |
| **4/4** | Supprime les archives `.gz` de `/var/log` de plus de 7 jours |

---

## 🚀 Installation rapide

```bash
curl -fsSL https://raw.githubusercontent.com/Eucliwood090/linux-cleanup/main/linux-cleanup.sh \
  -o linux-cleanup.sh
chmod +x linux-cleanup.sh
sudo bash linux-cleanup.sh
```

Ou en clonant le repo :

```bash
git clone https://github.com/Eucliwood090/linux-cleanup.git
cd linux-cleanup
sudo bash linux-cleanup.sh
```

---

## 📖 Usage

```bash
# Mode interactif — confirme chaque étape (recommandé)
sudo bash linux-cleanup.sh

# Simulation — ne modifie rien, affiche ce qui serait fait
sudo bash linux-cleanup.sh --dry-run

# Mode automatique — sans prompts (pour cron)
sudo bash linux-cleanup.sh --auto
```

---

## ⚙️ Valeurs par défaut configurées

| Paramètre | Valeur |
|-----------|--------|
| Docker `max-size` | `50m` |
| Docker `max-file` | `3` (→ 150 MiB max/conteneur) |
| journald `SystemMaxUse` | `500M` |
| journald `MaxRetentionSec` | `2 semaines` |
| Archives `/var/log/*.gz` | supprimées si > 7 jours |

Ces valeurs sont modifiables en haut du script.

---

## 🔁 Automatisation mensuelle (cron)

```bash
echo '0 3 1 * * root bash /usr/local/sbin/linux-cleanup.sh --auto' \
  | sudo tee /etc/cron.d/linux-cleanup
```

---

## ⚠️ Notes importantes

- **`truncate` vs `rm`** : le script utilise `truncate -s 0` et non `rm`. Supprimer le fichier log casserait le file handle Docker ; truncate vide le fichier sans l'effacer.
- **`daemon.json` et conteneurs existants** : la config Docker ne s'applique qu'aux *nouveaux* conteneurs. Pour les conteneurs existants, les recréer après le premier run :
  ```bash
  docker compose down && docker compose up -d
  ```
- **Backup automatique** : si `daemon.json` existe déjà, une copie horodatée est créée avant modification.

---

## 🖥️ Compatibilité

| OS | Statut |
|----|--------|
| Debian 11 / 12 | ✅ |
| Ubuntu 22.04 / 24.04 | ✅ |
| Raspberry Pi OS (Bookworm) | ✅ |
| Armbian | ✅ |
| Autres systemd-based | 🟡 non testé |

---

## 📄 Licence

MIT — libre d'utilisation, de modification et de distribution.
