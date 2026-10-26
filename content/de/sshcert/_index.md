---
title: "sshcert"
linkTitle: "sshcert"
weight: 40
description: "Die GÉANT-/EuroHPC-Domain-Grant-Erweiterung von SSH-Benutzerzertifikaten und sshcert-authorize, der fail-closed Befehl, den sshd fragt, ob ein Zertifikat für diesen Host bestimmt ist."
tags: [sshcert, ssh, eurohpc]
---

**Ein Zertifikat von der CA einer Föderation ist für sich allein keine Erlaubnis für
jeden Host, der dieser CA vertraut.** Die SSH-CA der EuroHPC Federation Platform
schreibt die Hosts, für die ein Zertifikat bestimmt ist, in eine Erweiterung,
`ssh-domain-grant@core.aai.geant.org`, und `sshd` ignoriert sie. go-authn/sshcert
liest und schreibt diese Erweiterung, und sein Befehl `sshcert-authorize` ist das, was
`sshd` ausführt, um sie durchzusetzen. Reines Go, `CGO_ENABLED=0`. Diese Seiten
beschreiben v0.1.9.

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.9
$ sshcert-authorize -version
sshcert-authorize v0.1.9
```

| | |
|---|---|
| [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}) | das `AuthorizedPrincipalsCommand`: was es prüft, was es ablehnt und wie sshd es aufruft |

## Die Erweiterung {#the-extension}

Ihre Daten sind ein kompaktes JSON-Array von Host-Mustern, `["login.example.org"]`. Ein
`*` passt auf **ein oder mehrere** Zeichen innerhalb eines einzigen Labels, und Namen
werden ohne Beachtung der Groß- und Kleinschreibung verglichen:

| Muster | passt auf | passt nicht auf |
|---|---|---|
| `login.example.org` | `login.example.org`, `LOGIN.example.org` | `www.login.example.org` |
| `*.example.org` | `a.example.org` | `example.org`, `a.b.example.org` |
| `prod-*.example.org` | `prod-1.example.org` | `prod-.example.org` |
| `*.*.example.org` | `a.b.example.org` | `a.example.org` |

Das Lesen ist streng: Nur was der Encoder schreibt, wird angenommen. Kein
Leerraum, nichts nach `]`, keine JSON-Escapes, keine Duplikate, höchstens 64
Muster, jedes aus Buchstaben, Ziffern, Bindestrichen und `*`, in Labels von 1 bis 63
Bytes, höchstens 253 Bytes, und **kein `*` im Label ganz rechts**. `null`, Objekte,
Zahlen und verschachtelte Arrays werden abgelehnt. `[]` wird angenommen und gewährt
keinen Host.

Ein Grant, der vorhanden und fehlerhaft ist, wird nie als fehlend gemeldet. Dieser
Unterschied ist der ganze Sinn des Befehls.

## Wer sie verwendet {#who-uses-it}

- **[authn-bridge]({{< relref "/authn-bridge/certificates.md#the-eurohpc-ssh-ca-profile" >}})**
  schreibt die Erweiterung für die `ssh_domain_grants` eines Clients, nachdem es jedes
  Muster mit `ValidatePattern` aus diesem Paket geprüft hat.
- Der SFTP-Server von **go-fileshare** liest sie mit `ssh_domains` und lehnt ein
  Zertifikat ohne Grant ab, sofern nicht `ssh_accept_ungranted` gesetzt ist.
- **sshcert-authorize** ist dieselbe Prüfung für ein einfaches `sshd`.

## Lizenz {#licence}

BSD-3-Clause.
