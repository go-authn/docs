---
title: "krb5 — accepter un ticket Kerberos"
linkTitle: "krb5"
weight: 70
description: "go-authn/krb5 est la moitié de Kerberos qui accepte : un keytab, un AP-REQ vérifié, l'AP-REP dont l'authentification mutuelle a besoin, et des messages signés et scellés sous la clé de session."
tags: [bibliothèques, kerberos]
---

**Ce ticket Kerberos est-il bon pour ce service ?** La moitié **accepteur** de
Kerberos, et seulement cette moitié : il détient un keytab, vérifie l'AP-REQ qu'un client
présente, répond par l'AP-REP qui prouve que le service est authentique, puis
signe, vérifie, scelle et ouvre des messages sous la clé que cet échange
a établie.

```sh
go get github.com/go-authn/krb5@v0.3.3
```

La v0.3.3 ne change ni l'API ni le code : elle relève les dépendances indirectes
golang.org/x/net à v0.62.0, golang.org/x/crypto à v0.58.0 et
github.com/hashicorp/go-uuid à v1.0.4. `govulncheck` listait 46 résultats dans des
modules requis et non appelés ; il en liste 1 maintenant, GO-2026-5932
(`golang.org/x/crypto/openpgp`), qui n'a pas de version corrigée et que rien dans
go-authn n'importe. Les résultats atteignables depuis le code étaient 0 avant et
sont 0 après.

Il ne parle jamais à un KDC et ne délivre jamais de ticket, donc de qui il accepte les tickets
est la décision de quelqu'un d'autre. La moitié qui délivre est
[kdc]({{< relref "/libraries/kdc.md" >}}), et ce module n'en dépend
pas — voir [pourquoi ce sont des modules distincts]({{< relref "/libraries/_index.md#why-they-are-separate-modules" >}}).
Le déchiffrement des tickets est celui de [gokrb5](https://github.com/jcmturner/gokrb5).

## Pourquoi il existe {#why-it-exists}

gokrb5 est une bibliothèque cliente. Elle vérifie un AP-REQ et ne sait pas construire l'AP-REP
qui y répond. Tout client GSS-API demande l'authentification mutuelle — le propre
`gss-client` du MIT positionne `GSS_C_MUTUAL_FLAG` sans moyen de le désactiver — donc un
service qui ne sait pas produire d'AP-REP n'établit aucun contexte. Le construire
est l'essentiel de ce que ce module ajoute.

## Exemple {#example}

```go
package main

import (
	"errors"
	"fmt"
	"log"

	"github.com/go-authn/krb5"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

// establish is one GSS-API exchange: the client's AP-REQ in, the AP-REP out.
func establish(a *krb5.Acceptor, token []byte) (*krb5.Context, []byte, error) {
	ctx, apRep, err := a.Accept(token)
	if err != nil {
		return nil, nil, err // no context: refuse, never fall back to something weaker
	}
	// The client will not consider the context open until it has verified
	// apRep, so sending it back is not optional.
	log.Printf("%s (user %q, realm %q) until %s", ctx.Principal(), ctx.User(), ctx.Realm(), ctx.Expires())
	return ctx, apRep, nil
}

func main() {
	// In a service: krb5.Load("/etc/krb5.keytab", krb5.Principal("nfs/files.example.org")).
	// Here, an empty keytab, so the refusals can be seen.
	a := krb5.New(keytab.New(), krb5.Principal("nfs/files.example.org"))

	_, _, err := establish(a, []byte("not a token"))
	fmt.Println(errors.Is(err, krb5.ErrNotAToken), err)

	_, err = krb5.Load("/nonexistent/krb5.keytab")
	fmt.Println(errors.Is(err, krb5.ErrNoKeytab), err)
}
```

```
true krb5: not a GSS-API krb5 token: asn1: structure error: explicitly tagged member didn't match
true krb5: keytab "/nonexistent/krb5.keytab": open /nonexistent/krb5.keytab: no such file or directory
```

Il a besoin de `github.com/jcmturner/gokrb5/v8` pour `keytab.New`, que `krb5.New`
prend ; `krb5.Load` lit plutôt un keytab depuis un chemin.

Après `Accept`, un `*Context` dit qui : `Principal()` (`alice@EXAMPLE.ORG`), ou
`User()` et `Realm()` séparément. Faire correspondre un principal à un compte local est la
politique de l'appelant : `alice@EXAMPLE.ORG` et `alice@PARTNER.ORG` répondent tous deux à
« alice ». `Expires()` est le moment où le ticket qui le sous-tend se termine, au-delà duquel un serveur
qui maintient une connexion de longue durée devrait cesser de l'honorer. `MIC`/`VerifyMIC`
et `Wrap`/`Unwrap` signent ; `Seal`/`Unseal` ajoutent la confidentialité (`sec=krb5p`).
Un `Context` n'est pas sûr en usage concurrent ; un `Acceptor` l'est.

## Ce qu'il refuse, et pourquoi {#what-it-refuses-and-why}

**Un ticket que ce service n'acceptera pas** — mauvais service, mauvaise clé,
expiré, rejoué, une horloge au-delà de `ClockSkew` (cinq minutes par défaut, comme chez le MIT)
— est `ErrRejected`. Des octets qui ne sont pas un jeton GSS-API krb5 sont
`ErrNotAToken`, et un jeton qui n'est pas un AP-REQ est `ErrNotAPReq`. Les erreurs
sont délibérément grossières : un client apprend que son ticket a été refusé, jamais
quelle vérification l'a refusé. Une erreur signifie aucun contexte, et le jeton renvoyé est
vide.

**Un principal pour lequel l'accepteur ne répond pas.** Avec
`krb5.Principal("nfs/files.example.org")`, un keytab qui détient plusieurs services
ne répond que pour celui-là.

**Un message dont la signature ne correspond pas** est `ErrBadMIC`, quel que soit, de la
longueur, de l'en-tête, de la séquence ou de la somme de contrôle, l'élément en désaccord. L'accepteur signe
avec l'usage de clé 23 et vérifie avec 25, donc un jeton que ce serveur a produit ne peut pas
lui être rejoué comme si le client l'avait signé.

**Un jeton scellé remis à `Unwrap`** est `ErrSealed`, distinct d'une mauvaise
signature : un appelant qui lit un jeton à intégrité seule ne doit pas recevoir
un chiffré qui se lit comme un message. **Un jeton non scellé remis à `Unseal`**
est `ErrNotSealed` : un protocole qui a promis la confidentialité ne reçoit pas
quelque chose qui a traversé le réseau en clair.

Il n'impose aucune sous-clé d'accepteur : la clé du contexte est la sous-clé que l'initiateur a mise
dans son authentificateur, ou la clé de session du ticket quand il n'en a envoyé aucune
(RFC 4121 §4.3).

{{< callout type="warning" >}}
**Un keytab est un secret au repos**

Son chemin peut venir d'un fichier de configuration ou de `KRB5_KTNAME` ; la clé
qu'il contient ne doit jamais être journalisée, affichée, ni transportée dans une variable
d'environnement.
{{< /callout >}}

## Ce contre quoi il est vérifié {#what-it-is-checked-against}

**Un vrai KDC du MIT et le propre `gss-client` du MIT**, contre ce paquet qui tient
le rôle de `gss-server`. `test/kdc.sh` construit un royaume jetable sur l'interface de bouclage,
sans privilèges ; la CI obtient MIT Kerberos via pkgx (les paquets d'Ubuntu ne
livrent pas `gss-client`). La voie de test Linux, le détecteur de concurrence et la voie
de couverture positionnent `KRB5_REQUIRE_JUDGE=1`, donc un jeu d'essai manquant fait échouer. Une étape supplémentaire
exécute `TestMITClientAgainstThisAcceptor` et échoue à moins que le journal ne dise
*authenticated as alice@* — une voie verte dont le juge a silencieusement cessé de s'exécuter
n'est pas acceptée. `TestMITClientSealed` fait de même avec la confidentialité activée.

Les voies macOS, Windows et inter-architectures n'ont pas de royaume, et là le
juge est sauté. Le plancher de la voie de couverture est de 90 %.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/krb5@v0.3.3](https://pkg.go.dev/github.com/go-authn/krb5@v0.3.3)
