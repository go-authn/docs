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
(autorité de certification) propre d'un site — et authnd est **redémarré** après chaque renouvellement,
car le certificat est lu une seule fois, à l'ouverture de l'écouteur.

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
ldaps on 127.0.0.1:3636, serving 2 people from the configuration file

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
objectClass: person
objectClass: posixAccount
uid: bob
cn: bob
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

## `publish_nt_hash` {#publish_nt_hash}

`sambaNTPassword` est ce qui permet à Samba ou à un autre serveur SMB d'authentifier
des personnes par cet annuaire, et ce n'est **pas** une empreinte de mot de passe au
sens où l'entend un formulaire de connexion : quiconque détient `MD4(UTF16LE(password))`
s'authentifie comme cette personne en NTLMv2 sans jamais connaître le
mot de passe. Elle n'est donc publiée que sur demande :

```hcl
publish_nt_hash = true
```

et cette demande est refusée sauf si l'écouteur a TLS, ou est en bouclage
(`127.0.0.0/8`, `::1`, `localhost`) et donc sur aucun réseau :

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

Avec elle, `check` nomme l'attribut par personne et dit ce qui le protège :

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS
alice  the configuration file  a password  uid, cn and sambaNTPassword
bob    the configuration file  an NT hash  uid, cn and sambaNTPassword

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2

this configuration can be served
```

et, pour l'écouteur StartTLS, *sambaNTPassword is published over TLS, once
StartTLS has been asked for*. alice n'a pas d'empreinte NT écrite ; la sienne est
dérivée du mot de passe qu'elle a. L'empreinte de bob est publiée pour qu'un serveur SMB
s'en serve, et `check` dit aussi que bob ne peut pas se lier à authnd lui-même.

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
