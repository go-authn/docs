---
title: "Les bibliothèques, une question chacune"
linkTitle: "Bibliothèques"
weight: 50
description: "Les quatorze modules Go de go-authn : la question à laquelle chacun répond, la version que ces pages décrivent, et pourquoi ce sont des modules distincts."
tags: [bibliothèques]
---

Des programmes comme [authnd]({{< relref "/authnd/_index.md" >}}) et
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) sont construits à partir
de modules publiés, versionnés et testés chacun de leur côté. Chacun répond à
**une** question, et un programme importe ceux dont il pose les questions.

Tous sont en pur Go et se compilent avec `CGO_ENABLED=0`.

| module | la question à laquelle il répond | ces pages décrivent | chemin d'import |
|---|---|---|---|
| [mfa]({{< relref "/libraries/mfa.md" >}}) | assez de facteurs ont-ils répondu, de types assez variés, et lesquels ? | v0.5.0 | `github.com/go-authn/mfa` |
| [totp]({{< relref "/libraries/totp.md" >}}) | ce code à six chiffres est-il juste, et a-t-il déjà servi ? | v0.4.2 | `github.com/go-authn/totp` |
| [fido]({{< relref "/libraries/fido.md" >}}) | comment parle-t-on à une clé de sécurité, par rapports de 64 octets ? | v0.6.2 | `github.com/go-authn/fido` |
| [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) | est-ce *la clé enregistrée* qui a répondu, et une personne l'a-t-elle touchée ? | v0.4.2 | `github.com/go-authn/keyfactor` |
| [directory]({{< relref "/libraries/directory.md" >}}) | qui est quelqu'un, et qu'est-ce qui peut le prouver ? | v0.14.0 | `github.com/go-authn/directory` |
| [ldap]({{< relref "/libraries/ldap.md" >}}) | quels sont les octets d'un serveur LDAP ? | v0.9.0 | `github.com/go-authn/ldap` |
| [krb5]({{< relref "/libraries/krb5.md" >}}) | ce ticket Kerberos est-il bon pour ce service ? | v0.3.1 | `github.com/go-authn/krb5` |
| [kdc]({{< relref "/libraries/kdc.md" >}}) | comment un royaume délivre-t-il des tickets à partir d'un annuaire ? | v0.4.3 | `github.com/go-authn/kdc` |
| [oidc]({{< relref "/libraries/oidc.md" >}}) | qui ce jeton porteur dit-il être en train de demander, et faut-il le croire ? | v0.4.1 | `github.com/go-authn/oidc` |
| [saml]({{< relref "/libraries/saml.md" >}}) | qu'a dit le fournisseur d'identité d'une fédération à propos de cette personne ? | v0.4.1 | `github.com/go-authn/saml` |
| [krl]({{< relref "/libraries/krl.md" >}}) | ce certificat ou cette clé SSH est-il révoqué, comme sshd répondrait ? | v0.6.1 | `github.com/go-authn/krl` |
| [servercert]({{< relref "/libraries/servercert.md" >}}) | d'où vient le certificat de serveur TLS d'un démon ? | v0.5.2 | `github.com/go-authn/servercert` |
| [wireguard]({{< relref "/libraries/wireguard.md" >}}) | cette clé WireGuard peut-elle se connecter, et à qui est-elle ? | v0.1.1 | `github.com/go-authn/wireguard` |
| [scim]({{< relref "/libraries/scim.md" >}}) | qui le fournisseur d'identité vient-il de créer, de modifier ou de supprimer ? | v0.1.0 | `github.com/go-authn/scim` |

## Comment ils se regroupent {#how-they-group}

**Les facteurs** — si une personne est présente.
[mfa]({{< relref "/libraries/mfa.md" >}}) décide combien de preuves suffisent et
ne connaît aucun périphérique. [totp]({{< relref "/libraries/totp.md" >}}) est un
facteur : un code venu d'un téléphone. [fido]({{< relref "/libraries/fido.md" >}}) parle
CTAP à une clé de sécurité et ne connaît aucune politique ;
[keyfactor]({{< relref "/libraries/keyfactor.md" >}}) est la seule pièce qui
importe les deux, et fait d'une clé un facteur.

**L'annuaire, et son protocole.**
[directory]({{< relref "/libraries/directory.md" >}}) est le modèle : une personne,
et les identifiants qu'une source détient pour elle — un mot de passe, une empreinte NT, un
vérificateur, des clés SSH, un secret de code à usage unique — et, à part
d'eux, les attributs qui la décrivent sans rien prouver.
[ldap]({{< relref "/libraries/ldap.md" >}}) est le protocole réseau LDAP, côté
serveur, et le schéma d'annuaire contre lequel une entrée peut être
vérifiée, lu dans des fichiers OpenLDAP ou écrit en HCL2 ; ce qu'il répond est
l'affaire du gestionnaire.

**Kerberos, en deux moitiés.** [krb5]({{< relref "/libraries/krb5.md" >}})
*accepte* les tickets : un keytab, un AP-REQ en entrée, un AP-REP en sortie.
[kdc]({{< relref "/libraries/kdc.md" >}}) les *délivre*, à partir d'un annuaire qui
détient des mots de passe.

**Fédération et jetons.** [saml]({{< relref "/libraries/saml.md" >}}) est un
fournisseur de service SAML 2.0 devant une fédération comme RENATER ou eduGAIN.
[oidc]({{< relref "/libraries/oidc.md" >}}) vérifie les jetons OpenID Connect
qu'un fournisseur signe — la moitié serveur de ressources, sans parcours de connexion.
[scim]({{< relref "/libraries/scim.md" >}}) va dans l'autre sens : le point d'accès
SCIM 2.0 qu'un fournisseur d'identité appelle pour créer, mettre à jour et
supprimer les personnes et les groupes de votre application.

**Révocation et certificats.** [krl]({{< relref "/libraries/krl.md" >}})
lit, écrit et vérifie les listes de révocation de clés OpenSSH.
[servercert]({{< relref "/libraries/servercert.md" >}}) donne à un démon son
certificat TLS, à partir de fichiers ou d'ACME.

**[wireguard]({{< relref "/libraries/wireguard.md" >}})** transporte la liste signée
des clés publiques WireGuard que des personnes ont enregistrées auprès d'un fournisseur, et
qu'une passerelle transforme en pairs.

## Pourquoi ce sont des modules distincts {#why-they-are-separate-modules}

**Un service qui ne fait qu'accepter des tickets ne lie jamais de KDC.** Un serveur NFS
vérifie les tickets qu'un client présente ; il a un keytab et rien d'autre à faire
avec un royaume. Si accepter et délivrer formaient un seul module, chacun de ces serveurs
emporterait un chemin de code de délivrance de tickets qu'il n'exécute jamais, et le module
d'annuaire dans lequel un KDC lit les personnes, dont il ne se sert jamais.

C'est mesuré, pas voulu. Dans un module jetable qui n'importe que
`github.com/go-authn/krb5@v0.3.1` :

```sh
$ GOWORK=off go list -deps . | grep go-authn
github.com/go-authn/krb5
$ GOWORK=off go list -m all | grep go-authn
github.com/go-authn/krb5 v0.3.1
```

La même commande, pour un module qui importe `github.com/go-authn/kdc@v0.4.3`,
liste `github.com/go-authn/directory` et `github.com/go-authn/kdc` : délivrer
a besoin des personnes, accepter non.

La même règle vaut ailleurs. `mfa` n'importe rien hors de la bibliothèque
standard, et `fido` n'importe pas `mfa` : un programme qui veut seulement faire
clignoter une clé n'emporte pas de paquet de politique. `totp` ne dépend que de `mfa`, et
`oidc` n'a aucune dépendance. `directory` garde ses sources LDAP, SQL et HCL
dans des sous-paquets : le paquet principal n'importe rien hors de la bibliothèque
standard, et `sqldir` prend un `*sql.DB`, si bien que le pilote de base de données est le
choix du programme.

## Chaque page a les mêmes parties {#every-page-has-the-same-parts}

La question ; la ligne `go get` de la version décrite ; un exemple minimal
qui compile avec cette version ; ce que le module refuse, d'après son code ;
et ce contre quoi il est vérifié — l'implémentation qui n'est pas celle-ci,
nommée dans sa CI ou ses tests. Là où un README et le code divergent, la page
suit le code.
