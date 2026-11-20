---
title: "cms — signatures en CMS SignedData"
linkTitle: "cms"
weight: 115
description: "go-authn/cms lit et vérifie le CMS SignedData (RFC 5652), le conteneur des signatures PDF, UEFI et S/MIME, jugé par OpenSSL."
tags: [bibliothèques, signatures, certificats]
---

**Cette signature tient-elle sur ces octets, et quel certificat l'a faite ?**
Le CMS SignedData ([RFC 5652](https://www.rfc-editor.org/rfc/rfc5652)) est le
conteneur dans lequel s'écrivent une signature PDF, une variable authentifiée
UEFI et un message S/MIME. La bibliothèque standard lit les certificats et
vérifie les signatures, mais n'a pas de CMS.

```sh
go get github.com/go-authn/cms@v0.1.0
```

La v0.1.0 **lit et vérifie**. La signature viendra à la version suivante.

## Exemple {#example}

```go
package main

import (
	"crypto/x509"
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/cms"
)

func main() {
	// A detached signature and the bytes it signed. For a PDF these are the
	// signature dictionary's /Contents and the file's /ByteRange.
	der, err := os.ReadFile("signature.der")
	if err != nil {
		panic(err)
	}
	content, err := os.ReadFile("signed-bytes")
	if err != nil {
		panic(err)
	}

	sd, err := cms.Parse(der)
	if err != nil {
		panic(err)
	}
	signers, err := sd.Verify(content) // nil instead, when the content is attached
	switch {
	case errors.Is(err, cms.ErrInvalid):
		fmt.Println("the signature does not hold:", err)
		return
	case errors.Is(err, cms.ErrUnsupported):
		fmt.Println("a signature this package cannot check:", err)
		return
	case err != nil: // cms.ErrMalformed
		fmt.Println("not a signature:", err)
		return
	}

	// The signature holds. Whether to TRUST who made it is a second question,
	// with inputs of its own: the roots you accept.
	roots := x509.NewCertPool() // fill with the roots you trust
	for _, c := range signers {
		_, err := c.Verify(x509.VerifyOptions{Roots: roots, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}})
		fmt.Println(c.Subject, "chain:", err)
	}
}
```

`Verify` répond à la question de savoir si la signature tient. La
**confiance** — la chaîne du certificat, sa validité, sa révocation — est une
décision distincte, que la RFC 5652 §5.6 place hors de CMS : `crypto/x509`
pour la chaîne, et la vérification des CRL de
[go-authn/revocation](https://github.com/go-authn/revocation) pour ce qui a été
retiré.

## Trois erreurs, parce qu'un appelant a besoin de trois réponses {#three-errors-because-a-caller-needs-three-answers}

| erreur | signifie |
|---|---|
| `ErrMalformed` | pas un SignedData que ce paquet sait lire |
| `ErrUnsupported` | une signature, qui utilise quelque chose qui n'est pas implémenté ici |
| `ErrInvalid` | lisible et prise en charge, et la signature ne tient pas |

Chaque refus enveloppe exactement l'une d'elles, et les tests de fuzzing le
tiennent pour un invariant.

## Ce qu'il refuse {#what-it-refuses}

D'après le code, chacun avec un test qui vérifie son message :

- un signataire dont le certificat n'est pas dans le conteneur ;
- des attributs signés sans exactement un `content-type` et exactement un
  `message-digest`, chacun avec une seule valeur ;
- un type de contenu signé qui n'est pas celui du contenu ;
- une empreinte qui ne correspond pas au contenu — **recalculée ici**, jamais
  prise au signataire ;
- un algorithme de signature dont le hachage propre n'est pas celui de
  l'empreinte ;
- SHA-1, refusé nommément ;
- Ed25519 sur autre chose que SHA-512 (RFC 8419) ;
- des attributs signés qui ne sont pas du DER — y compris une étiquette `[0]`
  primitive, à un bit d'une signature valide ;
- plus de **16 signataires**, et plus de **16 Mio**. Une borne de taille n'est
  pas une borne de travail : chaque signataire est vérifié sur tout le contenu.

**Pas encore :** les longueurs indéfinies BER sont refusées plutôt que
devinées ; pas de signature ; pas de validation de chaîne, à dessein.

## Contre quoi il est vérifié {#what-it-is-checked-against}

**La commande `cms` d'OpenSSL.** Onze signatures faites par OpenSSL 4.1.0
couvrent RSA, RSA-PSS, ECDSA et Ed25519, avec contenu attaché et détaché et les
deux formes d'identifiant de signataire. `openssl cms -verify` et ce paquet
rendent le même verdict sur chacune et sur ses variantes altérées : 34 sur 34.

Sur deux points, le paquet est **plus strict** qu'OpenSSL 4.1.0, qui accepte
une étiquette d'attributs signés primitive et Ed25519 sur SHA-256.
