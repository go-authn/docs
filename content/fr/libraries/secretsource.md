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
go get github.com/go-authn/secretsource@v0.12.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| Référence | Lit |
|---|---|
| `file:PATH` | un fichier ordinaire lisible par son propriétaire seul (Unix : mode 0600 ou plus strict ; Windows, depuis la v0.7.0 : une liste d'accès qui n'accorde de droit de lecture ou d'écriture à personne d'autre que le propriétaire, SYSTEM et le groupe Administrateurs) ; un saut de ligne final est retiré ; un fichier vide, ou qui ne contient qu'une fin de ligne, est refusé avec `ErrEmpty` (depuis la v0.6.0), et un FIFO est refusé comme n'étant pas un fichier ordinaire |
| `keychain:SERVICE/ACCOUNT` | un élément de mot de passe générique du Trousseau macOS |
| `secretservice:SERVICE/ACCOUNT` | un élément Secret Service freedesktop d'attributs `service=SERVICE`, `account=ACCOUNT` (GNOME Keyring, KWallet, intégration Secret Service de KeePassXC) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | l'unique élément Secret Service portant tous ces attributs ; plusieurs correspondances sont refusées |
| `keepassxc:URL` | l'entrée KeePassXC dont le **champ URL** est cette URL (`https://NOM.invalid/...` est un bon choix, qui ne se résout jamais) ; deux entrées de même URL sont refusées comme ambiguës |
| `systemd-creds:NAME` | (Linux, depuis v0.8.0) un credential systemd, rendu octet pour octet : pas de retrait du saut de ligne final, contrairement à `file:`. D'abord le fichier `NAME` dans `$CREDENTIALS_DIRECTORY` (placé par `LoadCredential=`, `LoadCredentialEncrypted=`, `SetCredentialEncrypted=`) ; sinon `NAME` ou `NAME.cred` dans `credstore.encrypted` sous `/etc`, `/run`, `/usr/lib`, déchiffré par `systemd-creds decrypt`. Refusé avec `ErrUnavailable` sur les autres systèmes |

**`file:` ne suit pas un lien symbolique** (depuis v0.9.0). Un lien au dernier
composant du chemin, pendant ou non, est refusé : sous Unix le fichier est ouvert
avec `O_NOFOLLOW`, sous Windows avec `FILE_FLAG_OPEN_REPARSE_POINT` et tout point
d'analyse est refusé (un espace réservé de fichiers dans le nuage aussi : visez
une copie locale ordinaire). Sous Unix, le fichier doit en outre appartenir à
l'utilisateur appelant ; root n'y échappe pas. **Migration :** visez le vrai
fichier (`readlink -f PATH`). Un lien symbolique dans un répertoire situé plus
haut dans le chemin fonctionne toujours.

`keepassxc:by-uuid/...` et `keepassxc:by-path/...` sont **refusés** : KeePassXC
2.8.0 plante quand une recherche trouve une entrée sans URL.

**Aucun schéma n'exécute de commande** : une option ne doit jamais pouvoir
lancer un processus. Une référence sans schéma est refusée, pas devinée comme un
chemin (`file:` est la façon d'écrire un chemin). Un secret de plus de 4096
octets, ou vide venant d'un gestionnaire ou d'un `file:`, est refusé (`ErrEmpty`), et un appel s'achève avec
son contexte (2 minutes sans échéance) même quand le gestionnaire attend que
vous le déverrouilliez.

## Credentials systemd {#systemd-creds}

Grammaire, exactement : `systemd-creds:NAME`, le schéma en minuscules, deux-points,
puis le nom du credential tel que donné à `LoadCredential=`,
`LoadCredentialEncrypted=` ou `systemd-creds encrypt --name=`, par exemple
`systemd-creds:smtp`. `NAME` est un simple nom de fichier de 1 à 255 octets : pas
de `/` (donc pas un chemin), ni `.` ni `..`, aucun caractère de contrôle, et pas
de suffixe `.cred` (le suffixe appartient au fichier ; `smtp` trouve `smtp` ou
`smtp.cred`).

- Le fichier de `$CREDENTIALS_DIRECTORY` est ouvert avec `O_NOFOLLOW`, doit être
  un fichier régulier appartenant à root ou à l'appelant, sans accès pour « les
  autres » (les bits de groupe sont acceptés : systemd donne à un service `User=`
  un fichier 0440 de root avec une ACL) ; le répertoire de même. Un lien
  symbolique ou un mode trop ouvert est refusé.
- Sinon `systemd-creds decrypt --name=NAME PATH -` est lancé directement : sans
  shell, avec un environnement vide, le secret lu sur la sortie standard
  seulement, 4096 octets au plus, borné par le contexte. Un appelant non root
  essaie d'abord `--user` (systemd 256 ou plus).
- Aucun rognage : un saut de ligne final, des octets NUL et des octets non UTF-8
  sont conservés ; scellez donc un mot de passe avec `printf %s`.
- Mesuré sur systemd 257 (Debian 13) avec `--with-key=host` ; non mesuré avec une
  clé TPM2. Un déchiffrement qui échoue renvoie `ErrUnavailable` et indique que
  le credential doit peut-être être rescellé.
- Liaison aux PCR : `--tpm2-pcrs=` est vide par défaut. Un `--tpm2-pcrs=7` nu peut
  verrouiller tous les credentials après une mise à jour du firmware ou du shim ou
  une migration de vTPM. Préférez `--with-key=host+tpm2`, une politique de PCR
  signée (`--tpm2-public-key`, PCR 11) ou `systemd-pcrlock`, et gardez une copie
  du secret pour le resceller.

## KeePassXC {#keepassxc}

KeePassXC est joint par son protocole d'intégration au navigateur, sur macOS et
Linux ; Windows n'est pas encore implémenté. Depuis la v0.6.0, sous Unix, le socket est
refusé quand c'est un lien symbolique ou quand son répertoire appartient à un autre
utilisateur ou est inscriptible par le groupe ou les autres, et l'uid du pair connecté
est vérifié après la connexion ; le lien symbolique historique
`$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer` n'est plus suivi (le vrai
socket sous `app/org.keepassxc.KeePassXC/` l'est).

Depuis la v0.6.1, le fichier d'association (le magasin de repli, utilisé quand ni le
trousseau macOS ni un Secret Service n'est là) est écrit dans un nouveau fichier
temporaire du même répertoire puis renommé sur le nom final, de sorte qu'un lien
symbolique laissé à ce nom est remplacé, pas suivi, et qu'un fichier de mode plus large
ressort en 0600. Sous Unix, le répertoire est vérifié d'abord, comme celui du socket :
appartenant à cet utilisateur, non inscriptible par le groupe ou les autres, pas un lien
symbolique ; sinon rien n'est écrit.

Depuis la v0.8.1, cette écriture est faite par
[`harden/privfile`]({{< relref "/libraries/harden.md#privfile" >}}) v0.2.0. Sous
Windows, le fichier reçoit désormais une liste d'accès protégée réservée au
propriétaire, comme dans go-authn/kinit v0.3.2, et le répertoire est vérifié de nouveau
à l'écriture, en plus d'avant.

1. Dans KeePassXC, activez *Settings > Browser Integration*.
2. Associez cette machine une fois par base, et approuvez dans KeePassXC :
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. Créez l'entrée et **renseignez son champ URL** avec
   `https://fido.invalid/yubikey-5c` (toute URL qu'aucune autre entrée
   n'utilise : la référence est cette URL). Vérifiez la référence sans afficher
   le secret :
   ```sh
   secretsource check 'keepassxc:https://fido.invalid/yubikey-5c'
   ```

La première lecture d'une entrée affiche la boîte de dialogue d'accès de
KeePassXC.

Utilisé par `fido --pin-from` (voir [fido]({{< relref "/libraries/fido.md" >}}))
et par `theca --pin-from`, `--password-from` et `--recovery-from`.

## Prendre un secret depuis un drapeau de ligne de commande : `secretsource/secretflag` {#secretflag}

Un secret passé comme valeur de drapeau est visible dans `ps`. Le paquet
`secretflag` donne à une commande la paire `--<nom>` (obsolète, avertit sur
stderr) et `--<nom>-from <réf>`, mutuellement exclusifs, la référence étant
résolue par `secretsource.Open` :

```go
var password string
b := secretflag.Add(cmd, "password", &password, "the admin password") // cobra
// or: secretflag.AddStd(fs, os.Stderr, "password", &password, "the admin password", "p")
// ... after parsing:
if err := secretflag.Resolve(ctx, b); err != nil { return err }
```

`Add` enregistre la paire sur une commande cobra, `AddStd` sur un
`flag.FlagSet` de la bibliothèque standard (avec des alias comme `-t`) ;
`Resolve` lit les références. Disponible depuis la v0.10.0.

`AddFrom` n'enregistre que `--<nom>-from`, sans jumeau simple obsolète, pour un
secret introduit après l'obsolescence du drapeau simple. `AddFromList`
enregistre un `--<nom>-from` répétable ; `Resolve` ajoute chaque secret résolu à
un `*[]string`, dans l'ordre (rotation de clés). Les deux suppriment les blancs
de bord, refusent un secret vide et gardent la valeur hors des erreurs, comme
`Add`. Disponible depuis la v0.12.0.

## Stocker un secret : `secretsource store` {#store}

Aucune entrée n'a à être créée à la main. `secretsource store REF [--group G]
[--login L] [--replace] [--generate N]` écrit le secret pour `keychain:`,
`secretservice:SERVICE/ACCOUNT`, `secretservice:KEY=VALUE` et `keepassxc:URL` :

```sh
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c'
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c' --generate 24
printf '%s' "$PIN" | secretsource store keychain:fido/yubikey-5c
```

Le secret est saisi deux fois sans écho, ou lu sur l'entrée standard quand ce
n'est pas un terminal ; il n'est jamais pris dans un argument ni dans
l'environnement. `--generate N` tire N lettres et chiffres et n'affiche rien de
secret. Une entrée existante est refusée sauf avec `--replace` (pour KeePassXC,
cela met à jour cette entrée, retrouvée par son URL). `file:` est refusé.

Pour `keepassxc:`, il utilise le `set-login` du protocole navigateur : l'entrée
porte toujours l'URL qui permet de la retrouver, et un doublon se cherche par
URL. L'identifiant par défaut est l'hôte de l'URL (`--login`), le groupe est
`KeePassXC-Browser Passwords` sauf si `--group` en nomme un sous la racine, et
`--title` est refusé car KeePassXC 2.8.0 l'ignore. KeePassXC affiche ses
propres boîtes de dialogue.

## Supprimer un secret : `Delete` {#delete}

`Delete(ctx, ref)` est le pendant de `Store` : un appelant qui garde un jeton
dans le trousseau peut le retirer à la déconnexion. Disponible depuis la v0.11.0.

- `keychain:` et `secretservice:SERVICE/ACCOUNT` suppriment l'élément. Quand une
  recherche Secret Service correspond à plusieurs éléments, le résultat est
  `ErrAmbiguous` et rien n'est supprimé.
- `keepassxc:URL` utilise le `delete-entry` du protocole navigateur : KeePassXC
  demande confirmation et déplace l'entrée dans sa Corbeille, de sorte que le
  mot de passe reste dans la base jusqu'à ce que la corbeille soit vidée.
- Une entrée absente donne une erreur qui est à la fois `ErrNotFound` et
  `fs.ErrNotExist`, si bien que « déjà disparue » peut être traité comme un
  succès, volontairement.
- `file:`, `systemd-creds:` et `secretservice:KEY=VALUE` sont refusés avec
  `ErrNoDelete` : ce paquet ne gère jamais un fichier ni un credential qu'il n'a
  pas stocké, et une recherche par attribut ne désigne aucun élément unique.

L'entrée est recherchée avant d'être supprimée. Rien de secret n'est renvoyé ni
journalisé.

## Référence {#reference}

Le README de
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) fait
foi pour cette page.
