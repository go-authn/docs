---
title: "secretsource — un secret depuis une référence"
linkTitle: "secretsource"
weight: 35
description: "go-authn/secretsource obtient un PIN, un mot de passe ou un code de récupération depuis une référence (un fichier, le Trousseau macOS, un Secret Service, KeePassXC), pour qu'aucun fichier en clair ne reste sur le disque."
tags: [bibliothèques, secretsource, secrets]
---

**D'où vient un PIN, quand il ne doit pas rester dans un fichier ?** Une
**référence** dit où vit un secret ; `secretsource.Open` va le chercher. La
référence ne contient aucun secret : elle peut figurer dans une option, un
script ou l'historique du shell.

```sh
go get github.com/go-authn/secretsource@v0.2.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:by-path/Keys/Yubikey PIN")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| Référence | Lit |
|---|---|
| `file:PATH` | un fichier ordinaire lisible par son propriétaire seul (mode 0600 ou plus strict) ; un saut de ligne final est retiré |
| `keychain:SERVICE/ACCOUNT` | un élément de mot de passe générique du Trousseau macOS |
| `secretservice:SERVICE/ACCOUNT` | un élément Secret Service freedesktop d'attributs `service=SERVICE`, `account=ACCOUNT` (GNOME Keyring, KWallet, intégration Secret Service de KeePassXC) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | l'unique élément Secret Service portant tous ces attributs ; plusieurs correspondances sont refusées |
| `keepassxc:by-uuid/HEX` | l'entrée KeePassXC portant cet UUID (32 chiffres hexadécimaux) |
| `keepassxc:by-path/Group/Title` | l'entrée à ce chemin (le nom du groupe racine est omis) ; un titre partagé par deux groupes est refusé comme ambigu, utilisez `by-uuid/` |
| `keepassxc:URL` | l'entrée dont le champ URL correspond |

**Aucun schéma n'exécute de commande** : une option ne doit jamais pouvoir
lancer un processus. Une référence sans schéma est refusée, pas devinée comme un
chemin (`file:` est la façon d'écrire un chemin). Un secret de plus de 4096
octets, ou vide venant d'un gestionnaire, est refusé, et un appel s'achève avec
son contexte (2 minutes sans échéance) même quand le gestionnaire attend que
vous le déverrouilliez.

## KeePassXC {#keepassxc}

KeePassXC est joint par son protocole d'intégration au navigateur, sur macOS et
Linux ; Windows n'est pas encore implémenté.

1. Dans KeePassXC, activez *Settings > Browser Integration*.
2. Associez cette machine une fois par base, et approuvez dans KeePassXC :
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. Vérifiez une référence sans afficher le secret :
   ```sh
   secretsource check 'keepassxc:by-path/Yubikey PIN'
   ```

La première lecture d'une entrée affiche la boîte de dialogue d'accès de
KeePassXC.

Utilisé par `fido --pin-from` (voir [fido]({{< relref "/libraries/fido.md" >}}))
et par `theca --pin-from`, `--password-from` et `--recovery-from`.

## Référence {#reference}

Le README de
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) fait
foi pour cette page.
