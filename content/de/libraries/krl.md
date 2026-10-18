---
title: "krl – OpenSSH-Sperrlisten für Schlüssel"
linkTitle: "krl"
weight: 110
description: "go-authn/krl parst, baut, führt zusammen und prüft OpenSSH-KRLs so, wie sshd sie liest, mit einer Ablauf-Erweiterung, beurteilt von ssh-keygen."
tags: [bibliotheken, widerruf, ssh]
---

**Ist dieses SSH-Zertifikat oder dieser Schlüssel widerrufen – so, wie sshd antworten würde?** Das
Binärformat von OpenSSHs `PROTOCOL.krl`, die Liste, die `sshd` über
`RevokedKeys` lädt und `ssh-keygen -k` schreibt. `golang.org/x/crypto/ssh` bietet
dafür keine Unterstützung.

```sh
go get github.com/go-authn/krl@v0.6.1
```

`IsRevoked` folgt `ssh_krl_check_key` in OpenSSHs `krl.c`: Ein Zertifikat
ist widerrufen, wenn seine Seriennummer oder seine Schlüssel-ID unter der CA widerrufen ist, die es signiert hat, oder
unter irgendeiner CA, wenn der Schlüssel seiner CA widerrufen ist oder wenn sein eigener Schlüssel als
Blob oder per SHA-1- oder SHA-256-Fingerabdruck widerrufen ist. Seriennummer 0 – was eine CA schreibt, wenn sie
keine angibt – wird nie per Seriennummer widerrufen.

## Beispiel {#example}

```go
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"time"

	"github.com/go-authn/krl"
	"golang.org/x/crypto/ssh"
)

func main() {
	ca := signer()
	user := signer()

	// The issuer: certificate 42 is revoked, and so is everything for key ID "alice".
	b := krl.NewBuilder(7, "revoked by the bridge")
	b.RevokeSerial(ca.PublicKey(), 42)
	b.RevokeKeyID(nil, "alice") // nil: under any CA
	b.SetExpires(time.Now().Add(time.Hour))
	data, err := b.Marshal(time.Now())
	if err != nil {
		panic(err)
	}

	// The server: parse the list, then ask about each certificate.
	k, err := krl.Parse(data)
	if err != nil {
		panic(err)
	}
	fmt.Println("version", k.Version, "signed", k.Signed, "expires set", !k.Expires.IsZero())
	for _, c := range []struct {
		serial uint64
		id     string
	}{{42, "bob"}, {43, "bob"}, {44, "alice"}} {
		fmt.Println(c.serial, c.id, k.IsRevoked(certificate(ca, user.PublicKey(), c.serial, c.id)))
	}
}

func signer() ssh.Signer {
	_, priv, _ := ed25519.GenerateKey(rand.Reader)
	s, _ := ssh.NewSignerFromKey(priv)
	return s
}

func certificate(ca ssh.Signer, key ssh.PublicKey, serial uint64, id string) *ssh.Certificate {
	c := &ssh.Certificate{
		Key: key, Serial: serial, KeyId: id, CertType: ssh.UserCert,
		ValidPrincipals: []string{id}, ValidBefore: ssh.CertTimeInfinity,
	}
	if err := c.SignCert(rand.Reader, ca); err != nil {
		panic(err)
	}
	return c
}
```

```
version 7 signed false expires set true
42 bob true
43 bob false
44 alice true
```

Dieselbe Liste und dieselben Zertifikate, in Dateien geschrieben, erhalten dieselben drei Antworten
von `ssh-keygen -Q -f list.krl` aus OpenSSH 10.3p1: `REVOKED`, `ok`,
`REVOKED`.

## Ablauf: `expires@go-authn.github.io` {#expiry-expiresgo-authngithubio}

Eine KRL hat ein Erzeugungsdatum und eine Version, und nichts sagt, wann sie aufhört,
aktuell zu sein; eine veraltete Kopie lässt sich also nicht von einer frischen unterscheiden.
`Builder.SetExpires` schreibt diesen Zeitpunkt in einen Erweiterungsabschnitt namens
`ExtensionExpires`, **nicht kritisch**, sodass `sshd` und `ssh-keygen` die Liste laden
und ihn ignorieren; `Parse` liest ihn in `KRL.Expires` ein.

{{< callout type="warning" >}}
**Keine Signaturen**

OpenSSH hat nie eine Möglichkeit angeboten, den Signaturabschnitt einer KRL zu schreiben, und prüft ihn
nicht mehr. `Parse` überspringt einen solchen und setzt `Signed`, was nichts über die
Echtheit aussagt; `Builder` schreibt nie einen. Die Integrität der Liste und damit die ihres
Ablaufs stammt aus ihrem Transport – HTTPS von einem authentifizierten Server – oder
aus einer abgetrennten SSHSIG-Signatur, die der Aufrufer prüft, was dieses Paket
nicht tut.
{{< /callout >}}

## Zusammenführen: eine Datei für sshd {#merging-one-file-for-sshd}

`sshd` las bis OpenSSH 10.3 eine einzige `RevokedKeys`-Datei, daher braucht ein Server,
der mehreren CAs vertraut, deren Listen in einer. `Builder.Merge` fügt jeden
Widerruf einer geparsten Liste hinzu. `Builder.MergeCA(k, ca, others...)` behält den Abschnitt von `k`
für `ca`, dessen Abschnitte für beliebige CAs, neu auf `ca` beschränkt, sowie dessen explizite Schlüssel
und Fingerabdrücke, und lässt – mitgezählt – Abschnitte für eine andere CA sowie
Schlüssel oder Fingerabdrücke weg, die eine der `others` bezeichnen. `MergeCAWith` mit
`MergeOptions{DropKeys: true}` lässt außerdem jeden expliziten Schlüssel außer dem
eigenen von `ca` weg, für eine Liste, der nicht für die Benutzer jeder CA vertraut wird: Ein widerrufener Benutzerschlüssel
sperrt dieses Konto unter jeder CA der zusammengeführten Datei aus, weil `sshd` den
eigenen Schlüssel eines Zertifikats prüft, wer auch immer es signiert hat.

## Was es ablehnt und warum {#what-it-refuses-and-why}

`Parse` lehnt ab, was `ssh-keygen` und `sshd` ablehnen: eine falsche Magic-Nummer oder Formatversion,
abgeschnittene oder überzählige Daten, einen unbekannten Abschnitt oder Zertifikats-Unterabschnitt,
eine unbekannte, als kritisch markierte Erweiterung, einen CA-Schlüssel, den OpenSSH nicht
parsen kann, Seriennummer 0, einen umgekehrten Seriennummernbereich, eine Bitmap, die größer ist, als OpenSSH liest,
oder eine, die über 2^64−1 hinaus überläuft. Es lehnt auch einen fehlerhaften oder wiederholten Ablauf ab:
Als fehlend gelesen, würde er eine Liste, die verfallen soll, in eine verwandeln, die es nie tut.

`Builder` lehnt – bei `Marshal`, das die erste ungültige Anforderung zurückgibt –
Seriennummer 0 ab, einen Bereich, dessen unteres Ende 0 ist oder über seinem oberen Ende liegt, eine Schlüssel-ID oder einen
Kommentar mit einem NUL, ein Zertifikat, wo ein CA-Schlüssel erwartet wird, und
einen Ablauf vor dem Erzeugungsdatum.

**Ein bewusster Unterschied.** Für viele dünn besetzte, nah beieinanderliegende Seriennummern
schreibt `ssh-keygen -k` eine Bitmap, die breiter ist, als sein eigener Leser akzeptiert, und
lehnt dann seine eigene Datei ab (*bignum is too large*). `Parse` lehnt diese Datei ebenfalls ab,
wie `sshd` es täte; `Builder` beginnt einen neuen Abschnitt, bevor eine Bitmap so
breit wird, sodass das, was er schreibt, immer lesbar ist.

`Parse` belegt Speicher im Verhältnis zu dem, was die Liste widerruft, wie OpenSSH: Eine KRL
sollte aus einer Quelle stammen, der man vertraut, keine riesige zu schicken.

## Wogegen es geprüft wird {#what-it-is-checked-against}

**OpenSSHs `ssh-keygen`**, auf den Linux- und macOS-Lanes, wo
`KRL_REQUIRE_SSHKEYGEN=1` ein fehlendes zum Fehlschlag macht (Windows führt nur die
reinen Go-Tests aus):

- eine KRL, geschrieben von `ssh-keygen -k`, mit jeder Seriennummern-Kodierung, Schlüssel-IDs, drei
  CAs plus „any CA“, expliziten Schlüsseln und einem widerrufenen CA-Schlüssel: `IsRevoked` antwortet
  wie `ssh-keygen -Q` für 250 Zertifikate, und `Builder` schreibt, mit denselben
  Widerrufen versorgt, **dieselben Bytes**;
- 40 zufällige Seriennummernmengen, von beiden geschrieben: byte-identisch, und dieselben Antworten
  für etwa 9000 Zertifikate;
- jede Kürzung und etwa 1400 Ein-Byte-Beschädigungen: `Parse` lehnt
  genau das ab, was `ssh-keygen` ablehnt;
- die Ablauf-Erweiterung lädt in `ssh-keygen`, und derselbe Abschnitt, als
  kritisch markiert, wird abgelehnt;
- zusammengeführte Listen widerrufen genau das, was eine ihrer Quellen widerruft.

`FuzzParse`, mit KRLs gespeist, die `ssh-keygen` geschrieben hat, und `FuzzBuilder` laufen in der CI.
Die Coverage-Untergrenze liegt bei 100 %, gemessen auf der Linux-Lane, wo `ssh-keygen`
vorhanden ist.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/krl@v0.6.1](https://pkg.go.dev/github.com/go-authn/krl@v0.6.1)
