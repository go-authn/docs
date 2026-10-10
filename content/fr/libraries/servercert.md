---
title: "servercert — d'où vient le certificat TLS d'un démon"
linkTitle: "servercert"
weight: 120
description: "go-authn/servercert sert un certificat de serveur TLS issu de fichiers relus quand ils changent, ou d'une AC ACME via autocert, External Account Binding compris."
tags: [libraries, tls, acme, certificates]
---

**D'où vient le certificat de serveur TLS d'un démon ?** Un certificat et une
clé sur disque, relus quand ils changent, ou une AC (autorité de certification)
ACME via [`autocert`](https://pkg.go.dev/golang.org/x/crypto/acme/autocert),
External Account Binding compris.

```sh
go get github.com/go-authn/servercert@v0.5.1
```

Une `Config` nomme exactement une source — `CertFile` et `KeyFile`, ou `ACME` —
et `New` renvoie une `*Source` dont `TLSConfig()` la sert, avec
`MinVersion` TLS 1.2.

## Exemple {#example}

Depuis des fichiers :

```go
package main

import (
	"log"
	"net/http"

	"github.com/go-authn/servercert"
)

func main() {
	src, err := servercert.New(servercert.Config{
		CertFile: "/etc/fileshare/tls/fullchain.pem",
		KeyFile:  "/etc/fileshare/tls/privkey.pem",
		OnError:  func(err error) { log.Print(err) }, // a renewal that did not load
	})
	if err != nil {
		log.Fatal(err) // unreadable, unparsable, or a key that is not the certificate's
	}
	srv := &http.Server{Addr: ":443", TLSConfig: src.TLSConfig()}
	log.Fatal(srv.ListenAndServeTLS("", ""))
}
```

`Config.Check` refuse une configuration qui ne peut pas fonctionner, et ne touche à rien —
aucun fichier lu, aucun répertoire créé :

```go
package main

import (
	"fmt"

	"github.com/go-authn/servercert"
)

func main() {
	// Check touches nothing: no file is read, no directory created.
	for _, c := range []servercert.Config{
		{ACME: &servercert.ACME{Domains: []string{"*.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"192.0.2.10"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "acme"}},
		{CertFile: "/etc/fileshare/tls/fullchain.pem"},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme",
			DirectoryURL: "http://acme.example.org/directory"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
	} {
		fmt.Println(c.Check())
	}
}
```

```
servercert: ACME domain "*.example.org" is a wildcard; that needs dns-01, which autocert does not do
servercert: ACME domain "192.0.2.10" is an IP address; autocert issues only for DNS names
servercert: ACME.CacheDir "acme" is not an absolute path
servercert: CertFile and KeyFile go together; one of them is empty
servercert: ACME.DirectoryURL "http://acme.example.org/directory" is not an https URL (RFC 8555 §6.1)
<nil>
```

La dernière est la production de Let's Encrypt : `DirectoryURL` vide.

## Fichiers {#files}

`New` lit la paire et échoue **tout de suite** sur une paire illisible, qui ne
s'analyse pas, ou dont la clé n'est pas celle du certificat. Ensuite, au plus une
fois toutes les 10 secondes et pendant une poignée de main, les fichiers sont
relus ; une paire modifiée est analysée sans tenir de verrou puis mise en place.
Une paire modifiée qui ne se charge **pas** — le certificat écrit avant sa clé,
un fichier tronqué — est signalée une fois à `OnError`, et la dernière bonne paire
reste en service : une tâche de renouvellement qui écrit les deux fichiers l'un
après l'autre ne fait donc jamais tomber le serveur.

## ACME {#acme}

autocert répond à deux types de défi et à aucun autre : `tls-alpn-01` (RFC 8737,
port 443, ALPN `acme-tls/1`) et, avec `HTTPChallenge`, `http-01` (RFC 8555
§8.3, port 80, servi par `Source.HTTPHandler`). Il n'y a pas de `dns-01`, donc ni
joker ni certificat pour une adresse IP.

Les certificats sont obtenus à la première poignée de main dont le SNI nomme l'un
des `Domains`, ou avant tout client par `Source.Prefetch`, et renouvelés par autocert
avant leur expiration. Un client qui se connecte par adresse IP n'envoie pas de SNI et
reçoit le certificat du premier domaine.

{{< callout type="warning" >}}
**Ajouter à `NextProtos`, ne jamais le remplacer**

Avec ACME, `TLSConfig().NextProtos` contient `acme-tls/1`, sans quoi la validation
tls-alpn-01 de l'AC échoue. Et il faut bien ajouter : un serveur TLS Go qui
annonce des protocoles ALPN refuse un client dont l'offre n'en partage aucun ; un
serveur NFS sur TLS ajoute donc `sunrpc` (RFC 9289). `net/http` ajoute `http/1.1` et
`h2` de lui-même.
{{< /callout >}}

**Une AC qui n'exige aucun défi.** autocert rend la main aussitôt quand une nouvelle
commande est déjà `ready`, ce que répond une AC aux domaines prévalidés : GÉANT
TCS, servi par HARICA, pour un compte Enterprise Admin. Un serveur interne
joignable depuis Internet ni sur le port 80 ni sur le 443 peut tout de même obtenir
un certificat reconnu publiquement. La clé HMAC de l'EAB est un secret : la
configuration nomme donc un **fichier** qui la contient (`EABHMACKeyFile`), jamais la clé.

Un défaut de `x/crypto/acme` est contourné ([golang/go#77704](https://github.com/golang/go/issues/77704)) :
après la finalisation d'une commande que l'AC traite encore, le client interroge un
en-tête `Location` que RFC 8555 ne place pas sur la réponse de finalisation. Le
transport du client ACME le fournit à partir de l'URL de commande vue plus tôt.

## Ce qu'elle refuse, et pourquoi {#what-it-refuses-and-why}

`Check` refuse : aucune source ou les deux ; une moitié de paire de fichiers ; ACME sans
domaines ou sans répertoire de cache ; un chemin relatif ; une moitié d'EAB ; un domaine
qui est une adresse IP, un joker, une seule étiquette, se termine par un point, ou n'est
pas un nom d'hôte valide ; une URL de répertoire qui n'est pas en https (RFC 8555 §6.1).

`New` refuse aussi un répertoire de cache — il contient des clés privées — qui est un
lien symbolique, est accessible au groupe ou aux autres, appartient à un autre utilisateur
que l'utilisateur effectif du processus, ou n'est pas accessible en écriture ; un répertoire
absent est créé en `0700` puis vérifié. Chaque répertoire au-dessus ne doit être modifiable
que par root ou par l'utilisateur effectif, comme le `StrictModes` de sshd l'exige du chemin
vers `authorized_keys`, et un lien symbolique au-dessus est refusé sauf s'il appartient à root.
Sous Windows, le mode et le propriétaire ne sont pas vérifiés — les ACL décident des deux, et
les restreindre vous revient — et un lien symbolique n'importe où dans le chemin est refusé.

## Contre quoi elle est vérifiée {#what-it-is-checked-against}

**pebble**, l'AC de test de Let's Encrypt, exécutée dans le processus à partir de ses
paquets `ca`, `db`, `va` et `wfe` avec un bouchon DNS, délivrant de vrais certificats
que `crypto/tls` vérifie contre la racine de pebble : tls-alpn-01 ; http-01 via
`HTTPHandler` et son témoin avec `HTTPChallenge` désactivé ; EAB exigé, absent, faux,
puis correct ; un domaine prévalidé délivré sans aucun port de défi ouvert, et son témoin.
Un test exécute la même délivrance sans le contournement de golang/go#77704 et exige
qu'elle échoue. Le plancher de couverture est de 100 %.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/servercert@v0.5.1](https://pkg.go.dev/github.com/go-authn/servercert@v0.5.1)
