---
title: "sshcert-authorize"
linkTitle: "sshcert-authorize"
weight: 10
description: "Was sshcert-authorize prüft, wenn sshd es als AuthorizedPrincipalsCommand ausführt, was es ablehnt und warum auch ein Zertifikat ohne Domain-Grant abgelehnt wird."
tags: [sshcert, ssh, sshd, eurohpc]
---

`sshd` fragt es bei jeder Anmeldung mit Zertifikat, welche Principals sich an dem
Konto anmelden dürfen. Es antwortet nur dann mit den Principals des Kontos, wenn der
Domain-Grant des Zertifikats diesen Host nennt; andernfalls antwortet es nichts, und
`sshd` lehnt das Zertifikat ab. Es übernimmt die Argumente, Flags, Ausgabe und das
Log-Format von GÉANTs `ssh-cert-authorize` und unterscheidet sich darin, was es ablehnt.

## Wie sshd es aufruft {#how-sshd-calls-it}

```
# /etc/ssh/sshd_config
TrustedUserCAKeys /etc/ssh/efp-ssh-ca.pub
AuthorizedPrincipalsCommand /usr/local/bin/sshcert-authorize %u %k
AuthorizedPrincipalsCommandUser nobody
```

```sh
install -o root -g root -m 0755 sshcert-authorize /usr/local/bin/
echo login.example.org > /etc/ssh/cert-allowed-domain.conf
```

und, für jedes lokale Konto, die Principals, die sich daran anmelden dürfen, einer pro
Zeile, in `/etc/ssh/auth_principals/<account>`. sshd führt den Befehl nur von einem Pfad
aus, der root gehört und für niemanden sonst beschreibbar ist.

`%u` ist das Konto, an dem die Anmeldung erfolgt. `%k` ist das Zertifikat, base64; eine
ganze Zeile `ssh-...-cert-v01@openssh.com BASE64` wird ebenfalls gelesen, und fehlt das
Argument, wird das Zertifikat von der Standardeingabe gelesen. Ein drittes Argument,
wenn es angegeben ist (das `%t` von sshd), muss der Typ des Zertifikats sein, sonst wird das
Zertifikat abgelehnt.

| Exit | gibt aus | sshd |
|---|---|---|
| `0` | die Principals des Kontos, einer pro Zeile | lässt das Zertifikat zu, wenn einer seiner Principals darunter ist |
| `1` | nichts | lehnt es ab |
| `2` | nichts | lehnt es ab: Die Argumente waren falsch |

{{< callout type="info" >}}
**Es prüft weder die Signatur noch die CA noch die Gültigkeitsdaten**

Nichts in dem Befehl prüft die Signatur des Zertifikats oder sein
Gültigkeitsfenster: Das tut sshd, das der CA über `TrustedUserCAKeys` vertraut.
Der Befehl entscheidet eine einzige Frage: ob das Zertifikat für diesen Host und
dieses Konto bestimmt ist.
{{< /callout >}}

## Was es ablehnt {#what-it-refuses}

In der Reihenfolge, in der es prüft:

1. einen Kontonamen, der leer, `.` oder `..` ist oder `/`, `\` oder ein NUL enthält;
2. einen Host ohne konfigurierte Domain oder einen, der kein gültiger Hostname ist;
3. ein Zertifikat, das sich nicht parsen lässt, einen bloßen Schlüssel oder ein Host-Zertifikat;
4. ein `%t`, das nicht der Typ des Zertifikats ist;
5. mit `--krl` ein Zertifikat, das die Liste widerruft, oder **jedes** Zertifikat, wenn
   die Liste nicht gelesen werden kann oder abgelaufen ist;
6. einen Domain-Grant, der vorhanden und fehlerhaft ist, **unabhängig von den Flags**;
7. **überhaupt keinen Domain-Grant**, sofern nicht `--allow-no-grant` gesetzt ist;
8. einen Grant, von dessen Mustern keines auf einen der Namen des Hosts passt;
9. ein Konto ohne Principals-Datei oder mit einer leeren.

Die Namen des Hosts sind `--domain` oder die Variable, die `--domain-env` nennt, oder die
Zeilen von `--domain-file` (Leerzeilen und `#`-Kommentare werden ignoriert; mehrere Zeilen
sind mehrere Namen, von denen jeder passen darf).

Mit Zertifikaten, die von einer Test-CA für das Konto `alice` signiert sind, dessen
Principals-Datei `a1b2c3@univ-example.example` aufführt, auf einem Host namens
`login.hpc.example.org`:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
a1b2c3@univ-example.example
```

Die letzte Zeile ist die Antwort, die sshd liest; die Zeilen davor sind das Log, hier auf
der Standardfehlerausgabe. Ein Zertifikat, das anderen Hosts gewährt wurde:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-other-cert.pub)"
INFO: action=cert_processed serial=1003 key_id="a1b2c3@univ-example.example other host" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=denied user=alice domain=login.hpc.example.org reason="domain not granted" grant=["*.elsewhere.example.net"] serial=1003 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
```

Ein Zertifikat ohne Grant:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=denied user=alice domain=login.hpc.example.org reason="no domain grant" serial=1002 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
```

Ein Konto ohne Principals-Datei und ein bloßer Schlüssel:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals bob "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=denied user=bob domain=login.hpc.example.org reason="no principals file for the user" serial=1001 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice.pub)"
WARNING: action=denied user=alice domain=login.hpc.example.org reason="a ssh-ed25519 key, not a certificate"
```

Jeder dieser Aufrufe endete mit `1` und gab nichts auf der Standardausgabe aus.

## Warum ein Zertifikat ohne Grant abgelehnt wird {#why-a-certificate-with-no-grant-is-refused}

GÉANTs `ssh-cert-authorize` lässt ein Zertifikat ohne Domain-Grant durch
(„might be valid for non-domain-based auth“), ebenso eines, dessen Grant es nicht
parsen kann oder das leer ist. Dann lässt eine Site, die in `TrustedUserCAKeys`
**zwei** CAs vertraut (der der Föderation und ihrer eigenen für das Personal, oder einer
Test-CA), ein Zertifikat der zweiten CA auf jedem Host herein, für jeden Principal in einer
Principals-Datei, ganz ohne Domain-Prüfung. Der Domain-Filter ist nur dann ein Filter,
wenn ein Zertifikat, das nicht sagt, wo es verwendet werden darf, abgelehnt wird.

Eine Site, die GÉANTs Verhalten wirklich will, sagt das, und der Befehl protokolliert
jedes Mal, wenn er es anwendet:

```
$ sshcert-authorize --syslog=false --allow-no-grant --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=no_grant_allowed user=alice domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
a1b2c3@univ-example.example
```

Selbst dann wird ein Grant, der vorhanden, aber fehlerhaft ist, abgelehnt.

## `--krl` {#krl}

`RevokedKeys` ist sshds eigene Prüfung, die vor dem Befehl erfolgt, für jeden Schlüssel
und jedes Zertifikat, und sie widerruft auch einen CA-Schlüssel; bevorzugen Sie sie.
`--krl FILE` prüft eine OpenSSH-KRL innerhalb des Befehls und ergänzt, was sshd nicht
tut: Es lehnt **jedes** Zertifikat ab, sobald die Liste abgelaufen ist (ihre Erweiterung
`expires@go-authn.github.io`, die sshd ignoriert), und jedes Zertifikat, wenn die Liste
nicht gelesen werden kann. Eine Liste ohne Ablaufdatum wird ohne eines verwendet.

Drei Aufrufe: mit der KRL, die [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) schreibt,
zuerst eine aktuelle, dann die fail-closed Liste, die es schreibt, wenn die Liste des Ausstellers
[verfällt]({{< relref "/authn-revokd/lapse.md" >}}); und zuletzt mit `--krl` auf eine Datei, die
es nicht gibt:

```
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
a1b2c3@univ-example.example
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=denied user=alice domain=login.hpc.example.org reason="certificate revoked" serial=1001 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
$ sshcert-authorize --syslog=false --krl missing.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=denied user=alice domain=login.hpc.example.org reason="KRL unreadable: open missing.krl: no such file or directory" serial=1001 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
```

Der zweite Aufruf wird abgelehnt, weil die fail-closed Liste den **CA-Schlüssel** des Zertifikats
widerruft: Die Prüfung umfasst den eigenen Schlüssel des Zertifikats, seine Seriennummer
und Key-ID sowie den Schlüssel, der es signiert hat. Der dritte wird abgelehnt, weil die Liste
nicht gelesen werden kann: Keine Liste gilt nicht als „nichts widerrufen“.

## Flags {#flags}

```
$ sshcert-authorize -help
usage: sshcert-authorize [flags] USER [CERTIFICATE [KEYTYPE]]

An sshd AuthorizedPrincipalsCommand (%u %k) that refuses a certificate whose
ssh-domain-grant@core.aai.geant.org extension does not grant this host, or that has none.

  -allow-no-grant
    	let in a certificate with no domain grant (GÉANT's behaviour); a malformed grant is still refused
  -debug
    	log details
  -domain string
    	the host's domain (overrides --domain-env and --domain-file)
  -domain-env string
    	environment variable holding the host's domain
  -domain-file string
    	file holding the host's domain, one name per line (default "/etc/ssh/cert-allowed-domain.conf")
  -extension string
    	name of the domain-grant extension (default "ssh-domain-grant@core.aai.geant.org")
  -krl string
    	refuse certificates this OpenSSH KRL revokes, and every certificate once it has expired or cannot be read
  -principals-dir string
    	directory of principals files, one per user (default "/etc/ssh/auth_principals")
  -syslog
    	log to syslog, facility AUTH (--syslog=false: to stderr) (default true)
  -version
    	print the version and exit
```

**Logs** sind `key=value`-Zeilen (`action=cert_processed`, `action=denied`,
`action=authorized`, mit `serial` und `ca_fingerprint`), standardmäßig an syslog,
Facility AUTH. sshd verwirft die Standardfehlerausgabe des Befehls, lassen Sie syslog im
Produktivbetrieb also eingeschaltet; `--debug` schreibt zusätzlich alles auf die
Standardfehlerausgabe. Ein Wert, der vom Client kommt, etwa der Kontoname, wird in
Anführungszeichen gesetzt, wenn er ein Leerzeichen, `=`, ein Anführungszeichen oder ein
Steuerzeichen enthält, sodass er kein Log-Feld fälschen kann.

**`-version`** gibt die Modulversion aus, in einem Release-Binary ebenso wie in einem,
das mit `go install` gebaut wurde:

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.5
$ sshcert-authorize -version
sshcert-authorize v0.1.5
```

Vor v0.1.5 gab ein Binary aus `go install` `sshcert-authorize dev` aus.
