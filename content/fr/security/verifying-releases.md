---
title: "Vérifier un téléchargement"
linkTitle: "Vérifier un téléchargement"
weight: 10
description: "Ce que publie chaque version, et les trois vérifications qui distinguent un binaire compilé par le workflow de publication de tout le reste."
tags: [sécurité, versions]
---

Chaque version d'authnd, authn-bridge, authn-revokd et sshcert publie six
binaires statiques (`CGO_ENABLED=0` : linux, darwin et windows, sur amd64 et
arm64), un fichier `SHA256SUMS`, et une attestation de provenance de compilation pour chaque
binaire. Les exemples ci-dessous utilisent authn-bridge v0.22.0 ; les autres programmes fonctionnent de la même
façon avec leur propre dépôt et leur propre nom.

```sh
gh release download v0.22.0 --repo go-authn/bridge
```

## 1. La somme de contrôle {#1-the-checksum}

```sh
sha256sum -c SHA256SUMS --ignore-missing      # macOS: shasum -a 256 -c SHA256SUMS
```

```
authn-bridge-darwin-amd64: OK
authn-bridge-darwin-arm64: OK
authn-bridge-linux-amd64: OK
authn-bridge-linux-arm64: OK
authn-bridge-windows-amd64.exe: OK
authn-bridge-windows-arm64.exe: OK
```

Cela prouve que le fichier est celui que liste la version, et rien de plus : quiconque
pourrait remplacer un binaire sur la page de la version pourrait remplacer `SHA256SUMS` à côté de
lui.

## 2. La provenance {#2-the-provenance}

```sh
gh attestation verify authn-bridge-linux-amd64 --repo go-authn/bridge
echo $?
```

L'attestation est signée par GitHub pour l'exécution du workflow qui a compilé le fichier,
elle nomme donc le dépôt et le workflow, pas une clé que quelqu'un détient.

{{< callout type="warning" >}}
**Lisez le code de sortie, pas la sortie.** Sans terminal, certaines versions de
`gh` n'affichent rien du tout quand la vérification réussit : mesuré avec gh
2.65.0 sur authnd, un binaire authentique a donné le code de sortie 0 et une sortie vide. Un binaire auquel
on a ajouté un octet a donné le code de sortie 1 et
`Error: failed to fetch attestations from go-authn/authnd: HTTP 404: Not Found`,
parce qu'aucune attestation n'existe pour son condensé. Le silence n'est pas l'échec ; un
code non nul l'est.
{{< /callout >}}

## 3. Ce que le binaire dit de lui-même {#3-what-the-binary-says-about-itself}

```sh
go version -m authn-bridge-linux-amd64
```

```
	path	github.com/go-authn/bridge/cmd/authn-bridge
	mod	github.com/go-authn/bridge	v0.22.0	
	build	-trimpath=true
	build	CGO_ENABLED=0
	build	vcs.revision=e1c4fdc3ae1cdddf2ccb4e64bda4317b5bf4f3a8
	build	vcs.modified=false
```

(lignes réduites à celles qui comptent). La ligne `mod` doit être exactement l'étiquette,
et `vcs.modified` doit valoir `false` : une compilation depuis un arbre avec des
changements non commités indique `true`, et sa version se lit `v0.22.0+dirty`. Le
workflow de publication refuse de publier à moins que **chacun** des six binaires
ne passe les deux vérifications, et à moins que le programme n'affiche l'étiquette comme dernier mot de
sa ligne de version :

```
$ authnd --version
authnd version v0.10.1
$ authn-bridge --version
authn-bridge version v0.22.0
$ authn-revokd -version
authn-revokd v0.6.3
```

authnd et authn-bridge prennent `--version` ; authn-revokd prend `-version`, la
syntaxe de drapeaux standard de Go. Depuis la v0.6.1, il écrit sur la sortie standard, comme les deux
autres, de sorte que `v=$(authn-revokd -version)` capture la version.

## Quelles versions ont des binaires {#which-releases-have-binaries}

Les binaires, sommes et attestations sont publiés à partir d'authnd v0.9.2, authn-bridge
v0.19.3, authn-revokd v0.5.0 et sshcert v0.1.2. La première version de chacun
compilait ses binaires dans l'extraction et annonçait `+dirty` ; cela a été corrigé dans
la suivante, et la vérification par binaire est venue après. Les étiquettes antérieures sont
uniquement des sources : compilez-les avec `go install …@<tag>`, qui enregistre l'étiquette
dans les informations de compilation que lit `go version -m`. Ce qu'affiche le programme
n'est pas toujours cela : sshcert-authorize affichait `dev` pour une compilation `go install` jusqu'à
v0.1.5, et revokd n'a pas de `-version` avant v0.5.0.
