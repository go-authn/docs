---
title: "Die Konfiguration"
linkTitle: "Konfiguration"
weight: 20
description: "Die revokd.hcl von authn-revokd: woher die Listen kommen, von wem sie signiert sein müssen, in welche Dateien sie geschrieben werden, und der Spiegel."
tags: [authn-revokd, konfiguration]
---

Eine Datei, standardmäßig `/etc/authn-revokd/revokd.hcl` (`-config` nennt eine andere).
Sie wird einmal gelesen, beim Start.

```hcl
state_dir = "/var/lib/authn-revokd/state"   # the verified copies: what orders the next list
refresh   = "1m"

source "univ-a-ssh" {
  url    = "https://login.univ-a.example/ssh/krl"    # and .../ssh/krl.sig beside it
  ssh_ca = "/etc/authn-revokd/ca/univ-a-ssh.pub"     # what the list must be signed by
}
source "univ-b-ssh" {
  url    = "http://mirror.cluster.local:8080/univ-b-ssh"   # a mirror: plain http is fine
  ssh_ca = "/etc/authn-revokd/ca/univ-b-ssh.pub"
}
source "univ-a-x509" {
  url     = "https://login.univ-a.example/x509/crl"
  x509_ca = "/etc/authn-revokd/ca/univ-a-x509.pem"
}

output "sshd" {                              # sshd_config: RevokedKeys /var/lib/authn-revokd/sshd.krl
  path    = "/var/lib/authn-revokd/sshd.krl"
  sources = ["univ-a-ssh", "univ-b-ssh"]     # merged into one file
}
output "tls" {                               # nginx: ssl_crl /var/lib/authn-revokd/univ-a.crl
  path    = "/var/lib/authn-revokd/univ-a.crl"
  sources = ["univ-a-x509"]
  format  = "pem"
}

# listen = "127.0.0.1:8080"                  # serve the verified lists: a mirror
```

## Die Schlüssel {#the-keys}

| Schlüssel | Standard | |
|---|---|---|
| `state_dir` | | erforderlich, absolut; das Verzeichnis wird mit `0700` angelegt, falls es fehlt |
| `refresh` | `1m` | wie oft jede Quelle abgerufen wird, eine Sekunde oder mehr; jede Wartezeit schwankt um ein Zehntel nach oben oder unten, damit eine Flotte nicht im Gleichschritt bleibt |
| `listen` | | `host:port`: die geprüften Listen bereitstellen, ein Spiegel; mit `-once` ignoriert |

**`source "<name>"`**: eine Liste. Der Name besteht aus Buchstaben, Ziffern, `.`, `_` und
`-`, beginnt nicht mit einem Punkt, höchstens 64 Zeichen: Er benennt eine Datei im
Zustandsverzeichnis und einen Pfad des Spiegels.

| Schlüssel | |
|---|---|
| `url` | `https://`, `http://` oder `file://`; die Signatur einer KRL wird von derselben URL mit angehängtem `.sig` abgerufen |
| `ssh_ca` | der öffentliche Schlüssel der SSH-CA, eine `authorized_keys`-Zeile: eine KRL-Quelle. Ein Zertifikat wird hier abgelehnt |
| `x509_ca` | das PEM-Zertifikat der CA: eine CRL-Quelle |
| `max_age` | lehnt zusätzlich zu ihrem eigenen Ablauf eine Liste ab, die vor längerer Zeit als dieser ausgestellt wurde; abgelehnt bei einer Quelle, die eine CRL-Ausgabe speist |
| `revoke_keys` | erlaubt der Liste dieser Quelle, in einer mit anderen Quellen geteilten Ausgabe **einfache Schlüssel** zu widerrufen; nur KRL-Quellen |

**`output "<name>"`**: eine Datei, die ein Server liest.

| Schlüssel | |
|---|---|
| `path` | absolut; neben sich selbst geschrieben und darüber umbenannt |
| `sources` | KRL-Quellen, zu einer Datei zusammengeführt; oder genau eine CRL-Quelle |
| `format` | `der` (der Standard) oder `pem`; nur CRL-Ausgaben |
| `on_change` | ein Befehl und seine Argumente, ausgeführt, nachdem sich die Datei geändert hat, und erneut bei jeder Synchronisierung, bis er gelingt |

## Eine KRL für mehrere CAs {#one-krl-for-several-cas}

`RevokedKeys` nimmt vor OpenSSH 10.3 eine einzige Datei, daher werden die KRL-Quellen einer
Ausgabe zusammengeführt, und **jede Liste behält ihre volle Wirkung auf ihre eigene CA und
keine auf eine andere**:

- **Behalten:** ihre Seriennummern und Schlüssel-IDs, ihre Abschnitte, die keine CA nennen (auf ihre
  eigene beschränkt), und ihr eigener CA-Schlüssel, der alle ihre Zertifikate widerruft.
- **Weggelassen und protokolliert:** der Abschnitt einer anderen CA und der Schlüssel einer anderen CA.
- **Einfache Benutzerschlüssel** werden weggelassen, wenn die Ausgabe mehr als eine Quelle hat,
  es sei denn, die Quelle hat `revoke_keys = true`. Eine KRL kann einen Schlüssel nicht auf eine
  CA beschränken: sshd prüft den eigenen Schlüssel eines Zertifikats gegen die Datei, gleich wer es signiert hat;
  ein Schlüssel, den eine CA nennt, würde die Person, die ihn hält, also unter jeder CA der Datei aussperren.
  Eine Ausgabe mit einer Quelle behält sie.

Jede Liste wird zuerst allein zusammengeführt. Eine, die sich nicht zusammenführen lässt, schlägt **nur für
ihre eigene CA** geschlossen fehl (fail closed); die zusammengeführte Datei läuft mit der ersten ihrer aktuellen
Eingaben ab, sodass ein Leser, der den Ablauf prüft, sieht, wenn authn-revokd anhält.

## Der Spiegel {#the-mirror}

Mit `listen` stellt authn-revokd bereit, was es hält, aus dem Speicher, nie aus den
Dateien, deren Schreiben gerade halb fertig sein kann:

| | |
|---|---|
| `GET /<source>` | die Liste, mit einem `ETag`; `If-None-Match` antwortet `304` |
| `GET /<source>.sig` | die Signatur einer KRL; `If-Match` auf ein anderes ETag antwortet `412` |
| `GET /healthz` | `200 ok` oder `503`, mit Nennung jeder Quelle ohne aktuelle Liste und jeder fehlgeschlagenen Ausgabe |

```
$ curl -s http://127.0.0.1:28474/healthz
ok
$ curl -s -D - -o /dev/null http://127.0.0.1:28474/bridge-ssh
HTTP/1.1 200 OK
Cache-Control: max-age=30
Content-Type: application/octet-stream
Etag: "dfd84d8513eb48d07ed72f2110316858"
Date: Mon, 26 Oct 2026 11:27:10 GMT
Content-Length: 130

$ curl -s -o /dev/null -w "%{http_code}\n" -H 'If-Match: "stale"' http://127.0.0.1:28474/bridge-ssh.sig
412
```

Eine CRL-Quelle hat kein `.sig` (`404`). Spiegel lassen sich verketten: Die Quelle eines Spiegels kann
ein anderer Spiegel sein, da jede Liste sich selbst prüft. Ein langsamer Upstream blockiert
die Antworten des Spiegels nie.

## Was beim Start abgelehnt wird {#what-is-refused-at-start}

Jeder dieser Fälle endet mit `2`, bevor etwas abgerufen wird:

```
authn-revokd: v/relative-state.hcl: state_dir "state": an absolute path
authn-revokd: v/refresh.hcl: refresh "500ms": a duration of a second or more
authn-revokd: v/both-ca.hcl: source "bridge-ssh": ssh_ca and x509_ca together: one source is one list
authn-revokd: v/sig-name.hcl: source "bridge-ssh.sig": a name that ends in .sig, or healthz, is a path the mirror already serves
authn-revokd: v/mixed.hcl: output "sshd" mixes KRL and CRL sources
authn-revokd: v/krl-format.hcl: output "sshd": format is for CRL outputs; a KRL is what sshd reads
authn-revokd: v/revoke-keys-crl.hcl: source "bridge-x509": revoke_keys is for a KRL source (ssh_ca): a CRL revokes its own CA's certificates only
```

Ebenso eine Konfiguration, die nicht vorhanden ist:

```
$ authn-revokd -config nowhere.hcl -once
authn-revokd: nowhere.hcl: no such file or directory
```

Vor v0.6.2 war es die Meldung des HCL-Parsers:
`nowhere.hcl: <nil>: Failed to read file; The configuration file "nowhere.hcl" could not be read.`

Eine CRL-Ausgabe nimmt außerdem eine einzige Quelle (ein TLS-Server liest eine CRL pro Aussteller), und
eine CRL-Quelle mit `max_age` wird abgelehnt, weil nichts es durchsetzen könnte:

```
authn-revokd: v/crl-maxage.hcl: output "tls": source "bridge-x509" has a max_age, which a CRL output cannot enforce: the TLS server judges a CRL by its nextUpdate alone. Remove max_age, or ask the CA for a closer nextUpdate
```

Ein TLS-Server, der eine CRL geladen hat, hält sie bis zu ihrem `nextUpdate` im Speicher,
was auch immer authn-revokd schreibt.

**Das Zustandsverzeichnis** unterliegt der StrictModes-Regel von sshd. Wer seine Dateien
ersetzen oder entfernen kann, entscheidet, welche Liste als nächste kommt, und ein geleerter Zustand
lässt eine wieder eingespielte ältere Liste herein. Es darf daher kein symbolischer Link sein, nicht für
Gruppe oder andere beschreibbar und niemandem gehören außer dem Benutzer von authn-revokd oder root. Diese Fälle enden
mit `1`:

```
authn-revokd: state_dir /tmp/authn/revokd/state-wide is writable by its group or by others (mode -rwxrwxrwx): whoever can write there decides which list comes next
authn-revokd: state_dir /tmp/authn/revokd/state-link is a symbolic link (L---------): whoever owns it decides where the state is; name the directory itself
```
