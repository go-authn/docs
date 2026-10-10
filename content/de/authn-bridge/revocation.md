---
title: "Was es widerruft, und wie Server davon erfahren"
linkTitle: "Widerruf"
weight: 60
description: "Die signierte, datierte KRL und CRL, die authn-bridge für die widerrufenen Zertifikate veröffentlicht, und der Shared-Signals-Sender, der erreicht, was keine Liste benennen kann."
tags: [authn-bridge, revocation, krl, crl, shared signals]
---

Eine Person oder eine Einrichtung zu deaktivieren ([die Admin-API]({{< relref "/authn-bridge/admin.md" >}}))
beendet alles, was zum Anbieter zurückkommt: Refresh-Tokens, `/userinfo`,
neue Zertifikate, Anwendungspasswörter. Was er bereits ausgegeben hat, wird
anderswo geprüft, gegen Schlüssel, und zwei Mechanismen erreichen es:

| Zugangsdaten | zurückgenommen durch |
|---|---|
| ein SSH-Zertifikat, das diese CA signiert hat | die **KRL**, `GET /ssh/krl`, mit ihrer Signatur unter `/ssh/krl.sig` |
| ein X.509-Client-Zertifikat | die **CRL**, `GET /x509/crl` |
| ein Access-Token, ein opkssh-Zertifikat, alles, was ein Server allein prüft | ein **Shared-Signals**-Ereignis `session-revoked` |

Der Widerruf ist endgültig. Eine Person wieder zu aktivieren, bringt ihre
Zertifikate nicht zurück; sie erhält neue. Eine Liste, aus der sich ein Widerruf entfernen ließe,
ist eine Liste, die jemand mit Zugang zur Admin-API bearbeiten könnte.

## Die Listen {#the-lists}

Beide werden so ausgestellt, wie es das Protokoll von go-authn/revocation vorsieht, damit sie
über beliebige Wege reisen können (einen Spiegel, einfaches HTTP, eine Datei) und trotzdem von dem geprüft werden,
der sie liest:

| | KRL | CRL |
|---|---|---|
| Format | OpenSSH `PROTOCOL.krl`, geschrieben von go-authn/krl: was `RevokedKeys` von `sshd` und `ssh-keygen -Q` lesen | DER, RFC 5280 |
| signiert | eine abgetrennte SSHSIG-Signatur des SSH-CA-Schlüssels, Namensraum `krl@go-authn.github.io` | von der CA, die die Zertifikate signiert |
| aktuell bis | ihre Erweiterung `expires@go-authn.github.io` (die sshd ignoriert) | ihr `nextUpdate` |
| geordnet nach | ihrer `krl_version`, dann ihrem Erzeugungsdatum | ihrer CRL Number, dann `thisUpdate` |

Jede Liste gibt an, dass sie **eine Stunde** nach ihrer Ausstellung nicht mehr aktuell ist. Eine Liste wird
unverändert aufbewahrt und ausgeliefert, bis sie die Hälfte dieser Zeit erreicht hat oder bis etwas
widerrufen wird; die nächste Anfrage erhält dann eine neue Ausgabe. Eine Ausgabe wird nie früher datiert als
die, die sie ersetzt, selbst wenn die Uhr zurückspringt, denn ein Leser lehnt eine
frühere Ausgabe derselben Version als Rollback ab. Die CRL Number steigt bei jeder
Ausgabe.

Die KRL eines Testanbieters, bei dem nichts widerrufen ist:

```
$ curl -s -D - -o var/bridge.krl http://127.0.0.1:28473/ssh/krl
HTTP/1.1 200 OK
Cache-Control: max-age=60
Content-Type: application/octet-stream
Etag: "c3e6cb39788fe31df282c784e49f1ba9"
Date: Sat, 10 Oct 2026 19:17:54 GMT
Content-Length: 130

$ ssh-keygen -Q -l -f var/bridge.krl
# KRL version 0
# Generated at 20261010T211754
# Comment: go-authn/bridge http://127.0.0.1:28473
```

**Das ETag ist das des Inhalts.** Ein Leser fragt mit `If-None-Match` ab und erhält
`304`, solange die Ausgabe, die er hält, noch die ausgelieferte ist; da sich der Inhalt
mindestens jede halbe Stunde ändert, behält ein abfragender Leser eine Kopie nie über ihren
Ablauf hinaus:

```
$ curl -s -o /dev/null -H 'If-None-Match: "c3e6cb39788fe31df282c784e49f1ba9"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl
304
```

**Die Signatur wird mit `If-Match`** auf das ETag der Liste abgerufen. Wurde die Liste
zwischenzeitlich neu ausgestellt, lautet die Antwort `412` statt einer Signatur, die nicht
zu ihr passt:

```
$ curl -s -o var/bridge.krl.sig -H 'If-Match: "c3e6cb39788fe31df282c784e49f1ba9"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
200
$ curl -s -o /dev/null -H 'If-Match: "stale"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
412
```

`ssh-keygen` prüft die Signatur und lehnt sie in jedem anderen Namensraum ab:

```
$ ssh-keygen -Y verify -f allowed -I bridge -n krl@go-authn.github.io -s bridge.krl.sig < bridge.krl
Good "krl@go-authn.github.io" signature for bridge with ED25519 key SHA256:6gbNjRq4BYFximPaiHg3L5G01DO7ycES/Bx2Hg4Qkvg
```

wobei `allowed` die Zeile
`bridge namespaces="krl@go-authn.github.io" <the CA key from /ssh/config>` ist.

Die CRL, im selben Moment ausgestellt:

```
$ openssl crl -inform DER -in var/bridge.crl -noout -text
Certificate Revocation List (CRL):
    Version 2 (0x1)
    Signature Algorithm: ecdsa-with-SHA256
    Issuer: CN=go-authn bridge NFS client CA
    Last Update: Oct 10 19:18:02 2026 GMT
    Next Update: Oct 10 20:18:02 2026 GMT
    CRL extensions:
        X509v3 Authority Key Identifier: 
            70:62:92:19:7D:D4:26:45:97:9B:32:20:0C:D4:67:02:45:6C:55:B9
        X509v3 CRL Number: 
            1791659882080
No Revoked Certificates.
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:45:02:20:50:1e:bd:e3:7b:39:32:6c:7b:d9:91:bd:bb:78:
        f2:74:ed:ca:da:74:77:e0:0f:39:e0:63:4c:45:91:47:ba:98:
        02:21:00:a0:1f:54:40:3f:75:66:af:f5:a9:a8:86:f3:2d:a9:
        d7:60:15:24:43:b6:80:a5:bb:45:49:9d:89:56:89:e0:68
```

Ein Zertifikat bleibt in seiner Liste, bis es abläuft: Ein abgelaufenes Zertifikat wird
überall abgelehnt, ohne aufgeführt zu sein.

### Wer sie liest {#who-reads-them}

- Ein einfaches `sshd` oder nginx und andere TLS-Server:
  [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) ruft die Listen ab,
  behält nur die, die die Prüfung bestehen, schreibt sie dorthin, wo die Server sie lesen, und
  schlägt für sshd geschlossen fehl (fail closed), wenn eine Liste verfällt.
- [go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)
  ruft sie selbst ab, prüft sie und lehnt die Zertifikate des Anbieters ab,
  solange es keine aktuelle Liste hält.

## Shared Signals {#shared-signals}

Ein Access-Token oder ein opkssh-Zertifikat wird dort geprüft, wo es verwendet wird, und keine
Liste kann es benennen. Deshalb ist der Anbieter ein OpenID-Shared-Signals-Sender: Bei
`DisablePerson`, `RevokePerson` und `DisableIdP` reiht er ein CAEP-Ereignis
**`session-revoked`** ein (alles, was diesem Subject vor dem Zeitpunkt des
Ereignisses ausgestellt wurde, ist ungültig), für jeden Empfänger, der danach gefragt hat.

```hcl
state { ... }            # required: a queue a restart empties loses revocations
ssf {}                   # event_retention = "192h" by default

client "fileshare-ssf" { # a receiver: client credentials, scope ssf
  secret_file  = "/etc/authn-bridge/fileshare-ssf.secret"
  ssf_receiver = true
  audience     = ["fileshare"]
}
```

```
$ curl -s http://127.0.0.1:28473/.well-known/ssf-configuration | jq .
{
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "delivery_methods_supported": [
    "urn:ietf:rfc:8936"
  ],
  "configuration_endpoint": "http://127.0.0.1:28473/ssf/streams",
  "status_endpoint": "http://127.0.0.1:28473/ssf/streams/status",
  "add_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:add",
  "remove_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:remove",
  "verification_endpoint": "http://127.0.0.1:28473/ssf/streams/verify",
  "spec_version": "1_0",
  "authorization_schemes": [
    {
      "spec_urn": "urn:ietf:rfc:6749"
    }
  ]
}
```

- **Nur Poll-Zustellung** (RFC 8936): Der Empfänger fragt; von hier aus wird nichts nach außen aufgebaut.
- Ein Empfänger authentifiziert sich mit einem Access-Token aus dem **Client-Credentials**-Grant,
  für einen `ssf_receiver`-Client mit einem Geheimnis, Scope `ssf`.
  Er sieht nur seine eigenen Streams, höchstens zehn.
- Ereignisse sind SETs (RFC 8417), signiert mit dem ID-Token-Schlüssel, ohne `exp` und ohne
  `sub`. Das Subject ist standardmäßig das **Konto**, `acct:<username>`: Ein `sub`
  kann pairwise sein, eines pro Client. Ein Empfänger, der mit
  `ssf_subject_format = "iss_sub"` konfiguriert ist, erhält stattdessen den Aussteller und das öffentliche `sub`.
- Eine deaktivierte Einrichtung ergibt ein Ereignis pro Person, von der der Anbieter dort eine Spur hat,
  und eines, dessen Subject der **Tenant** ist, die Entity-ID der Einrichtung,
  mit ihren Scopes, was die Personen abdeckt, die der Anbieter vergessen hat.
- Streams und nicht zugestellte Ereignisse werden in der `state`-Datenbank aufbewahrt, bis sie
  bestätigt werden oder `event_retention` verstrichen ist. Ein Ereignis, das ein Empfänger als
  fehlerhaft meldet, wird erneut ausgegeben, bis zu zehnmal.

Der SSF-Block wird ohne einen `state`-Block abgelehnt:

```
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```
