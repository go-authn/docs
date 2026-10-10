---
title: "Zertifikate"
linkTitle: "Zertifikate"
weight: 50
description: "Die SSH-Benutzerzertifikate, die authn-bridge signiert, ihr Profil für die EuroHPC Federation Platform und die X.509-Client-Zertifikate, die es für NFS über TLS ausstellt."
tags: [authn-bridge, ssh, x509, eurohpc]
---

Eine angemeldete Person kann für einige Stunden einen öffentlichen SSH-Schlüssel zertifizieren oder ein
X.509-Client-Zertifikat ausstellen lassen. Ein Server, der der CA des Anbieters vertraut, lässt
sie herein, ohne dass dort eine Kontodatei zu bearbeiten wäre. Jedes Zertifikat wird **in
`certificates_file` festgehalten, bevor es ausgegeben wird**: Eines, das sich nicht festhalten lässt, wird
nicht ausgestellt, da es nie widerrufen werden könnte, und widerrufene werden in
der [KRL und der CRL]({{< relref "/authn-bridge/revocation.md" >}}) veröffentlicht.

## SSH-Zertifikate {#ssh-certificates}

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

ssh_ca {
  key_file = "/var/lib/authn-bridge/ssh-ca"   # authn-bridge keygen --ssh-ca; Ed25519
  validity = "12h"                            # the default; a week at most
}

client "sftp" {
  device           = true
  ssh_certificates = true
}
```

`authn-bridge ssh-cert --issuer https://login.example.org --client sftp` meldet
sich mit einem Code an, sendet `~/.ssh/id_ed25519.pub` (oder `--key`) per POST an
`/ssh/certificate`, mit einem Token des Scopes `ssh`, und schreibt
`<key>-cert.pub` daneben, wo `ssh` und `sftp` es finden.

Der CA-Schlüssel muss Ed25519 sein: Ein RSA-CA-Schlüssel signiert mit SHA-1, sofern ihm nichts
anderes gesagt wird, und das lehnt OpenSSH seit 8.8 standardmäßig ab.

**Was das Zertifikat sagt.**

- **Genau ein Principal**, der `preferred_username` der Person, sofern das
  Profil des Clients keinen anderen Claim nennt. Ein Zertifikat ohne Principal gilt
  für *jeden* Benutzer (PROTOCOL.certkeys); eine Person ohne Benutzernamen erhält daher keines. Ein
  Name mit einem Komma, einem Leerzeichen, einem Anführungszeichen, einem Backslash oder einem Steuerzeichen wird
  abgelehnt (`403`): `sshd` liest `principals="a,b"` und Einträge in `AuthorizedPrincipalsFile`
  als Listen, sodass ein solcher Name zwei sind.
- **Key ID** `<principal> sub=<sub> jti=<token id>`: das, was `sshd` protokolliert.
- **Keine `permit-*`-Erweiterung** standardmäßig. SFTP braucht keine, und ein Zertifikat,
  das kein pty, keine Weiterleitung und keine rc-Datei erlaubt, gewährt Dateizugriff und
  sonst nichts.
- **Die Gruppen der Person** in der Erweiterung `groups@go-authn.org`, eine pro Zeile,
  wenn das Token Gruppen trägt. OpenSSH ignoriert sie; sie ist signiert, sodass ein Server,
  der nach Gruppe autorisiert, ihr glauben kann.
- **Gültig** ab vor fünf Minuten (für Uhren, die nicht übereinstimmen) bis `validity`
  ab jetzt, oder bis die Sitzung beim IdP endet, falls das früher ist.
- **Der Schlüssel** muss Ed25519, ECDSA P-256/384/521, ein Sicherheitsschlüssel (`sk-`) oder
  RSA mit mindestens 2048 Bit sein. Ein Zertifikat als Schlüssel wird abgelehnt.

## Das SSH-CA-Profil von EuroHPC {#the-eurohpc-ssh-ca-profile}

Die SSH-CA der EuroHPC Federation Platform (GÉANT / MyAccessID) stellt Ed25519-Zertifikate
mit einer Stunde Gültigkeit aus, mit einem Principal, der die Person föderationsweit benennt,
und den Hosts, für die sie bestimmt sind, in der GÉANT-Erweiterung
`ssh-domain-grant@core.aai.geant.org`. Ein Client kann seine
Zertifikate in dieser Form ausstellen lassen. Jeder Schlüssel gilt pro Client und ist optional; ein
Client, der keinen setzt, erhält das oben beschriebene Zertifikat.

```hcl
client "efp" {
  device              = true
  ssh_certificates    = true
  ssh_principal_claim = "voperson_id"               # the default is preferred_username
  ssh_validity        = "1h"                        # never longer than ssh_ca's, nor the IdP's session
  ssh_extensions      = ["permit-pty"]              # none by default
  ssh_domain_grants   = ["login.hpc.example.org"]   # the hosting entity's hosts
  # ssh_source_address = ["192.0.2.0/24"]           # the source-address critical option
}
```

| Schlüssel | |
|---|---|
| `ssh_principal_claim` | `preferred_username`, `sub`, `voperson_id` oder `eduperson_principal_name`. Die letzten beiden gibt der Scope `eduperson` frei, den das Token haben muss (`authn-bridge ssh-cert --scope eduperson`); andernfalls, oder wenn der IdP kein solches Attribut freigegeben hat, lautet die Antwort `403` und sagt, welches |
| `ssh_extensions` | aus `permit-pty`, `permit-user-rc`, `permit-port-forwarding`, `permit-agent-forwarding`, `permit-X11-forwarding` |
| `ssh_source_address` | Adressen oder CIDR-Präfixe, kanonisch in `source-address` geschrieben |
| `ssh_validity` | kürzer als `validity` von `ssh_ca`, für diesen Client |
| `ssh_domain_grants` | Domain-Muster, geprüft mit `ValidatePattern` aus [go-authn/sshcert]({{< relref "/sshcert/_index.md" >}}) und kodiert mit dessen `EncodeDomainGrant` |

### Was das Profil ablehnt {#what-the-profile-refuses}

Jeweils beim Start, aus `authn-bridge check`:

```
authn-bridge: client "efp": ssh_validity = 24h0m0s: longer than the ssh_ca validity, 12h0m0s
authn-bridge: client "efp": ssh_extensions: "no-touch-required" is not one of permit-X11-forwarding, permit-agent-forwarding, permit-port-forwarding, permit-pty, permit-user-rc
authn-bridge: client "src": ssh_source_address: "192.0.2.1/24" has bits set under its mask: 192.0.2.0/24?
authn-bridge: client "x": ssh_principal_claim, ssh_extensions, ssh_source_address, ssh_validity and ssh_domain_grants shape SSH certificates: they need ssh_certificates = true
```

`no-touch-required` wird nicht angeboten: Es verzichtet auf den Anwesenheitstest des
**eigenen** Sicherheitsschlüssels der Person, und den hat der Anbieter nicht für alle
Personen eines Clients wegzugeben.

Ein Domain-Grant wird an der Syntax der Spezifikation gemessen, dann an der eigenen Richtlinie
dieses Anbieters: Kleinschreibung, mindestens zwei Labels und ein Platzhalter nur unterhalb einer
registrierbaren Domain. Was rechts vom letzten Platzhalter fest bleibt, darf kein
öffentliches Suffix sein (die Public Suffix List): `*.ac.uk` würde jeder
Einrichtung darunter Zugang gewähren.

```
authn-bridge: client "efp": ssh_domain_grants: "*.ac.uk": a wildcard over the public suffix "ac.uk" grants every domain under it
authn-bridge: client "efp": ssh_domain_grants: "Login.hpc.example.org": written in lower case, as hosting entities' domains are compared
authn-bridge: client "efp": ssh_domain_grants: "login.hpc.*": sshcert: invalid domain pattern: pattern "login.hpc.*" has a wildcard in its rightmost label
```

### Von einem Standort aus vertrauen {#trusting-it-from-a-site}

`GET /ssh/config` veröffentlicht den CA-Schlüssel in der Form, in der EFP seinen eigenen veröffentlicht; ein
Standort folgt also den Vertrauensanweisungen von EFP mit der URL dieses Anbieters:

```
$ curl -s http://127.0.0.1:28473/ssh/config
{"PublicKey":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHFRUBlwxcGmmqW2lBI9bJyN4LL0/4U0NZwOOwBFPWw9"}
```

```sh
curl -s https://login.example.org/ssh/config | jq -r '.PublicKey' > /etc/ssh/bridge-ssh-ca.pub
echo "TrustedUserCAKeys /etc/ssh/bridge-ssh-ca.pub" >> /etc/ssh/sshd_config
```

sshd ignoriert den Domain-Grant. Der Standort filtert danach mit einem
`AuthorizedPrincipalsCommand`: [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}),
das ein Zertifikat ablehnt, dessen Grant den Host nicht nennt, und ebenso eines ganz ohne
Grant. Die CA steht nicht im OpenID-Discovery-Dokument: Keine OpenID-Connect-Metadaten
nennen eine SSH-CA.

Was sich von der eigenen CA von EFP weiterhin unterscheidet: Der Principal ist die `subject-id`,
die die Einrichtung der Person freigegeben hat, kein MyAccessID-Bezeichner; die
Gruppenerweiterung ist vorhanden, wenn das Token Gruppen trägt; und **es gibt eine KRL**,
`GET /ssh/krl`, die die Zertifikate der hier deaktivierten Personen aufführt.

## X.509-Client-Zertifikate für NFS über TLS {#x509-client-certificates-for-nfs-over-tls}

NFS über TLS (RFC 9289) kann den Client anhand seines Zertifikats benennen.

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

x509_ca {
  key_file  = "/var/lib/authn-bridge/nfs-ca/ca.key"   # authn-bridge keygen --x509-ca /var/lib/authn-bridge/nfs-ca
  cert_file = "/var/lib/authn-bridge/nfs-ca/ca.crt"   # what go-fileshare trusts
  validity  = "12h"                                   # the default; a week at most
}

client "nfs" {
  device            = true
  x509_certificates = true
}
```

`authn-bridge nfs-cert --issuer ... --client nfs` erzeugt einen P-256-Schlüssel auf dem
Rechner der Person, sendet eine Zertifikatsanforderung per POST an `/x509/cert`, mit einem Token
des Scopes `nfs`, und schreibt das Zertifikat und den Schlüssel. Der CA-Schlüssel muss
P-256 sein und sein Zertifikat das einer CA, die Zertifikate und CRLs signiert.

**Was das Zertifikat sagt.** Subject und Erweiterungen der Anforderung werden
ignoriert: Zertifiziert wird die Person des Tokens, nicht das, was sie verlangt hat.

- Die Person, `user@domain`, als **ein** subjectAltName `otherName`
  `1.3.6.1.4.1.2238.1.1.1` mit einem UTF8String, wo FreeBSDs
  `rpc.tlsservd -u` ihn liest. Ein Benutzername ohne `@` oder unter drei Bytes wird
  abgelehnt.
- Jede Gruppe als URI-Name daneben:
  `tag:go-authn.github.io,2026:group:<the group, percent-encoded>`.
- Der CN ist der Benutzername; ab 64 Zeichen ist das Subject leer und der
  subjectAltName kritisch (RFC 5280).
- Nur Client-Authentifizierung, und ein CRL-Verteilungspunkt:
  `<issuer>/x509/crl`.
- Gültig ab vor fünf Minuten bis `validity`, zum Ende der Sitzung beim IdP oder des eigenen
  Zertifikats der CA, je nachdem, was zuerst endet.
- Ein P-256- oder RSA-Schlüssel (2048 Bit und mehr) und eine damit signierte Anforderung.

{{< callout type="warning" >}}
**Ein Zertifikat benennt die Maschine, nicht die Person, die sie benutzt**

RFC 9289: Der Server „cannot utilize the remote TLS peer identity to
authenticate RPC users“. Linux setzt das Client-Zertifikat pro Mount, sodass
alle, die diesen Mount nutzen, die Person sind, die es nennt. Das ist für eine Maschine
gedacht, die eine Person nutzt, und `authn-bridge nfs-cert` sagt das.
{{< /callout >}}

## Eine Zertifikatsanforderung, die über eine Deaktivierung hinweg offen gehalten wird {#a-certificate-request-held-open-across-a-disabling}

Das Token wird geprüft, wenn die Anforderung beginnt, und der Body danach gelesen, in
welchem Tempo auch immer der Client ihn sendet. Daher wird ein Zertifikat zuerst festgehalten, und dann
werden das Token und die Person erneut geprüft: Wurde die Person in der Zwischenzeit deaktiviert oder
das Token widerrufen, wird das gerade festgehaltene Zertifikat widerrufen, und die
Antwort ist `401`. Entweder hat der Widerruf das Zertifikat gesehen, oder das Zertifikat
sieht den Widerruf.
