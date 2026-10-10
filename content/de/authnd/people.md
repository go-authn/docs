---
title: "Woher die Personen kommen"
linkTitle: "Personen"
weight: 20
description: "user- und group-Blöcke, eine SQL-Datenbank, ein anderes LDAP-Verzeichnis: wie jede Quelle geschrieben wird, in welcher Reihenfolge sie gefragt werden und was jede einer Person erlaubt."
tags: [authnd, configuration, sql, ldap]
---

Ein `user`-Block ist das ganze Verzeichnis für eine kleine Installation oder die Dienstkonten,
die eine große aus ihrer Datenbank heraushält. Eine Installation, deren Personen bereits
in einer Datenbank oder in LDAP stehen, sollte sie nicht an einen zweiten Ort kopieren, der
veraltet; also liest ein `users`-Block sie dort, wo sie sind. Der `users`-Block ist
`hcldir` aus go-authn/directory, derselbe, den
[go-fileshare](https://github.com/go-fileshare/fileshare) liest: Ein
Verzeichnis wird beiden auf dieselbe Weise beschrieben.

## In der Konfiguration geschrieben {#written-in-the-configuration}

```hcl
user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

user "carol" {
  nt_hash         = "…"                                   # MD4(UTF16LE(password)), 32 hex
  authorized_keys = ["ssh-ed25519 AAAA… carol@laptop"]    # published as sshPublicKey
}

group "staff" { members = ["alice", "carol"] }
```

| Feld | was es ist |
|---|---|
| `password` | das Passwort, inline |
| `password_file` | dasselbe, aus einer Datei gelesen (umgebender Leerraum entfernt) |
| `nt_hash` | `MD4(UTF16LE(password))`, 32 Hexadezimalzeichen – für eine Installation, die das hält und nicht das Passwort |
| `totp_secret` | ein base32-Geheimnis für Einmalcodes, mindestens 128 Bit; siehe [einen zweiten Faktor]({{< relref "/authnd/mfa.md" >}}) |
| `authorized_keys` | `authorized_keys`-Zeilen, veröffentlicht als `sshPublicKey` |
| `authorized_keys_file` | dasselbe, aus einer Datei |

Beim Start abgelehnt, unter Nennung der Person:

- `password` und `password_file` zusammen – sagen Sie, welches von beiden;
- `password` und `nt_hash` zusammen – der Hash wird aus dem Passwort abgeleitet,
  also können zwei davon einander widersprechen;
- `authorized_keys` und `authorized_keys_file` zusammen;
- ein `nt_hash`, der nicht aus 32 Hexadezimalzeichen besteht, eine `authorized_keys`-Zeile, die
  sich nicht parsen lässt, ein `totp_secret` unter 128 Bit;
- derselbe `user` oder dieselbe `group` zweimal, und eine `group` ohne Mitglieder.

Ein Gruppenmitglied, das keine Quelle kennt, wird ebenfalls abgelehnt; das fängt einen
Tippfehler ab, bevor er stillschweigend nichts gewährt:

```
$ authnd check cases/typo.hcl
authnd: group "staff" has "alise" in it, who is not in the configuration file
```

{{< callout type="warning" >}}
**Ein `nt_hash` allein kann keinen Bind ausführen**

Eine Person, die nur mit `nt_hash` geschrieben ist, wird veröffentlicht, kann einem SMB-Server
über `sambaNTPassword` übergeben werden und **kann sich nicht bei authnd selbst binden**: Ein
LDAP-Simple-Bind sendet das Passwort, und ein NT-Hash ist hier kein Weg, eines zu prüfen.
bob unten hat nur einen NT-Hash, und der Hash ist der des
gesendeten Passworts:

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=bob,ou=people,dc=example,dc=org -y bob.pwin
ldap_bind: Invalid credentials (49)
```

`check` sagt es, nach den Tabellen:

```
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
```
{{< /callout >}}

## In einer SQL-Datenbank {#in-a-sql-database}

```hcl
users "sql" {
  driver   = "postgres"                      # or mysql (mariadb), or sqlite
  dsn_file = "/etc/authnd/pg.dsn"            # required: a DSN may hold a password
  users    = "select login, secret, nt_hash from staff"   # required
  groups   = "select team, member from team_members"      # optional
}
```

**Die Abfragen sind Ihre**, denn die Personen einer Installation liegen bereits in deren
Form vor. Die Spalten der `users`-Abfrage werden **nach Position** gelesen: ein Name,
dann beliebige von Passwort, NT-Hash, SSH-Schlüsseln (einer pro Zeile) und
Einmalcode-Geheimnis, in dieser Reihenfolge – bis zu fünf Spalten. Ein NULL sind
Zugangsdaten, die diese Person nicht hat. Eine Passwortspalte wird so verglichen, wie sie
gespeichert ist: authnd hat keine Einstellung für eine gehashte Spalte. Die `groups`-Abfrage liefert
einen Gruppennamen und ein Mitglied, eine Zeile pro Mitgliedschaft.

`driver` akzeptiert `postgres` (oder `postgresql`, `pgx`), `mysql` (oder `mariadb`)
und `sqlite` (oder `sqlite3`). Die Datenbank wird beim Start erreicht, bevor
irgendetwas lauscht; eine, die nicht antwortet, hält den Server daher dort an, wo
jemand zusieht:

```
$ authnd check cases/nodb
authnd: users "sql": the postgres database is not answering: failed to connect to `user=authnd database=authnd`:
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
```

PostgreSQL auf derselben Maschine über seinen Socket und Peer-Authentifizierung
braucht kein Passwort im DSN: `host=/run/postgresql dbname=authnd user=authnd`.
SQLite im Zustandsverzeichnis: `file:/var/lib/authnd/people.db`.

Ein Schlüssel, der zur anderen Art von Block gehört, wird abgelehnt statt ignoriert:

```
$ authnd check cases/sqlwrongkey.hcl
authnd: users "sql" has base_dn in it, which belongs to an ldap block
```

## In einem anderen LDAP-Verzeichnis {#in-another-ldap-directory}

```hcl
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/authnd/upstream.pw"
}
```

`url` und `base_dn` sind Pflicht. Wo die Personen und Gruppen liegen und welche
Attribute sie benennen:

| Schlüssel | Standard |
|---|---|
| `user_filter` | `(objectClass=posixAccount)` |
| `user_attribute` | `uid` |
| `group_base_dn` | `base_dn` |
| `group_filter` | `(objectClass=posixGroup)` |
| `group_attribute` | `cn` |
| `group_member_attribute` | `memberUid` |
| `totp_attribute` | keiner: Es gibt kein Standardattribut, und eine Vermutung würde nichts lesen und dabei so aussehen, als hätte sie nachgesehen |
| `start_tls` | `false` |

`sambaNTPassword` und `sshPublicKey` werden unter diesen Namen gelesen. Zwei Dinge
werden abgelehnt, bevor irgendetwas geöffnet wird:

```
$ authnd check cases/ldap-clear.hcl
authnd: users "ldap" would send every password to "ldap.example.org" in the clear: use ldaps://, or start_tls = true (RFC 4513 §5.1.3)

$ authnd check cases/ldap-cred.hcl
authnd: users "ldap" has credentials in its url, and a url is printed: use bind_dn with bind_password_file
```

`ldap://` zu einer Loopback-Adresse und `ldapi://` werden akzeptiert: Niemand ist
dazwischen.

Ein Verzeichnis hinter diesem **prüft** Passwörter, indem gegen es gebunden wird; es
gibt sie nicht heraus. Hier steht ein authnd vor einem anderen, unter einer anderen Basis:

```
$ authnd check front2
ldap://127.0.0.1:3894, base dc=example,dc=net

USER        FROM                    CAN PROVE         PUBLISHED AS
alice       ldap://127.0.0.1:3893   a password check  uid and cn
bob         ldap://127.0.0.1:3893   a password check  uid and cn
dora        ldap://127.0.0.1:3893   a password check  uid and cn
eli         ldap://127.0.0.1:3893   a password check  uid and cn
svc-backup  the configuration file  a password        uid and cn

GROUP      MEMBERS
engineers  dora and eli
staff      alice, bob and dora

a bind carries a password
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

*Eine Passwortprüfung* (*a password check*) genügt für einen Bind und genügt nie für ein
[Kerberos-Ticket]({{< relref "/authnd/kerberos.md#who-can-be-issued-a-ticket" >}})
oder für SMB.

## Reihenfolge, und die eine Ausnahme {#order-and-the-one-exception}

Quellen werden **in der Reihenfolge gefragt, in der sie geschrieben sind**, und die erste, die
einen Namen kennt, besitzt ihn. Die `user`-Blöcke kommen immer zuerst, sodass ein lokal
eingetragenes Dienstkonto nicht von jemandem mit demselben Namen
in der Datenbank überschrieben wird. **Die Gruppenmitgliedschaft ist die Vereinigung** aller
Quellen: Eine Gruppe, die sowohl ein `group`-Block als auch die `groups`-Abfrage einer
Datenbank nennt, hat die Mitglieder beider.

{{< callout type="warning" >}}
**Zwei Namen, die sich nur in der Groß-/Kleinschreibung unterscheiden, werden abgelehnt**

Eine uid wird ohne Beachtung der Groß-/Kleinschreibung verglichen (RFC 4519 §2.39), ebenso jeder DN;
`Dora` in der Datei und `dora` in einer Datenbank sind daher für LDAP ein Name und für alles,
was Bytes vergleicht, zwei Personen – eine Passwortänderung der einen würde bei der
anderen landen. Eine solche Konfiguration startet nicht:

```
$ authnd check cases/case.hcl
authnd: "Dora" (from the configuration file) and "dora" (from a sqlite database) differ only by case, and an LDAP name does not tell them apart: a uid is compared ignoring case. Rename one of them
```
{{< /callout >}}

## Einmal gelesen {#read-once}

Jede Quelle wird **einmal, beim Start** gelesen. Eine Person, die der Datenbank hinzugefügt wird, oder
eine Mitgliedschaft, die sich im Verzeichnis hinter diesem ändert, wird nach einem
Neustart bedient, nicht vorher. Das gilt auch für eine Passwortspalte in einer Datenbank: Sie wird
mit dem Rest der Zeile gelesen. Ein Verzeichnis hinter diesem unterscheidet sich nur
darin, dass ein Bind geprüft wird, indem gegen es gebunden wird; ein *dort* geändertes Passwort ist
also das, das funktioniert. Die andere Ausnahme ist ein Passwort, das eine Person über
authnd selbst ändert und das [sofort angewendet wird]({{< relref "/authnd/passwords.md" >}}).
Es gibt kein Neuladen; siehe [Betrieb]({{< relref "/authnd/operations.md" >}}).
