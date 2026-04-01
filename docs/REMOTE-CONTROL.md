# Alba Remote — Raccourcis iPhone & MacBook

## 📱 iPhone — Créer un raccourci Shortcuts

### Raccourci "Alba Status"
1. Ouvre **Shortcuts** (Raccourcis)
2. **+** → New Shortcut
3. Ajoute l'action **"Run Script Over SSH"**
   - Host: `mac-mini-de-alba` (ou `100.106.217.64`)
   - Port: 22
   - User: `alba`
   - Authentication: SSH Key (importe ta clé) ou Password
   - Script:
   ```
   export PATH=/opt/homebrew/bin:/Users/alba/.nvm/versions/node/v22.22.2/bin:/usr/local/bin:/usr/bin:/bin
   bash ~/bin/start-alba.sh status
   ```
4. Ajoute **"Show Result"** après
5. Nomme-le **"Alba Status"** avec 🟢 comme icône

### Raccourci "Alba Restart"
Même chose, avec ce script :
```
export PATH=/opt/homebrew/bin:/Users/alba/.nvm/versions/node/v22.22.2/bin:/usr/local/bin:/usr/bin:/bin
bash ~/bin/start-alba.sh stop
sleep 2
/opt/homebrew/bin/tmux new-session -d -s alba-launcher 'bash ~/bin/start-alba.sh start'
sleep 10
bash ~/bin/start-alba.sh status
```

### Raccourci "Alba Health"
```
export PATH=/opt/homebrew/bin:/Users/alba/.nvm/versions/node/v22.22.2/bin:/usr/local/bin:/usr/bin:/bin
bash ~/AZW/alba-blueprint/skills/health-check/scripts/health-check.sh
```

⚡ **Astuce** : mets les 3 raccourcis dans un dossier "Alba" et ajoute-les au widget Home Screen.

⚠️ **Prérequis** : Tailscale doit tourner sur l'iPhone ET le Mac Mini.

---

## 💻 MacBook — Commandes Terminal

Depuis ton MacBook (connecté en Tailscale) :

```bash
# Copie alba-remote sur ton MacBook
scp alba@mac-mini-de-alba:~/bin/alba-remote ~/bin/alba
chmod +x ~/bin/alba

# Puis utilise :
alba status    # ou: alba s
alba restart   # ou: alba r
alba stop
alba start
alba logs      # ou: alba l
alba health    # ou: alba h
alba check     # ou: alba c
```

Ou sans installer, one-liner :
```bash
ssh alba@mac-mini-de-alba "PATH=/opt/homebrew/bin:/Users/alba/.nvm/versions/node/v22.22.2/bin:\$PATH bash ~/bin/start-alba.sh status"
```
