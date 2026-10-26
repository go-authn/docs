---
title: "Eine Person ändert ihr eigenes Passwort"
linkTitle: "Passwort ändern"
weight: 50
description: "Der eine Schreibvorgang, den authnd annimmt: das eigene Passwort einer Person, über RFC 3062 oder ein RFC-4511-Modify, immer mit dem alten Passwort, zurückgeschrieben in die Datei, die die Person deklariert."
tags: [authnd, passwörter, ldappasswd]
---

Eine Person darf **ihr eigenes** Passwort ändern, und das niemand anderes, über die
RFC-3062-Operation Password Modify (was `ldappasswd` sendet) oder ein RFC-4511-Modify.
In beiden Fällen **muss das aktuelle Passwort mit dem neuen gesendet werden,
womit auch immer sich die Verbindung gebunden hat**. Eine Sitzung, die mit einem
[OAUTHBEARER-Token]({{< relref "/authnd/tokens.md" >}}) gebunden ist – kurzlebig und
womöglich nur ein Faktor –, könnte es sonst in ein dauerhaftes Passwort verwandeln, das
auch für `kinit` funktioniert.

Das ist das ppolicy-Verhalten von OpenLDAP mit gesetztem `pwdSafeModify`, mit den
Ergebniscodes, die dessen `ppolicy.c` zurückgibt. RFC 3062 §3 erlaubt es: „If oldPasswd is
not present, the server MAY use other policy to determine whether or not to
change the password.“

## Mit `ldappasswd` {#with-ldappasswd}

`-t` ist eine Datei mit dem alten Passwort, `-T` eine mit dem neuen; `-A` und
`-S` fragen stattdessen danach.

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -T alice.new
Result: Insufficient access (50)
Additional info: a password change must send the old password with the new one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t wrong.pwin -T alice.new
Result: Server is unwilling to perform (53)
Additional info: the old password sent is not the current one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.new
dn:uid=alice,ou=people,dc=example,dc=org
```

Das alte Passwort funktioniert sofort nicht mehr, für einen Bind und – mit einem
[Realm]({{< relref "/authnd/kerberos.md#a-password-changed-over-ldap" >}}) –
für `kinit`. Der Server sagt es in seiner Ausgabe:

```
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password
```

authnd erzeugt kein Passwort: Eine Anfrage ohne neues Passwort wird
mit `unwillingToPerform` abgelehnt (*this server does not generate passwords: send the
one you want*). Ein Passwort, das es erfände, müsste über die
Verbindung zurückgeschickt werden, und der eine Ort, an dem es sicher landet, ist der
Scrollback eines Terminals.

## Mit `ldapmodify` {#with-ldapmodify}

Die Änderung ist ein **Löschen des alten Werts, gefolgt vom Hinzufügen des neuen,
in einer einzigen Anfrage**. RFC 4511 §4.6 wendet die Änderungen eines Modify der Reihe nach und
atomar an; das Löschen – und mit ihm die ganze Anfrage – schlägt daher fehl, sofern der
gelöschte Wert nicht der gehaltene ist:

```
dn: uid=alice,ou=people,dc=example,dc=org
changetype: modify
delete: userPassword
userPassword: alice-test-pw
-
add: userPassword
userPassword: alice-new-pw
-
```

Ein bloßes `replace` beweist nichts, und alles außer `userPassword` ist nichts,
was dieser Server ändert:

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f replace.ldif
ldap_modify: Insufficient access (50)
	additional info: a password change must send the old password with the new one
modifying entry "uid=alice,ou=people,dc=example,dc=org"

$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f other.ldif
ldap_modify: Server is unwilling to perform (53)
	additional info: this server changes userPassword and nothing else, not cn
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

Ein Modify, das ein Passwort **und** etwas anderes verlangt, wird als Ganzes abgelehnt:
Ein Modify ist atomar, und die Hälfte davon auszuführen, würde Erfolg melden für
etwas, das niemand verlangt hat.

## Wer was ändern kann {#who-can-change-what}

| Anfrage | Antwort |
|---|---|
| kein altes Passwort, oder ein bloßes `replace: userPassword` | `insufficientAccessRights` |
| ein altes Passwort, das nicht das aktuelle ist | `unwillingToPerform` |
| der Eintrag einer anderen Person | `insufficientAccessRights`, *a password may be changed only by the person it belongs to* |
| eine anonyme Verbindung | `insufficientAccessRights`, *an anonymous connection has not said who it is* |
| jemand ganz ohne Passwort – kann sich nur mit einem Token gebunden haben | `unwillingToPerform`: Ein Bearer-Token ist kein Passwort und setzt nicht das erste. Das setzt die Administration in der Konfiguration |
| jemand, der aus einem `users`-Block bedient wird | `unwillingToPerform`: authnd liest diese Quellen und schreibt sie nicht |
| die Datei kann nicht geschrieben werden | `other` (80), *the password could not be written*; der Grund steht in der Ausgabe des Servers |

Der vorletzte Fall, mit dem Release-Binary, für dora, die aus einer
SQLite-Datenbank kommt:

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=dora,ou=people,dc=example,dc=org -y dora.pwin -t dora.pwin -T dora.new
Result: Server is unwilling to perform (53)
Additional info: dora is served from a sqlite database, which this server reads and does not write
```

Die Person wird **nach Identität, nicht nach DN** zugeordnet: Der eigene Name der Sitzung muss
genau der des Ziels sein, Byte für Byte; eine als `uid=Backup` gebundene Sitzung
kann daher das Passwort von `backup` nicht ändern, obwohl die beiden DNs als gleich gelten. Das
und die [Ablehnung von Namen, die sich nur in der Groß-/Kleinschreibung unterscheiden]({{< relref "/authnd/people.md#order-and-the-one-exception" >}})
sind zwei Kontrollen, die nicht voneinander abhängen.

## Wohin das neue Passwort geschrieben wird {#where-the-new-password-is-written}

Zurück in **die Datei, die die Person deklariert**, und nirgendwohin sonst:

- bei einem `user`-Block mit `password_file` wird **diese Datei** neu geschrieben, wobei
  Eigentümer und Gruppe erhalten bleiben, soweit der Prozess es darf, und ihr Modus auf
  höchstens 0600 eingeengt wird – nie erweitert;
- bei einem `user`-Block mit `password` inline wird die Konfigurationsdatei
  mit dem neuen Wert neu geschrieben, wobei Kommentare, Reihenfolge und Modus erhalten bleiben;
- ein `user`-Block mit nur einem `nt_hash` bekommt kein Passwort: Das würde
  ändern, was die Person ausweisen kann, und das ist eine Änderung der Konfiguration.

Jeder Schreibvorgang geht in eine temporäre Datei **im selben Verzeichnis**, dann folgt ein
Umbenennen – so hinterlassen eine volle Platte oder ein Absturz das alte Passwort, keine leere
Datei. Dafür braucht es Schreibzugriff auf das Verzeichnis. Unter der mitgelieferten Unit
nimmt `ProtectSystem=strict` ihn weg, und eine Änderung wird so abgelehnt:

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f safe.ldif
ldap_modify: Other (e.g., implementation specific) error (80)
	additional info: the password could not be written
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

mit dem Grund in der Ausgabe des Servers:

```
changing the password for alice: etc/authnd/passwords/alice.pw: open etc/authnd/passwords/.hcldir-1822988247: permission denied
```

Legen Sie die Passwörter also in ein eigenes Verzeichnis, das der Dienst beschreiben kann,
und die Konfiguration für ihn schreibgeschützt – das
[`ReadWritePaths=`-Drop-in]({{< relref "/authnd/install.md#the-configuration-directory" >}}).
Eine Person, deren Passwort inline steht, bräuchte ein beschreibbares `/etc/authnd` selbst,
was den Dienst auch seine eigene Konfiguration umschreiben ließe.

Nach einem erfolgreichen Schreibvorgang werden die Konfigurationsdateien erneut gelesen, **nur für die
`user`-Blöcke**: Eine unabhängige Änderung, die auf der Platte wartet, wird nicht
halb wirksam, weil jemand ein Passwort geändert hat. Alles andere wartet weiterhin auf
einen Neustart. Die Dateien werden allerdings weiterhin ganz gelesen; lädt also eine von ihnen
nicht mehr, wird das Passwort geschrieben, und der Client erfährt *the password
was written but this server did not reload it* – der laufende Server behält
das alte, bis er neu gestartet wird.
