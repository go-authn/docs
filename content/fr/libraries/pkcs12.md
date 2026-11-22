---
title: "pkcs12 — la clé et les certificats d'un fichier .p12 téléversé"
linkTitle: "pkcs12"
weight: 116
description: "go-authn/pkcs12 lit les fichiers PKCS#12 (.p12 / .pfx, RFC 7292) en Go pur, conçu pour les fichiers non fiables : chaque borne de ressources est une option qu'on ne peut pas désactiver, et OpenSSL fait foi."
tags: [bibliothèques, certificats, clés]
---

**Quelle clé privée et quels certificats contient ce fichier qu'on nous a envoyé ?**
PKCS#12 ([RFC 7292](https://www.rfc-editor.org/rfc/rfc7292)) est le conteneur
`.p12` / `.pfx` dans lequel un exporteur écrit une clé, son certificat et le
reste de la chaîne. `golang.org/x/crypto/pkcs12` est obsolète et figé sur
SHA-1 et 3DES/RC2 : il rejette ce qu'OpenSSL 3 et 4 et Windows écrivent
aujourd'hui par défaut (PBES2, AES, MAC SHA-2). Ce module les lit, sans autre
dépendance que la bibliothèque standard, et il est conçu pour les **fichiers
téléversés non fiables**.

```sh
go get github.com/go-authn/pkcs12@v0.1.0
```

Il **décode seulement** : il n'y a pas d'encodeur. Décider s'il faut faire
confiance à la chaîne, c'est le `Verify` de `crypto/x509`, une décision à part.

## Exemple {#example}

```go
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/pkcs12"
)

func main() {
	data, err := os.ReadFile("upload.p12")
	if err != nil {
		panic(err)
	}

	b, err := pkcs12.Decode(data, "the password", nil)
	switch {
	case errors.Is(err, pkcs12.ErrIncorrectPassword):
		fmt.Println("ask again:", err)
		return
	case err != nil: // hostile, unsupported, too costly...
		fmt.Println("refused:", err)
		return
	}

	// b.PrivateKey   *rsa.PrivateKey, *ecdsa.PrivateKey, ed25519.PrivateKey or *ecdh.PrivateKey
	// b.Certificate  the certificate holding the key's public half
	// b.CACerts      every other certificate, in file order
	fmt.Println("certificate for", b.Certificate.Subject, "and", len(b.CACerts), "more")
}
```

`Decode(data, password, *Options) (*Bundle, error)` accepte `nil` pour les
valeurs par défaut. Le `Bundle` contient la clé, le certificat dont elle est la
moitié privée, et les autres dans l'ordre du fichier.

## Options et valeurs par défaut {#options-and-their-defaults}

Un champ à zéro prend la valeur par défaut, et **aucun champ ne peut désactiver
une borne**.

| champ | défaut | signification |
|---|---|---|
| `MaxInputSize` | 8 MiB | `len(data)` |
| `MaxIterations` | 1 000 000 | itérations d'une dérivation de clé |
| `MaxWork` | 5 000 000 | itérations x blocs de sortie sur tout le fichier |
| `MaxDepth` | 16 | imbrication BER et imbrication des fragments de chaîne construite |
| `MaxBags` | 1024 | SafeBags du fichier |
| `MaxAuthSafes` | 32 | ContentInfos de l'AuthenticatedSafe |
| `MaxCertSize` | 32 KiB | DER d'un certificat |
| `MaxCertBytes` | 512 KiB | DER de tous les certificats ensemble |
| `MaxRSABits` | 8192 | module RSA |
| `AllowNoMAC` | `false` | lire un fichier sans MAC d'intégrité (`openssl pkcs12 -nomac`) ; sinon c'est `ErrNoMAC` |
| `NoPassword` | `false` | le fichier a été exporté sans aucun mot de passe, à la différence du mot de passe vide `""` |

Les deux booléens sont les deux ambiguïtés du format. Avec `AllowNoMAC`, rien
n'authentifie le contenu, et un mauvais mot de passe n'est détecté que par un
déchiffrement qui échoue. Le mot de passe **vide** (`""`) et le mot de passe
**absent** (`NoPassword`) dérivent des clés différentes et fonctionnent tous
deux : avec `""` et `NoPassword` à false, `Decode` essaie le vide puis l'absent,
car les exporteurs ne s'accordent pas sur ce qu'ils ont écrit ; avec
`NoPassword` à true, seul l'absent est essayé, et l'argument de mot de passe
doit être `""`.

## Ce qu'il lit {#what-it-reads}

| couche | pris en charge |
|---|---|
| chiffrement | PBES2 ([RFC 8018](https://www.rfc-editor.org/rfc/rfc8018)) avec PBKDF2 sur HMAC-SHA-1/224/256/384/512 et AES-128/192/256-CBC |
| chiffrement ancien | `pbeWithSHAAnd3-KeyTripleDES-CBC`, `pbeWithSHAAnd2-KeyTripleDES-CBC`, `pbeWithSHAAnd40BitRC2-CBC` et la variante 128 bits ; RC2 est implémenté dans le module |
| intégrité | MAC HMAC avec SHA-1/224/256/384/512 (KDF de l'annexe B de la RFC 7292), et **PBMAC1** ([RFC 9579](https://www.rfc-editor.org/rfc/rfc9579)) |
| mots de passe | BMPString selon l'annexe B.1, caractères hors BMP en paires de substitution |
| encodage | BER, y compris les longueurs indéfinies et les OCTET STRING construits, qu'écrivent Windows et Java |
| sacs | sacs de clés chiffrés et en clair, sacs de certificats ; les sacs de CRL, de secrets et de contenus sûrs sont ignorés |

**Refusés en `ErrUnsupported` :** les modes à clé publique d'intégrité et de
confidentialité (`signedData`, `envelopedData`), RC4, scrypt, PBES1 autre que
ceux de PKCS#12, SHA-1 dans PBMAC1, et le BER (plutôt que le DER) dans un
certificat ou une clé PKCS#8.

## Erreurs {#errors}

| erreur | signifie |
|---|---|
| `ErrMalformed` | pas un fichier PKCS#12 que ce paquet sait lire |
| `ErrUnsupported` | lisible, mais utilisant quelque chose d'absent ici |
| `ErrLimit` | une borne de `Options` serait dépassée ; refusé avant le travail |
| `ErrIncorrectPassword` | un mauvais mot de passe et un fichier altéré, la même réponse par conception |
| `ErrNoMAC` | pas de MAC, et `AllowNoMAC` n'est pas positionné |
| `ErrNoPrivateKey` | aucune clé privée dans le fichier |
| `ErrMultipleKeys` | plus d'une clé privée dans le fichier |
| `ErrNoCertificate` | aucun certificat ne correspond à la clé privée |
| `ErrPassword` | un mot de passe inutilisable |

Tout refus enveloppe exactement l'une d'elles, et la cible de fuzzing le tient
pour un invariant.

## Les bornes de sécurité {#the-security-bounds}

Chaque borne ci-dessus est vérifiée **avant le travail**, et chaque champ de
longueur est comparé aux octets réellement présents avant toute allocation. Les
sels de plus de 512 octets et les mots de passe de plus de 1024 caractères sont
refusés.

Le MAC est vérifié, **en temps constant, avant tout déchiffrement**.

`crypto/x509` alloue jusqu'à 43 à 52 fois la taille d'un certificat quand il est
fait de milliers de noms minuscules, et `crypto/rsa` valide une clé par de
l'arithmétique sur les nombres qu'elle déclare, si bien que des facteurs bien
plus longs que le module coûtent du CPU surlinéaire. Ni l'un ni l'autre ne se
corrige de l'extérieur ; ce qui les atteint est donc borné d'abord : les
certificats par `MaxCertSize` et `MaxCertBytes`, et toute clé PKCS#8 (32 KiB au
plus) est lue avec `encoding/asn1` et refusée, typée, quand son module dépasse
`MaxRSABits`, qu'un facteur ou un exposant est plus long que le module ne le
permet, qu'un nombre n'est pas positif, ou qu'elle est multi-premiers
(`ErrUnsupported`).

**Mémoire par requête.** Avec les options par défaut, un fichier hostile fait
allouer à un `Decode` environ 25 Mo (mesuré conjointement : pires certificats
et plus grande clé acceptée, 8192 bits, 25,1 Mo, dont environ 20 Mo restent
vivants jusqu'au retour) pour un fichier de 530 Ko. Un service qui décode des
fichiers téléversés doit plafonner les décodages en cours, par exemple avec un
sémaphore, et abaisser `MaxCertBytes` s'il n'attend que de courtes chaînes.

## Limites {#limitations}

- **Les clés RSA sans valeurs CRT sont refusées** (`ErrUnsupported`). Une clé
  sans `Dp`, `Dq` et `Qinv` est refusée avant que `crypto/x509` la voie. La
  RFC 8017 les exige et tous les exporteurs les écrivent (OpenSSL, Windows,
  keytool de Java), mais `crypto/x509` dérive les manquantes par de
  l'arithmétique sur grands entiers : 16,4 Mo et 21 744 allocations à 8192
  bits, contre 0,36 Mo et 618 avec elles.
- **[go-authn/pkcs12#2](https://github.com/go-authn/pkcs12/issues/2), ouverte,
  LOW.** Sous `GODEBUG=x509rsacrt=0`, `crypto/x509` écarte les valeurs CRT
  invalides et les recalcule, et le contrôle préalable vérifie seulement
  qu'elles sont *présentes* : une clé de 8192 bits aux valeurs CRT fausses le
  franchit, et avec les pires certificats le décodage atteint 39,4 Mo (rapport
  74,7), hors de la borne que les tests affirment. Cela suppose que
  l'opérateur l'active, et le `go.mod` du module déclare une version de Go pour
  laquelle ce réglage n'est pas le défaut ; avec les réglages par défaut, la
  même entrée est refusée en `ErrMalformed`.
- Il décode seulement, et ne juge pas la chaîne.

## Contre quoi il est vérifié {#what-it-is-checked-against}

**OpenSSL fait foi.** 23 fichiers écrits par OpenSSL 4.1 (AES/PBES2, 3DES et
RC2 en `-legacy`, `-nomac`, plusieurs certificats, RSA, EC et Ed25519, PBMAC1)
sont dans les tests, avec un manifeste de ce qu'OpenSSL dit lui-même que
chacun contient.

**Amplification.** `TestAmplification` borne les octets alloués rapportés aux
octets d'entrée sur de nombreux minuscules sacs, de nombreux certificats, une
imbrication indéfinie profonde, de longues chaînes d'OCTET STRING et des
longueurs annoncées de 4 GiB, et affirme que les refus ont lieu avant l'appel à
`crypto/x509`. Le module est aussi fuzzé (corpus versionné), couvre 100 % des
blocs et passe avec `-race` et `govulncheck`.

**`software.sslmate.com/src/go-pkcs12`**, dans un module `oracle/` séparé :
sur les 23 fichiers que les deux peuvent tenter, les deux en lisent 18 avec
feuille, ordre de chaîne et clé identiques à l'octet près. Seul ce paquet lit
les 5 autres (RC2-128, un MAC SHA-384, pas de MAC, et deux mots de passe aux
caractères hors BMP) ; il n'y en a aucun que l'autre lit et que celui-ci
refuse.

Il se marie avec [cms]({{< relref "/libraries/cms.md" >}}) : décoder un `.p12`
ici, signer là.
