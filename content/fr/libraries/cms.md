---
title: "cms — signatures en CMS SignedData"
linkTitle: "cms"
weight: 115
description: "go-authn/cms lit, vérifie et signe le CMS SignedData (RFC 5652), le conteneur des signatures PDF, UEFI et S/MIME, jugé par OpenSSL."
tags: [bibliothèques, signatures, certificats]
---

**Cette signature tient-elle sur ces octets, et quel certificat l'a faite ?**
Le CMS SignedData ([RFC 5652](https://www.rfc-editor.org/rfc/rfc5652)) est le
conteneur dans lequel s'écrivent une signature PDF, une variable authentifiée
UEFI et un message S/MIME. La bibliothèque standard lit les certificats et
vérifie les signatures, mais n'a pas de CMS.

```sh
go get github.com/go-authn/cms@v0.2.0
```

La v0.2.0 **lit, vérifie et signe**.

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

## Signer {#signing}

`cms.Sign` écrit un ContentInfo DER avec **un seul signataire**, à partir de
n'importe quel `crypto.Signer` : une clé RSA, ECDSA ou Ed25519, dans un fichier,
sur une carte ou dans un HSM. Avant de rendre son résultat, il vérifie la
signature sous le certificat : un signataire qui renvoie une signature fausse
est refusé, jamais émis.

```go
package main

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/go-authn/cms"
)

func main() {
	// A key and a self-signed certificate, for the example. In practice the
	// key may live on a card or in an HSM: any crypto.Signer will do.
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		panic(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "signer"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
	}
	certDER, err := x509.CreateCertificate(rand.Reader, template, template, key.Public(), key)
	if err != nil {
		panic(err)
	}
	cert, err := x509.ParseCertificate(certDER)
	if err != nil {
		panic(err)
	}

	content := []byte("the bytes to sign")
	der, err := cms.Sign(content, cms.SignOptions{
		Signer:      key,
		Certificate: cert,
		Hash:        crypto.SHA256,
		Detached:    true, // as a PDF signature: the content is not inside
		SigningTime: time.Now(),
	})
	switch {
	case errors.Is(err, cms.ErrSigner):
		panic(fmt.Sprint("the key or the device failed: ", err))
	case errors.Is(err, cms.ErrOptions):
		panic(fmt.Sprint("the request is wrong: ", err))
	case err != nil: // cms.ErrUnsupported
		panic(err)
	}

	// Sign checked its own signature; Verify is the reader's side.
	sd, err := cms.Parse(der)
	if err != nil {
		panic(err)
	}
	signers, err := sd.Verify(content)
	if err != nil {
		panic(err)
	}
	fmt.Println("signed by", signers[0].Subject.CommonName)

	content[0] ^= 1
	_, err = sd.Verify(content)
	fmt.Println("altered content:", errors.Is(err, cms.ErrInvalid))
}
```

`SignOptions` accepte aussi `Chain` (les intermédiaires à embarquer), `PSS`
(RSASSA-PSS), `SigningCertificateV2` (RFC 5035, ce qu'exigent les profils de
base CAdES et PAdES), `ContentType`, `NoSignedAttrs` et `Rand`. L'empreinte est
SHA-256 par défaut, ou SHA-384 ou SHA-512 ; Ed25519 utilise toujours SHA-512.
SHA-1 est refusé.

`Sign` a trois erreurs propres : `ErrOptions` (la demande est fausse),
`ErrSigner` (la clé ou le dispositif a échoué, ou a rendu une signature qui ne
se vérifie pas sous le certificat) et `ErrUnsupported` (un algorithme qu'il
n'écrit pas). Ed25519 **sans attributs signés** est refusé aussi : la RFC 8419
l'autorise, mais OpenSSL ne vérifie pas ce que ce paquet écrirait.

`cms -verify` d'OpenSSL et le `Verify` de ce paquet s'accordent sur toutes les
combinaisons soumises : **58 combinaisons, 203 verdicts**, sur RSA PKCS #1 v1.5,
RSA-PSS et ECDSA P-256 avec SHA-256, SHA-384 et SHA-512, et Ed25519 avec
SHA-512, en attaché et en détaché, avec et sans attributs signés. `Verify` ne
vérifie pas encore signing-certificate-v2 : lier le certificat du signataire à
cet attribut revient à l'appelant.

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
- des attributs signés sous quatre formes non DER : une étiquette `[0]`
  primitive (à un bit d'une signature valide), un attribut qui n'est pas une
  SEQUENCE, des valeurs qui ne sont pas un SET, et des octets en trop dans un
  attribut. L'ordre du SET n'est pas vérifié ;
- plus de **16 signataires**, et plus de **16 Mio**. Une borne de taille n'est
  pas une borne de travail, d'où le plafond de signataires : le contenu est
  haché une fois par algorithme d'empreinte, mais un signataire Ed25519 sans
  attributs signés le hache encore en entier à chaque vérification.

**Pas encore :** les longueurs indéfinies BER sont refusées plutôt que
devinées ; la signature n'a qu'un signataire, sans contre-signature ni jeton
d'horodatage ; `Verify` ne vérifie pas signing-certificate-v2 ; pas de
validation de chaîne, à dessein.

## Contre quoi il est vérifié {#what-it-is-checked-against}

**La commande `cms` d'OpenSSL.** Onze signatures faites par OpenSSL 4.1.0
couvrent RSA, RSA-PSS, ECDSA et Ed25519, avec contenu attaché et détaché et les
deux formes d'identifiant de signataire. `openssl cms -verify` et ce paquet
rendent le même verdict sur chacune et sur ses variantes altérées : 34 sur 34.

Sur deux points, le paquet est **plus strict** qu'OpenSSL 4.1.0, qui accepte
une étiquette d'attributs signés primitive et Ed25519 sur SHA-256.
