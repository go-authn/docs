---
title: "check, bevor Sie etwas neu starten, über das sich Personen anmelden"
linkTitle: "check"
weight: 30
description: "Was authnd check öffnet, was es über eine Konfiguration ausgibt, bevor sie bereitgestellt wird, wie man es liest, und der eine Fehler, den es nicht sehen kann."
tags: [authnd, check, konfiguration]
---

```
authnd check /etc/authnd
authnd check --config a.hcl --config b.hcl
```

`check` liest die Konfiguration genau so wie der Server, **öffnet alles, was der Server
öffnet, bevor er lauscht** – die Dateien, die Datenbank, das Verzeichnis hinter diesem, das
Discovery-Dokument des Identitätsanbieters, das TLS-Zertifikat und den Schlüssel, den Keytab –
und gibt aus, was veröffentlicht würde und für wen, **ohne zu lauschen**. Es gibt aus, woher
jeder Zugangsnachweis kommt, und nie, was darin steht. Es endet mit Status 0 und mit *this
configuration can be served* oder mit Status 1 und dem einen Satz, der den Server aufhält.

## Eine Konfiguration, die bereitgestellt werden kann {#a-configuration-that-can-be-served}

Zwei `user`-Blöcke, ein Reader und eine SQLite-Datenbank, in einem Verzeichnis mit zwei
Dateien (`authnd.hcl` und `people.hcl`):

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS
alice  the configuration file  a password  uid and cn
bob    the configuration file  an NT hash  uid and cn
dora   a sqlite database       a password  uid and cn
eli    a sqlite database       an NT hash  uid and cn

GROUP      MEMBERS
engineers  dora and eli
staff      alice, bob and dora

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## Wie man es liest {#reading-it}

Die erste Zeile nennt Schema, Adresse und Basis: `ldap://`, `ldaps://` oder
`ldap+starttls://` – siehe [TLS]({{< relref "/authnd/tls.md" >}}).

| Spalte | |
|---|---|
| `FROM` | die Quelle, der der Name gehört: *the configuration file*, *a sqlite database* (oder postgres, mysql) oder die URL eines Verzeichnisses hinter diesem |
| `CAN PROVE` | *a password* (vorhanden, sodass es verglichen und Schlüssel daraus abgeleitet werden können), *a password check* (ein anderes Verzeichnis antwortet mit Ja oder Nein), *an NT hash*, *N keys*, *a one-time-code secret* oder *nothing* |
| `PUBLISHED AS` | die Attribute, die der Eintrag trägt: immer `uid` und `cn`; `sambaNTPassword`, wenn `publish_nt_hash` eingeschaltet ist und die Person einen NT-Hash hat oder ein Passwort, aus dem er abgeleitet werden kann; `sshPublicKey`, wenn Schlüssel vorhanden sind |

Die Zeilen nach den Tabellen sagen, was man wissen muss, bevor man sich auf die
Konfiguration verlässt:

- **was ein Bind trägt**: *a password* oder, mit einem [`mfa`-Block]({{< relref "/authnd/mfa.md" >}}),
  *a password with a 6-digit code after it*; mit einem [`oidc`-Block]({{< relref "/authnd/tokens.md" >}}),
  woher Tokens kommen und worüber;
- **wer sich überhaupt nicht mit einem Passwort binden kann**: Personen, die nur über einen
  NT-Hash bekannt sind – siehe [Personen]({{< relref "/authnd/people.md#written-in-the-configuration" >}});
- **wer suchen darf**: die Reader oder *no reader is declared: nothing may search, and binds
  are not affected*;
- **ob `sambaNTPassword` veröffentlicht wird**, und worüber – siehe
  [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}});
- mit einem [`kerberos`-Block]({{< relref "/authnd/kerberos.md" >}}) der Realm und
  **wem ein Ticket ausgestellt werden kann und wem nicht**, mit dem Grund;
- mit einem `mfa`-Block, **wer keinen zweiten Faktor hat** und sich deshalb nicht mit einem
  Passwort binden kann; steht ein `oidc`-Block daneben, fügt die Zeile hinzu, dass ein Token,
  dessen `amr` zwei Arten nennt, es weiterhin kann;
- eine **Gruppe, die jemanden nennt, den keine Quelle hat**.

Diese letzte wird so veröffentlicht, wie sie ist – `memberUid` ist eine Zeichenkette, und eine
Fassade für ein System trägt berechtigterweise Namen, die einem anderen gehören –, aber es wird
gesagt, weil die andere Lesart ein Tippfehler ist. Hier hat die Tabelle `team_members` der
Datenbank eine Zeile für `zoe`, einen Namen, den hier niemand trägt:

```
GROUP      MEMBERS
engineers  dora, eli and zoe
staff      alice, bob and dora
engineers names zoe, who has no entry here: the group is published as it stands, and nothing here can prove them
```

(Ein `group`-*Block*, der eine fremde Person nennt, wird sofort abgelehnt; siehe
[Personen]({{< relref "/authnd/people.md#written-in-the-configuration" >}}).)

## Was es ablehnt {#what-it-refuses}

Jeder dieser Fälle hält `check` und den Server gleichermaßen auf, mit Exit-Status 1. Sie
stehen auf den Seiten, zu denen sie gehören; einige, wie ausgegeben:

```
$ authnd check cases/nobody.hcl
authnd: there is nobody here: name a user, or a users block reading a database or a directory

$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear

$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks

$ authnd check empty
authnd: empty has no .hcl files in it

$ authnd
authnd: no configuration: give a .hcl file or a directory of them
```

## Das Zertifikat, der Keytab und das eine, was es nicht sehen kann {#the-certificate-the-keytab-and-the-one-thing-it-cannot-see}

Ein Zertifikat, das sich nicht laden lässt, und ein Keytab ohne `krbtgt/REALM` werden von
`check` abgelehnt, mit den Worten, die der Server verwenden würde:

```
$ authnd check cases/badcert
authnd: the certificate: open tls/missing.pem: no such file or directory

$ authnd check cases/nokrbtgt
authnd: kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/EXAMPLE.ORG" realm: EXAMPLE.ORG kvno: 0 etype: 18
```

Was `check` nicht wissen kann, ohne zu lauschen, ist, **ob die Ports frei sind**. Ein zweiter
Server an derselben Kerberos-Adresse besteht `check` und wird beim Start abgelehnt:

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

## Als Dienstkonto ausführen {#run-it-as-the-service-account}

```sh
sudo -u authnd authnd check /etc/authnd
```

damit eine Datei, die nur root lesen kann, hier scheitert und nicht beim Neustart. Führen Sie
es vor einem Upgrade mit dem **neuen** Binary aus; siehe
[Installation]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}}).
