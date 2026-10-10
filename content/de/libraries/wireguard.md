---
title: "wireguard – wessen Schlüssel ist das, und darf er sich verbinden?"
linkTitle: "wireguard"
weight: 130
description: "go-authn/wireguard definiert einen öffentlichen WireGuard-Schlüssel streng und überträgt die vom Anbieter signierte Liste registrierter Schlüssel, die ein Gateway in Peers umsetzt."
tags: [libraries, wireguard, tokens]
---

**Darf sich dieser WireGuard-Schlüssel verbinden, und wem gehört er?** WireGuard authentifiziert einen
Peer über seinen statischen öffentlichen Schlüssel und über nichts sonst: keine Zertifikate, kein Ablauf,
kein Widerruf. Die Frage wird also außerhalb des Protokolls beantwortet, und erneut
beantwortet, sobald sich die Antwort ändert. Ein Anbieter –
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) – beantwortet sie; dieses
Modul ist das, worauf sich der Anbieter und ein Gateway einigen.

```sh
go get github.com/go-authn/wireguard@v0.1.0
```

Seine einzige Abhängigkeit ist [oidc]({{< relref "/libraries/oidc.md" >}}) v0.4.0,
das die Liste prüft.

Es tut zwei Dinge: `ParseKey` sagt, was ein öffentlicher Schlüssel ist, und `Source.Fetch`
holt die signierte `List` des Anbieters mit den Schlüsseln, die Personen registriert haben, jeder ein `Peer`
mit seinem `Key`, `Subject`, `Username`, `Device` und dem Ende seiner Lease.

{{< callout type="info" >}}
**Hier gehen nur öffentliche Schlüssel durch**

Ein privater Schlüssel wird auf dem Gerät erzeugt und verlässt es nie; nichts in diesem
Paket hat einen Platz für einen.
{{< /callout >}}

## Beispiel {#example}

```go
package main

import (
	"crypto/ecdh"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/go-authn/wireguard"
)

func main() {
	// A public key as wg(8) prints it. Here it is derived from a fixed
	// private key; on a device, `wg genkey | wg pubkey` makes one, and the
	// private half never leaves it.
	priv, _ := ecdh.X25519().NewPrivateKey([]byte(strings.Repeat("\x2a", 32)))
	text := base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes())

	k, err := wireguard.ParseKey(text)
	fmt.Println(k, err)

	// The all-zero key authenticates nobody.
	_, err = wireguard.ParseKey(base64.StdEncoding.EncodeToString(make([]byte, 32)))
	fmt.Println(err)

	// Unpadded is another spelling of the same bytes, and is refused.
	_, err = wireguard.ParseKey(strings.TrimRight(text, "="))
	fmt.Println(err)
}
```

```
B6r/Pp/BZydVRPTDpqF82Dfy7G54zYpXsePfs8wDWnY= <nil>
wireguard: the key is a point of low order, which authenticates nobody
wireguard: the key is not base64: illegal base64 data at input byte 40
```

Ein Gateway hält eine `Source` und ruft die Liste ab:

```go
package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/go-authn/wireguard"
)

func main() {
	ctx := context.Background()
	src, err := wireguard.NewSource(ctx, wireguard.SourceConfig{
		Issuer:       "https://bridge.example.org",
		ClientID:     "gateway-1",
		ClientSecret: readSecret("/etc/gateway/client-secret"),
	})
	if err != nil {
		log.Fatal(err)
	}
	for {
		l, err := src.Fetch(ctx) // signed, typ wireguard-peers+jwt, for this gateway, not older
		if err != nil {
			log.Print(err)
		} else {
			for _, p := range l.Peers {
				log.Printf("peer %s is %s (%s) until %s", p.Key, p.Subject, p.Username, p.Expires)
			}
		}
		time.Sleep(time.Minute)
	}
}

// readSecret reads the client secret from a file: never from the command
// line or the environment.
func readSecret(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	return string(b)
}
```

`NewSource` liest die Konfiguration des Anbieters beim Start. `Fetch` holt ein
Token für das Gateway selbst (`client_credentials`, Scope `wireguard_peers`),
ruft die Liste von `/wireguard/peers` unterhalb des Ausstellers ab und prüft sie
mit go-authn/oidc: die Signatur gegen die Schlüsselmenge des Anbieters, den Aussteller,
die Audience (die `ClientID` dieses Gateways), den Ablauf und den `typ`
`wireguard-peers+jwt` (`ListType`) – sodass weder ein Access-Token noch ein ID-Token
als Liste durchgehen kann, noch eine Liste als Token.

## Was es ablehnt und warum {#what-it-refuses-and-why}

**Einen Schlüssel** (`ParseKey`):

- jede andere Schreibweise derselben Bytes. Die Dekodierung ist streng, und der Text
  muss genau so wieder ausgegeben werden, wie er kam, sodass ein nach dem Text geschlüsselter Speicher
  einen Schlüssel nicht zweimal unter zwei Namen halten kann;
- einen Punkt niedriger Ordnung, darunter den Schlüssel aus lauter Nullen. Jeder Austausch mit einem solchen
  ergibt dasselbe gemeinsame Geheimnis, welchen Schlüssel die andere Seite auch hat (RFC 7748 §6.1),
  er authentifiziert also niemanden. `crypto/ecdh` entscheidet das, indem es einen
  Austausch berechnet, sodass auch die Varianten mit gesetztem höchstem Bit abgelehnt werden.

**Eine Liste** (`Fetch`):

| | warum |
|---|---|
| eine Liste mit niedrigerer `version` als eine, die diese `Source` bereits übernommen hat | eine alte Liste ist ebenfalls signiert und kann einen inzwischen zurückgenommenen Schlüssel enthalten |
| ein zweimal aufgeführter Schlüssel | welchen ein Gateway auch behielte, der Verkehr der anderen Person käme unter dem falschen Namen an |
| ein Peer ohne Subject | er gehört niemandem |
| ein Schlüssel, der keiner ist | siehe oben |
| ein Aussteller oder Token-Endpunkt im Klartext, außer Loopback | das Geheimnis des Gateways und die Liste würden eine Verbindung passieren, die jeder mitlesen kann |
| eine `SourceConfig` ohne `ClientID` und `ClientSecret` | ein Gateway liest die Liste als eigener Client |

Eine Liste trägt `exp`: Ein Gateway, das bis dahin keine neuere abrufen kann, hat keine
Liste statt einer veralteten. `Peer.Subject` ist das `sub` der Person, wie es der
Client sieht, der den Schlüssel registriert hat, öffentlich oder pairwise – der Wert, den ein
Gateway auch in den Access-Tokens dieser Person findet.

## Wogegen es geprüft wird {#what-it-is-checked-against}

**`wg(8)` selbst**, aus wireguard-tools, erzeugt die Schlüssel, die `ParseKey`
akzeptieren muss. Es ist in der Linux-Test-Lane, dem Race Detector und der
Coverage-Lane installiert, die `WIREGUARD_REQUIRE_JUDGE=1` setzen, sodass ein fehlendes `wg` zum Fehlschlag führt,
statt übersprungen zu werden. Der Test für niedrige Ordnung prüft die sieben Punkte, die libsodium aufführt,
jeweils mit und ohne höchstes Bit. Die Coverage-Untergrenze liegt bei 100 %.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/wireguard@v0.1.0](https://pkg.go.dev/github.com/go-authn/wireguard@v0.1.0)
