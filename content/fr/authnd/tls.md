---
title: "TLS : ldaps:// ou StartTLS, et pas les deux à la fois"
linkTitle: "TLS"
weight: 40
description: "Servir LDAP sur TLS à partir d'un certificat en fichiers, le choix entre ldaps:// et StartTLS, et pourquoi sambaNTPassword n'est publié que sur TLS."
tags: [authnd, tls, starttls, ldaps]
---

```hcl
listen    = "0.0.0.0:636"
cert_file = "/etc/authnd/cert.pem"   # the chain, leaf first
key_file  = "/etc/authnd/key.pem"
```

`cert_file` et `key_file` ensemble activent TLS ; l'un sans l'autre est
refusé (*one without the other serves nothing*). TLS 1.2 est le minimum.
authnd n'a pas de client ACME : les deux fichiers sont écrits par autre chose —
[go-authn/servercert]({{< relref "/libraries/servercert.md" >}}), certbot, l'AC
(autorité de certification) propre d'un site — et depuis la v0.15.0 authnd les relit quand ils changent, sans redémarrage : voir
[renouveler le certificat](#renewal). Jusqu'à la v0.14.1, authnd était
**redémarré** après chaque renouvellement, car le certificat était lu une seule
fois, à l'ouverture de l'écouteur.

## Deux façons, un écouteur chacune {#two-ways-one-listener-each}

| | `starttls` | l'écouteur | `check` dit |
|---|---|---|---|
| **ldaps://** | non défini | la poignée de main TLS a lieu avant qu'un seul octet de LDAP soit échangé | `ldaps://…` |
| **StartTLS** | `starttls = true` | en clair, mis à niveau quand le client le demande (RFC 4511 §4.14) | `ldap+starttls://…` |

C'est l'un ou l'autre, et cela doit l'être : un écouteur ne peut pas à la fois exiger une
poignée de main et attendre de voir si on en demande une. Le choix d'un site dépend
de ses **clients** : `ldaps://` sur le 636 est ce pour quoi la plupart sont configurés,
et StartTLS est ce que demandera un client pointé sur le 389 avec « utiliser TLS » coché.
Un site qui a besoin des deux fait tourner deux instances, chacune avec son propre
`--config`. `starttls = true` sans certificat est refusé :

```
$ authnd check cases/starttls-nocert.hcl
authnd: starttls needs cert_file and key_file: there is nothing to upgrade a connection WITH
```

### ldaps:// {#ldaps}

Le serveur, un certificat signé par une AC pour `127.0.0.1`, et la chaîne vérifiée
par un client qui n'est pas ce programme :

```
$ authnd --config ldaps
ldaps on 127.0.0.1:3636, serving 3 people from the configuration file
uid=carol,ou=people,dc=example,dc=org is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

$ openssl s_client -connect 127.0.0.1:3636 -CAfile tls/ca.pem -verify_return_error -verify_ip 127.0.0.1 </dev/null 2>&1 | grep -E 'Verify return|Protocol|subject=|issuer='
subject=CN=localhost
issuer=CN=docs test CA
Protocol: TLSv1.3
Verify return code: 0 (ok)
    Protocol  : TLSv1.3
    Verify return code: 0 (ok)
```

### StartTLS, qui refuse tant qu'on ne l'a pas demandé {#starttls-which-refuses-until-it-is-asked-for}

StartTLS est demandé par le **client**, donc le simple fait de le proposer ne promet
rien : un client qui ne le demande jamais se lierait en clair. Un écouteur avec
`starttls = true` refuse donc chaque liaison et chaque recherche tant que la
connexion n'a pas été mise à niveau, avec `confidentialityRequired` :

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
ldap_bind: Confidentiality required (13)
	additional info: this listener requires TLS, and nothing asked for it

$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
dn: uid=bob,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: sambaSamAccount
objectClass: uidObject
uid: bob
cn: bob
sambaSID: S-1-5-21-1004336348-1177238915-682003330-1104
sambaNTPassword: 8846F7EAEE8FB117AD06BDD830B7586C
```

(`-ZZ` signifie « StartTLS, et échouer s'il échoue ». `LDAPTLS_REQCERT=never` est là
parce que le `ldapsearch` livré avec macOS fait confiance au magasin du système et qu'on n'a pas pu
lui faire accepter cette AC de test ; la chaîne a été vérifiée séparément avec
`openssl s_client -starttls ldap -CAfile tls/ca.pem -verify_return_error`,
qui a répondu `Verify return code: 0 (ok)`.)

C'est ce refus qui fait de `cert_file` une garantie plutôt qu'une offre — et
c'est sur lui que s'appuie `publish_nt_hash`. Il inclut la liaison anonyme
qu'envoie `ldapsearch -x` avant de lire le root DSE, si bien que sur un écouteur StartTLS
cette requête de découverte, elle aussi, a besoin de `-ZZ`.

## Renouveler le certificat {#renewal}

Depuis la v0.15.0, un certificat renouvelé n'exige pas de redémarrage. authnd
compare `cert_file` et `key_file` à ce qu'il sert au premier handshake TLS qui
suit un délai de 5 secondes depuis son dernier examen, et aussitôt sur `SIGHUP`
(`kill -HUP`, ou `systemctl kill -s HUP authnd`). L'identité d'un fichier est le
SHA-256 de son contenu : un outil de renouvellement qui renomme un nouveau
fichier par-dessus l'ancien et un qui le réécrit sur place sont donc tous deux
vus, et une paire de même taille écrite dans le même tic d'horloge n'est pas
prise pour l'ancienne.

Une nouvelle paire qui ne se charge pas (à moitié écrite, clé qui ne correspond
pas au certificat, fichier corrompu) ne change rien : authnd continue de servir
le certificat qu'il a, journalise l'échec **une seule fois** pour cet état des
fichiers, et réessaie quand ils changent de nouveau. Avant la v0.15.0, un
certificat expiré la nuit n'était plus approuvé par aucun client jusqu'à ce que
quelqu'un redémarre authnd. La configuration et le keytab ne sont toujours lus
qu'au démarrage.

## `publish_nt_hash` {#publish_nt_hash}

`sambaNTPassword` est ce qui permet à Samba ou à un autre serveur SMB d'authentifier
des personnes par cet annuaire, et ce n'est **pas** une empreinte de mot de passe au
sens où l'entend un formulaire de connexion : quiconque détient `MD4(UTF16LE(password))`
s'authentifie comme cette personne en NTLMv2 sans jamais connaître le
mot de passe. Elle n'est donc publiée que sur demande et, depuis la v0.11.0,
avec le domaine auquel appartiennent les SID des personnes :

```hcl
publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"   # `net getlocalsid` on the SMB server
}
```

Cette demande est refusée sauf si l'écouteur a TLS, ou est en bouclage
(`127.0.0.0/8`, `::1`, `localhost`) et donc sur aucun réseau :

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

### Le bloc `samba` {#the-samba-block}

`sambaNTPassword` appartient au `sambaSamAccount` de Samba, dont le MUST est
`uid` et `sambaSID`, et aucune autre classe ne l'autorise. Chaque entrée que
publie authnd respecte [le schéma qu'il sert]({{< relref "/authnd/entries.md" >}}),
donc l'attribut n'est publié que sur un `sambaSamAccount`, et cela demande un
SID :

| clé | |
|---|---|
| `domain_sid` | obligatoire : le SID de domaine du serveur SMB, `S-1-5-21-…`, tel que l'affiche `net getlocalsid` |
| `algorithmic_rid_base` | facultatif, `1000` par défaut, celui de Samba. Un nombre impair, ou inférieur à 1000, est refusé : Samba en utiliserait silencieusement un autre |

Le `sambaSID` d'une personne est son propre attribut `sambaSID` quand une
source en donne un ([attributs]({{< relref "/authnd/entries.md#adding-attributes" >}})).
Sinon, c'est `domain_sid-RID`, avec RID = 2 × `uidNumber` +
`algorithmic_rid_base` : la correspondance algorithmique de Samba
(smb.conf(5), *algorithmic rid base*). Une personne qui a une clé NT et ni
l'un ni l'autre est publiée **sans** `sambaNTPassword`, et `check` et le
journal de démarrage disent qui. Les définitions Samba ne sont ajoutées au
schéma servi à `cn=Subschema` que lorsque le bloc est présent ; elles ont été
écrites à partir des OID, des noms et des syntaxes publiés par Samba, et non
copiées de son `samba.schema` sous GPL-3.0.

{{< callout type="error" >}}
**Rupture pour les configurations v0.10.x : `publish_nt_hash` sans bloc `samba` ne démarre pas**

La v0.10.x servait `publish_nt_hash = true` seul. Depuis la v0.11.0, cette
configuration est refusée au démarrage et par `check`, avec ce qu'il faut
ajouter :

```
$ authnd check cases/nthash.hcl
authnd: publish_nt_hash needs a samba block: sambaNTPassword belongs to Samba's sambaSamAccount, whose MUST is uid and sambaSID, and a SID needs the domain's. Add

  samba {
    domain_sid = "S-1-5-21-..."   # the SMB server's: `net getlocalsid` prints it
  }

and each person's sambaSID is their own sambaSID attribute, or domain_sid-(2 x uidNumber + 1000), Samba's algorithmic mapping; `authnd check` lists who has neither
```

Lancez `check` avec le nouveau binaire avant la mise à niveau. Le refus est
délibéré : l'entrée de la v0.10.x ne peut pas respecter le schéma, et les deux
solutions silencieuses — écarter l'attribut, ce qui retire SMB à tout le
monde, ou écarter l'entrée, ce qui retire la personne — se produiraient
toutes deux sans rien sur la console.
{{< /callout >}}

Un bloc `samba` sans `publish_nt_hash` est refusé aussi, puisqu'il ne
publierait rien :

```
$ authnd check cases/samba-alone.hcl
authnd: a samba block without publish_nt_hash publishes nothing: it is the domain of the sambaSID that sambaNTPassword needs. Remove it, or set publish_nt_hash = true
```

### Ce que dit `check` {#what-check-says}

Trois personnes sur un écouteur `ldaps://` : alice a un mot de passe et le
trio POSIX, donc son SID est dérivé (2 × 1000 + 1000) ; bob n'a qu'une
empreinte NT et un `sambaSID` propre ; carol a un mot de passe et ni l'un ni
l'autre.

```hcl
listen    = "127.0.0.1:3636"
base_dn   = "dc=example,dc=org"
cert_file = "tls/cert.pem"
key_file  = "tls/key.pem"

publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"
}

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes    = { uidNumber = "1000", gidNumber = "1000", homeDirectory = "/home/alice" }
}

user "bob" {
  nt_hash    = "8846F7EAEE8FB117AD06BDD830B7586C"
  attributes = { sambaSID = "S-1-5-21-1004336348-1177238915-682003330-1104" }
}

user "carol" { password = "carol-pw" }
```

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS                                       WITH
alice  the configuration file  a password  account, posixAccount, sambaSamAccount, uidObject  uid, cn, gidNumber, homeDirectory, uidNumber, sambaSID and sambaNTPassword
bob    the configuration file  an NT hash  account, sambaSamAccount, uidObject                uid, cn, sambaSID and sambaNTPassword
carol  the configuration file  a password  account, uidObject                                 uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, sambaSamAccount, uidObject
carol has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
carol is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2
  in sambaSamAccount, with sambaSIDs in S-1-5-21-1004336348-1177238915-682003330 (a person's own sambaSID, or RID 2 x uidNumber + 1000)

this configuration can be served
```

et, pour l'écouteur StartTLS, *sambaNTPassword is published over TLS, once
StartTLS has been asked for*. alice n'a pas d'empreinte NT écrite ; la sienne est
dérivée du mot de passe qu'elle a. L'empreinte de bob est publiée pour qu'un serveur SMB
s'en serve, et `check` dit aussi que bob ne peut pas se lier à authnd lui-même.
L'entrée de carol est publiée sans l'attribut, et un serveur SMB ne peut pas
servir carol tant qu'une source ne lui donne pas de `uidNumber` ou de
`sambaSID`.

Ce que reçoit un lecteur, sur l'écouteur StartTLS des mêmes personnes :

```
$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=alice)'
dn: uid=alice,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: sambaSamAccount
objectClass: uidObject
uid: alice
cn: alice
gidNumber: 1000
homeDirectory: /home/alice
uidNumber: 1000
sambaSID: S-1-5-21-1004336348-1177238915-682003330-3000
sambaNTPassword: D061EF15E9494B458016FA760CECDD63
```

Seul un [lecteur]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})
peut chercher, donc seul un lecteur voit jamais l'attribut. Qui peut le lire est
donc la même question que qui détient le mot de passe d'un lecteur.

{{< callout type="warning" >}}
**NTLMv2 a besoin du mot de passe ou de son MD4, et de rien d'autre**

Un serveur de fichiers qui interroge authnd au sujet de quelqu'un ne peut servir cette personne en SMB que si
la *source* détenait assez pour cela : un mot de passe, ou l'empreinte. Une personne qui
vient d'un annuaire qui ne fait que vérifier les mots de passe — *a password check* dans
`check` — ne peut jamais recevoir de `sambaNTPassword`, quoi que fasse authnd
entre les deux. Sans `publish_nt_hash`, personne ne le peut : `check` dit alors
*sambaNTPassword is not published, so nothing here can authenticate an SMB
session*.
{{< /callout >}}

## Les jetons en ont besoin aussi {#tokens-need-it-too}

Un [bloc `oidc`]({{< relref "/authnd/tokens.md" >}}) refuse un jeton sur une
connexion qui n'est pas chiffrée, sauf si `allow_plaintext = true` dit que
TLS est terminé devant ce processus.
