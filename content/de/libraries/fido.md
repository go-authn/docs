---
title: "fido – mit einem Sicherheitsschlüssel sprechen"
linkTitle: "fido"
weight: 30
description: "go-authn/fido spricht CTAPHID und CTAP2 mit einem Sicherheitsschlüssel über jeden 64-Byte-Transport: Handshake, Registrierung, Assertion und PIN, in reinem Go."
tags: [bibliotheken, fido, faktoren]
---

**Wie spricht man mit einem Sicherheitsschlüssel?** Das FIDO-Protokoll zwischen Client und Authenticator
– das CTAPHID-Framing, der Kanal-Handshake und die CTAP2-Befehle, die
ein Credential registrieren, eine Signatur anfordern und eine PIN gegen ein Token tauschen – in
reinem Go, auf jedem Betriebssystem.

```sh
go get github.com/go-authn/fido@v0.6.2
```

Nichts hier ist plattformspezifisch. Ein `Transport` bewegt 64-Byte-Reports zu und
von einem Authenticator und sagt, wie das Gerät heißt; woher diese Reports
kommen – IOKit unter macOS, hidraw unter Linux, WebHID in einem Browser –, ist das Paket
von jemand anderem. Alles darüber ist hier:

| | |
|---|---|
| `Open(ctx, t)` | der `INIT`-Handshake auf dem Broadcast-Kanal; gibt einen `*Key` mit eigenem Kanal zurück. Der `Key` besitzt `t`: `Close` schließt ihn, und ein fehlgeschlagenes `Open` ebenso |
| `Key.Ping`, `Key.Wink` | ein Hin und Zurück und ein Blinken – der billigste Weg zu fragen: *Welcher dieser Schlüssel ist dieser hier?* |
| `Key.GetInfo` | Versionen, Erweiterungen, AAGUID, Optionen, PIN-Protokolle |
| `Key.MakeCredential`, `Key.GetAssertion` | registrieren und signieren; `ParseAuthData` liest die Authenticator-Daten, und `AuthData.PublicKey` macht aus einem P-256-COSE-Schlüssel einen `*ecdsa.PublicKey` |
| `Key.PINRetries`, `Key.KeyAgreement`, `Key.PINToken` | `authenticatorClientPIN`, beide PIN/UV-Auth-Protokolle |
| `Split`, `NewReassembler`, `ParseInit`, `Key.CBOR` | das Framing, exportiert für alle, die einen Schlüssel auf andere Weise ansteuern |

`AuthData.PublicKey` ist eine Umwandlung, keine Prüfung: Welche Algorithmen
zählen und was mit einem Signaturzähler geschieht, der rückwärts gelaufen ist, ist Sache des
Aufrufers. [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) ist ein solcher
Aufrufer.

## Beispiel {#example}

Das Framing allein, ohne Schlüssel: eine Nachricht, in Reports zerlegt und wieder
zusammengesetzt.

```go
package main

import (
	"bytes"
	"fmt"

	"github.com/go-authn/fido"
)

func main() {
	// A 200-byte ping, cut into the 64-byte reports a key reads...
	payload := bytes.Repeat([]byte{0xA5}, 200)
	reports, err := fido.Split(0x01020304, fido.CmdPing, payload)
	if err != nil {
		panic(err)
	}
	fmt.Println(len(reports), "reports of", len(reports[0]), "bytes")

	// ...and put back together, as a reply would be.
	r := fido.NewReassembler(0x01020304)
	for _, rep := range reports {
		msg, done, err := r.Feed(rep)
		if err != nil {
			panic(err)
		}
		if done {
			fmt.Println(bytes.Equal(msg.Data, payload), msg.Cmd == fido.CmdPing)
		}
	}

	// A report for another channel is an error, not something to drop.
	other, _ := fido.Split(0x0A0B0C0D, fido.CmdPing, []byte("hi"))
	_, _, err = fido.NewReassembler(0x01020304).Feed(other[0])
	fmt.Println(err)

	// The framing's real limit, not the length field's.
	fmt.Println(fido.MaxMessage)
}
```

```
4 reports of 64 bytes
true true
fido: the report belongs to another channel
7609
```

Mit einem Schlüssel führt `fido.Open(ctx, transport)` den Handshake aus, und der `*Key`, den es
zurückgibt, trägt jeden späteren Befehl.

## Was es ablehnt und warum {#what-it-refuses-and-why}

**Einem Schlüssel wird nicht vertraut, dass er auf das antwortet, was gefragt wurde.** Eine Antwort, die einen
anderen Befehl trägt als den gesendeten, wird abgelehnt (CTAP 2.1 §11.2.9 gibt jeder
Antwort ihren eigenen Befehl, und libfido2 prüft das ebenfalls). Eine `INIT`-Antwort, deren
Nonce nicht die gesendete ist, wird abgelehnt: Sie ist der Handshake eines anderen Programms auf
demselben Schlüssel. Ein PIN-Token, das nicht die Länge seines Protokolls hat – 16 oder 32 Bytes unter
Protokoll eins, genau 32 unter Protokoll zwei –, wird abgelehnt.

**Ein Keepalive ist keine Antwort.** Ein Schlüssel, der auf einen Finger wartet, sendet
etwa alle hundert Millisekunden `CTAPHID_KEEPALIVE`; es wird übersprungen, und die
einzige Grenze dafür, wie lange eine Berührung dauern darf, ist der Kontext.

**Eine Nachricht, länger als das Framing tragen kann.** Zwei Längenbytes würden
65535 erlauben, aber 57 Bytes im Initialisierungspaket plus 128 Fortsetzungen zu je 59
ergeben 7609 (`MaxMessage`); darüber hinaus würde eine Sequenznummer `0x80` erreichen, und ein
Schlüssel würde sie als neue Nachricht lesen. `Split` gibt `ErrTooLong` zurück.

**Reports, die nicht zusammenpassen**: einer für einen anderen Kanal (`ErrWrongChannel` –
zwei Programme auf einem Schlüssel), Fortsetzungen in falscher Reihenfolge (`ErrOutOfOrder`), ein
Report, der kürzer ist als ein Paket (`ErrShortPacket`), eine `INIT`-Antwort, kürzer als
ihre 17 Bytes (`ErrTruncated`).

**Ein Befehl, für den der Schlüssel keine Unterstützung angegeben hat.** `Wink` wird nicht an einen Schlüssel
ohne `CapWink` gesendet, `GetInfo` nicht an einen ohne `CapCBOR`: Der Schlüssel würde
`CTAPHID_ERROR` antworten, und der Aufrufer müsste diese Ablehnung von einem Fehler unterscheiden.

**Eine leere PIN** und alles außer P-256 in `AuthData.PublicKey` – beim Namen abgelehnt,
statt halb dekodiert.

{{< callout type="warning" >}}
**Eine falsche PIN kostet einen Versuch**

CTAP gibt einem Authenticator einen Zähler für PIN-Versuche, höchstens acht, und jede
falsche PIN verbraucht einen. Drei falsche PINs hintereinander sperren die PIN, bis der
Schlüssel abgezogen und wieder eingesteckt wird. Ein Zähler, der null erreicht, sperrt sie
endgültig: Nur ein Reset hebt das auf, und ein Reset löscht jedes Credential auf dem
Schlüssel. Fragen Sie `Key.PINRetries` ab, bevor Sie jemanden zur Eingabe auffordern: Es
sagt, wie viele Versuche bleiben und ob der Schlüssel darauf wartet, abgezogen zu werden.

Lehnt ein Schlüssel eine PIN ab, sagt der Fehler, welcher der beiden Fälle vorliegt.
CTAP2_ERR_PIN_AUTH_BLOCKED (`0x34`), den das Abziehen aufhebt, lautet
`too many wrong PINs in a row; unplug the key and plug it in again (0x34)`;
CTAP2_ERR_PIN_BLOCKED (`0x32`), den nur ein Reset aufhebt, lautet
`the PIN is blocked: no tries are left, and only a reset, which erases the credentials, unblocks it (0x32)`.
Vor v0.6.2 waren die beiden Sätze vertauscht: Ein Schlüssel, der nur abgezogen
werden musste, galt als gesperrt, und wer das las, setzte ihn womöglich zurück und
verlor jedes Credential darauf.
{{< /callout >}}

## Wogegen es geprüft wird {#what-it-is-checked-against}

Die CI hat keinen Sicherheitsschlüssel, daher verwenden die Tests einen gefälschten Transport, der
zusammensetzt, was ihm gesendet wird – einen Schlüssel, der ablehnt, hängen bleibt, ständig meldet, er sei
beschäftigt, oder seinen Kanal mit einem anderen Programm teilt –, bei einer Coverage von 100 %. Zwei Fixtures
stammen von außerhalb dieses Codes:

- `testdata/yubikey-fido-5.7.4-getinfo.hex`, die `GetInfo`-Antwort, **aufgezeichnet
  von einem YubiKey FIDO 5.7.4**, dekodiert von `ctap2_test.go`;
- `testdata/webauthn-reference-authdata.b64`, ein Beispiel aus den Tests von
  **go-webauthn/webauthn**, das den Parser für die Authenticator-Daten und
  `AuthData.PublicKey` prüft.

Die Tabelle der Statuscodes folgt `err.h` von libfido2. Die README des Moduls dokumentiert
eine Registrierung und eine Assertion gegen einen echten YubiKey, wobei die Signatur
gegen den öffentlichen Schlüssel geprüft wurde, den er herausgegeben hat; dieser Lauf ist nicht Teil der CI.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/fido@v0.6.2](https://pkg.go.dev/github.com/go-authn/fido@v0.6.2)
