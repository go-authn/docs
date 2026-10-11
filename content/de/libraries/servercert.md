---
title: "servercert – woher das TLS-Zertifikat eines Daemons kommt"
linkTitle: "servercert"
weight: 120
description: "go-authn/servercert stellt ein TLS-Serverzertifikat aus Dateien bereit, die bei Änderung neu gelesen werden, oder von einer ACME-CA über autocert, External Account Binding eingeschlossen."
tags: [bibliotheken, tls, acme, zertifikate]
---

**Woher kommt das TLS-Serverzertifikat eines Daemons?** Ein Zertifikat und ein
Schlüssel auf der Festplatte, neu gelesen, wenn sie sich ändern, oder eine ACME-CA über
[`autocert`](https://pkg.go.dev/golang.org/x/crypto/acme/autocert), External
Account Binding eingeschlossen.

```sh
go get github.com/go-authn/servercert@v0.5.1
```

Eine `Config` nennt genau eine Quelle – `CertFile` und `KeyFile` oder `ACME` –,
und `New` gibt eine `*Source` zurück, deren `TLSConfig()` sie bereitstellt, mit
`MinVersion` TLS 1.2.

## Beispiel {#example}

Aus Dateien:

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

`Config.Check` lehnt eine Konfiguration ab, die nicht funktionieren kann, und rührt nichts an –
keine Datei wird gelesen, kein Verzeichnis angelegt:

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

Die letzte ist Let's Encrypt in Produktion: `DirectoryURL` leer.

## Dateien {#files}

`New` liest das Paar und schlägt **sofort** fehl, wenn eines unlesbar ist, sich nicht
parsen lässt oder dessen Schlüssel nicht der des Zertifikats ist. Danach werden die Dateien höchstens einmal alle
10 Sekunden und während eines Handshakes erneut gelesen; ein geändertes Paar wird
geparst, ohne eine Sperre zu halten, und eingewechselt. Ein geändertes Paar, das sich **nicht**
laden lässt – das Zertifikat vor seinem Schlüssel geschrieben, eine abgeschnittene Datei –, wird
einmal an `OnError` gemeldet, und das letzte gute Paar bleibt im Dienst, sodass ein Erneuerungsjob,
der die beiden Dateien nacheinander schreibt, den Server nie lahmlegt.

## ACME {#acme}

autocert beantwortet zwei Challenge-Typen und keine anderen: `tls-alpn-01` (RFC 8737,
Port 443, ALPN `acme-tls/1`) und, mit `HTTPChallenge`, `http-01` (RFC 8555
§8.3, Port 80, bereitgestellt von `Source.HTTPHandler`). Es gibt kein `dns-01`, daher kein
Wildcard- und kein IP-Adressen-Zertifikat.

Zertifikate werden beim ersten Handshake bezogen, dessen SNI eine der
`Domains` nennt, oder vor jedem Client durch `Source.Prefetch`, und von autocert
erneuert, bevor sie ablaufen. Ein Client, der sich per IP-Adresse verbindet, sendet kein SNI und
erhält das Zertifikat der ersten Domain.

{{< callout type="warning" >}}
**An `NextProtos` anhängen, es nie ersetzen**

Mit ACME enthält `TLSConfig().NextProtos` `acme-tls/1`, ohne das die
tls-alpn-01-Validierung der CA fehlschlägt. Und anhängen müssen Sie: Ein Go-TLS-Server, der
ALPN-Protokolle anbietet, lehnt einen Client ab, dessen Angebot keines davon teilt; daher fügt ein
NFS-over-TLS-Server `sunrpc` hinzu (RFC 9289). `net/http` fügt `http/1.1` und
`h2` selbst hinzu.
{{< /callout >}}

**Eine CA, die keine Challenge braucht.** autocert kehrt sofort zurück, wenn eine neue Bestellung
bereits `ready` ist, was eine CA mit vorab validierten Domains antwortet: GÉANT
TCS, bereitgestellt von HARICA, für ein Enterprise-Admin-Konto. Ein interner Server,
der aus dem Internet weder auf Port 80 noch auf 443 erreichbar ist, kann trotzdem ein öffentlich
vertrauenswürdiges Zertifikat erhalten. Der EAB-HMAC-Schlüssel ist ein Geheimnis, daher nennt die Konfiguration
eine **Datei**, die ihn enthält (`EABHMACKeyFile`), nie den Schlüssel selbst.

Ein Defekt von `x/crypto/acme` wird umgangen ([golang/go#77704](https://github.com/golang/go/issues/77704)):
Nach dem Abschließen einer Bestellung, die die CA noch bearbeitet, fragt der Client die URL
im `Location`-Header der Antwort auf das Abschließen ab, den RFC 8555 dort nicht setzt.
servercert gibt dem ACME-Client einen Transport, der diesen Header hinzufügt, mit der
Bestell-URL aus der früheren newOrder-Antwort.

## Was es ablehnt und warum {#what-it-refuses-and-why}

`Check` lehnt ab: keine oder beide Quellen; ein halbes Dateipaar; ACME ohne
Domains oder Cache-Verzeichnis; einen relativen Pfad; ein halbes EAB; eine Domain, die eine
IP-Adresse oder ein Wildcard ist, aus einem einzigen Label besteht, mit einem Punkt endet oder kein gültiger Hostname
ist; eine Verzeichnis-URL, die nicht https ist (RFC 8555 §6.1).

`New` lehnt außerdem ein Cache-Verzeichnis ab – es enthält private Schlüssel –, das ein
symbolischer Link ist, für Gruppe oder andere zugänglich ist, einem anderen Benutzer gehört als
dem effektiven des Prozesses oder nicht beschreibbar ist; ein fehlendes wird mit
`0700` angelegt und danach geprüft. Jedes Verzeichnis darüber darf nur von
root oder dem effektiven Benutzer änderbar sein, wie es `StrictModes` von sshd für den Pfad zu
`authorized_keys` verlangt, und ein symbolischer Link darüber wird abgelehnt, sofern er nicht root gehört.
Unter Windows werden Modus und Eigentümer nicht geprüft – ACLs entscheiden beides, und sie
einzuschränken ist Ihre Sache –, und ein symbolischer Link irgendwo im Pfad wird abgelehnt.

## Wogegen es geprüft wird {#what-it-is-checked-against}

**pebble**, die Test-CA von Let's Encrypt, im Prozess ausgeführt aus ihren Paketen `ca`, `db`, `va`
und `wfe` mit einem DNS-Stub, stellt echte Zertifikate aus, die `crypto/tls`
gegen die Root von pebble prüft: tls-alpn-01; http-01 über `HTTPHandler` und
seine Kontrolle mit ausgeschaltetem `HTTPChallenge`; EAB verlangt, fehlend, falsch, dann richtig;
eine vorab validierte Domain, ausgestellt ohne offenen Challenge-Port, und ihre Kontrolle. Ein
Test führt dieselbe Ausstellung ohne die Umgehung für golang/go#77704 aus und verlangt,
dass sie fehlschlägt. Die Coverage-Untergrenze liegt bei 100 %.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/servercert@v0.5.1](https://pkg.go.dev/github.com/go-authn/servercert@v0.5.1)
