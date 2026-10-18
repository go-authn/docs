---
title: "Un royaume Kerberos pour les mêmes personnes"
linkTitle: "Royaume Kerberos"
weight: 60
description: "Le bloc kerberos, le keytab avec lequel il signe les tickets, qui peut recevoir un ticket et pourquoi certaines personnes ne le peuvent jamais, et pourquoi il ne peut pas cohabiter avec un bloc mfa."
tags: [authnd, kerberos, kdc]
---

```hcl
kerberos {
  realm    = "EXAMPLE.ORG"               # required, upper case
  keytab   = "/etc/authnd/krb5.keytab"   # required; must hold krbtgt/EXAMPLE.ORG
  listen   = "127.0.0.1:88"              # the default; UDP and TCP both
  lifetime = "10h"                       # the default, MIT's
}
```

Un bloc `kerberos` fait d'authnd un KDC en plus d'un annuaire, au moyen de
[go-authn/kdc]({{< relref "/libraries/_index.md" >}}) : les mêmes personnes
reçoivent des tickets au lieu d'être seulement consultées. Il répond en UDP et en TCP à
la même adresse, exige la pré-authentification par horodatage chiffré, et n'émet
que des tickets `aes256-cts-hmac-sha1-96`. `lifetime` est une durée Go
(`"10h"`, `"90m"`). L'annuaire et le royaume sont à égalité : si l'un s'arrête,
le processus s'arrête, parce qu'un serveur qui continuerait à répondre en LDAP après la mort de son KDC
paraîtrait en bonne santé à tout ce qui ne parle pas Kerberos.

Refusé au démarrage :

```
$ authnd check cases/realm-lower.hcl
authnd: kerberos: realm "example.org" is not upper case: clients uppercase the realm they derive from a domain, and would then ask for a realm this server does not answer for
```

et de même un royaume sans nom, sans keytab, une adresse qui ne s'analyse pas,
un `lifetime` que Go ne sait pas lire, et un bloc `kerberos` à côté d'un bloc `mfa`
(ci-dessous).

## Le keytab {#the-keytab}

Le keytab contient la clé avec laquelle authnd signe ses propres tickets —
`krbtgt/REALM@REALM` — et une clé par service auquel il émet des tickets. C'est
le même fichier que lisent ces services. Le mot de passe
du krbtgt n'est plus jamais saisi : rendez-le donc aléatoire. Avec le `ktutil` du MIT
(paquet `krb5-user` sur Debian et Ubuntu ; cette recette est celle que donne
`docs/install.md`, et elle n'a pas été exécutée pour ces pages) :

```sh
printf 'addent -password -p krbtgt/EXAMPLE.ORG@EXAMPLE.ORG -k 1 -e aes256-cts-hmac-sha1-96\n%s\nwkt /tmp/krb5.keytab\nquit\n' \
  "$(head -c 32 /dev/urandom | base64)" | ktutil
sudo install -o root -g authnd -m 0640 /tmp/krb5.keytab /etc/authnd/krb5.keytab
rm /tmp/krb5.keytab
```

Ajoutez la clé d'un service de la même façon (`-p nfs/files.example.org@EXAMPLE.ORG`), et
donnez à ce service la même clé dans son propre keytab. Sous macOS,
`ktutil -k <file> add -r -p <principal> -V 1 -e aes256-cts-hmac-sha1-96` de Heimdal
écrit une clé aléatoire sans aucun mot de passe. Dans les deux cas, relisez le keytab
avant de démarrer (`klist -k` avec MIT, `ktutil -k <file> list` avec
Heimdal) :

```
$ ktutil -k etc/authnd/krb5.keytab list
etc/authnd/krb5.keytab:

Vno  Type                     Principal                       Aliases
  1  aes256-cts-hmac-sha1-96  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG  
```

Un keytab sans `krbtgt/REALM` est refusé par `check` et au démarrage ; voir
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}}).
Le keytab est lu une seule fois, au démarrage : le remplacer demande un redémarrage.

## Qui peut recevoir un ticket {#who-can-be-issued-a-ticket}

Un KDC doit **déchiffrer** la pré-authentification du client avec la clé
à long terme de cette personne : il lui faut donc le **mot de passe** de la personne, et pas seulement un moyen
d'en vérifier un. `check` dit qui le peut et qui ne le peut pas, avec la raison :

```
$ authnd check realm
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP  MEMBERS        PUBLISHED AS
staff  alice and bob  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

| la source a | un ticket |
|---|---|
| un mot de passe (`password`, `password_file`, une colonne de mot de passe SQL) | oui |
| seulement une empreinte NT | **non** : c'est la clé RC4-HMAC, et ce royaume n'émet que de l'AES |
| seulement une vérification de mot de passe (un annuaire `users "ldap"` derrière celui-ci) | **non** : une source qui ne fait que vérifier un mot de passe ne peut produire aucune clé |

Pour un annuaire derrière celui-ci, la dernière ligne de la partie royaume se lit
*alice, bob, dora and eli: the source only verifies a password, so it cannot
produce any key*. C'est structurel plutôt qu'une affaire de configuration,
et le découvrir dans `check` vaut mieux que de l'apprendre de quelqu'un dont le `kinit` dit
que son mot de passe correct est faux.

## kinit contre lui {#kinit-against-it}

Un `krb5.conf` qui nomme ce KDC. ⛔ Pour MIT Kerberos, les accolades vont sur leurs
propres lignes : son analyseur ignore silencieusement un royaume écrit sur une seule ligne.

```ini
[libdefaults]
    default_realm = EXAMPLE.ORG
    dns_lookup_kdc = false
[realms]
    EXAMPLE.ORG = {
        kdc = 127.0.0.1:18388
    }
```

La même configuration servie, et interrogée par le `kinit` Heimdal de macOS
(`--password-file` lit le mot de passe dans un fichier) :

```
$ authnd --config realm
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp)

$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
$ klist
Credentials cache: FILE:ccache
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 18 16:10:19 2026  Oct 19 02:10:19 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG

$ kinit --password-file=wrong.pwin alice@EXAMPLE.ORG
kinit: Password incorrect

$ kinit --password-file=bob.pwin bob@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: this realm holds no Kerberos key for that principal

$ kinit --password-file=dora.pwin zed@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
```

Le ticket dure les dix heures par défaut. bob a saisi le mot de passe à partir duquel son empreinte NT
a été calculée, et il est tout de même refusé : le royaume n'a pas de clé pour lui. Le
KDC écrit ce qu'il a refusé, avec le code d'erreur Kerberos, sur sa sortie :

```
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
kerberos: refused krbtgt/EXAMPLE.ORG: this realm holds no Kerberos key for that principal (code 9)
kerberos: refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

*Pre-authentication required* est le premier échange normal d'un `kinit` : le
client demande sans pré-authentification, s'entend dire qu'elle est requise, puis redemande
avec. Le `kinit` réussi d'alice ne laisse que cette ligne.

{{< callout type="info" >}}
**Le royaume dit quels noms existent ; l'annuaire, non**

Une liaison LDAP pour un nom que personne ne porte reçoit la réponse `invalidCredentials`, la
même que pour un mauvais mot de passe. Le KDC répond *no such principal in this realm*
(`KDC_ERR_C_PRINCIPAL_UNKNOWN`, code 6), comme le font les KDC Kerberos. Avec un
bloc `kerberos` sur une adresse que d'autres peuvent joindre, la liste des noms est
donc aussi devinable qu'avec n'importe quel KDC ; `listen` vaut par défaut
la boucle locale.
{{< /callout >}}

## Un mot de passe changé par LDAP {#a-password-changed-over-ldap}

Le KDC lit les mêmes personnes que celles que sert l'annuaire, si bien qu'un
[mot de passe changé par LDAP]({{< relref "/authnd/passwords.md" >}}) atteint le
royaume aussitôt — l'ancien cesse de fonctionner pour `kinit` à l'instant où il cesse
de fonctionner pour une liaison :

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new
$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
kinit: Password incorrect
$ kinit --password-file=alice.new alice@EXAMPLE.ORG
$
```

## Pas à côté d'un bloc `mfa` {#not-beside-an-mfa-block}

```
$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks
```

La pré-authentification par horodatage chiffré de la RFC 4120 n'est dérivée que du mot de passe.
Un second facteur exige la pré-authentification OTP (RFC 6560) à l'intérieur de FAST
(RFC 6113), que ce KDC n'implémente pas. Un royaume ici distribuerait des
tickets sur un seul facteur aux personnes dont le [bloc `mfa`]({{< relref "/authnd/mfa.md" >}})
dit qu'il leur en faut deux, et un ticket ouvre tout ce qu'ouvre une liaison — le choix est donc
fait en refusant en cas de doute : l'un ou l'autre.

## Ports {#ports}

88 est privilégié. Sous l'unité fournie, `CAP_NET_BIND_SERVICE` le couvre ;
un serveur lancé par un utilisateur ordinaire veut un port haut, comme ci-dessus, et un
`krb5.conf` qui le nomme.
