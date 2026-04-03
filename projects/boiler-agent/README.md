# Agent IA Dépannage Chaudières Biomasse

## Vision
Application mobile-first pour techniciens chauffagistes sur le terrain.
Photo du code panne → diagnostic guidé → solution étape par étape → pièces détachées.

## MVP Features
1. **Lecture photo code panne** — OCR sur écran chaudière
2. **Diagnostic guidé** — arbre de décision oui/non
3. **Base codes erreur** — tous fabricants biomasse
4. **Mode offline** — chaufferies sans réseau
5. **Rapport intervention** — PDF auto-généré

## Structure
```
data/
  herz-firematic-fault-codes.json    # Codes erreur HERZ complets
  herz-firematic-parts.json          # Pièces détachées avec références
  herz-firematic-specs.json          # Spécifications techniques
  diagnostic-trees.json              # Arbres de diagnostic par symptôme
  field-toolkit.json                 # Outils et procédures terrain
```

## Marques cibles (phase 1)
- HERZ (Firematic, Pelletstar, Firestar)
- Fröling (Lambdatronic)
- ÖkoFEN (Pellematic)
- Hargassner
- ETA

## Stack envisagé
- Frontend: React Native (iOS + Android)
- OCR: Vision API (Claude/GPT-4V)
- Backend: Supabase
- Offline: SQLite embarqué
