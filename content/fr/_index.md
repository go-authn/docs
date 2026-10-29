---
title: "go-authn"
linkTitle: "Accueil"
type: docs
cascade:
  type: docs
description: "L'authentification en Go pur : les facteurs qui prouvent que quelqu'un est présent, un annuaire qui dit qui sont les personnes, les deux moitiés de Kerberos, et un fournisseur OpenID Connect devant une fédération SAML."
---

**Deux questions, et ce ne sont pas les mêmes.** *Cette personne est-elle là, maintenant ?* n'est
pas *qui est cette personne, et qu'est-ce qui le prouverait ?* go-authn répond aux deux :
les facteurs qui prouvent la présence, un annuaire qui porte ce qui **prouve** chaque
personne plutôt qu'un champ de mot de passe, les deux moitiés de Kerberos, et un fournisseur
OpenID Connect devant une fédération SAML. Go pur, `CGO_ENABLED=0`.
Ces pages décrivent les versions listées sur la [page d'état]({{< relref "/status.md" >}}).

## Quatre programmes {#four-programs}

| | ce que c'est | ces pages décrivent |
|---|---|---|
| [authnd]({{< relref "/authnd/_index.md" >}}) | un serveur LDAP, et éventuellement un royaume Kerberos, pour des personnes qui vivent ailleurs : un fichier, une base de données SQL, un autre annuaire | v0.13.2 |
| [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) | un fournisseur OpenID Connect devant une fédération SAML (RENATER, eduGAIN), qui émet aussi des certificats SSH et signe les listes qui les révoquent | v0.23.4 |
| [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) | récupère ces listes, vérifie chacune avant qu'un serveur ne la lise, et refuse en cas de doute quand l'une d'elles expire | v0.6.6 |
| [sshcert]({{< relref "/sshcert/_index.md" >}}) | `sshcert-authorize`, à qui sshd demande si la délégation de domaine d'un certificat nomme cet hôte | v0.1.9 |

Chacun est un binaire statique unique pour Linux, macOS et Windows sur amd64 et arm64,
publié avec `SHA256SUMS` et une provenance de compilation :
[vérifier un téléchargement]({{< relref "/security/verifying-releases.md" >}}).

```sh
go install github.com/go-authn/authnd@v0.13.0
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.4
go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.6
```

Les commandes s'appellent `authn-*` (et `authnd`) parce qu'elles sont installées sur
des machines qui font tourner autre chose : un `bridge` ou un `revokd` nu dans `/usr/bin`
prendrait un nom dont quelqu'un d'autre pourrait avoir besoin.

## Et les bibliothèques en dessous {#and-the-libraries-under-them}

Les programmes sont minces. Ce qu'ils font réside dans
[quatorze modules]({{< relref "/libraries/_index.md" >}}), une question chacun, de sorte
qu'un service qui ne fait qu'*accepter* des tickets Kerberos ne lie jamais un KDC, et qu'un
service qui ne vérifie qu'un code à usage unique ne lie jamais un annuaire.

## Pourquoi l'annuaire porte ce qui prouve quelqu'un {#why-the-directory-carries-what-proves-somebody}

SMB a besoin d'une empreinte NT ; S3 a besoin du mot de passe lui-même, parce que SigV4 en calcule
un HMAC ; un royaume Kerberos a besoin d'une clé dérivée du mot de passe, et une empreinte
NT n'est pas cette clé. Une identité qui ne détient qu'une de ces choses peut servir certains
protocoles et jamais les autres, quoi que la personne tape. L'annuaire de go-authn
enregistre donc **ce que chaque personne peut prouver**, et `authnd check` affiche, avant
que quoi que ce soit ne soit redémarré, qui pourrait recevoir un ticket Kerberos et qui ne le
pourrait jamais :

```
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself
```

C'est la sortie même d'authnd v0.11.0 : [en entier]({{< relref "/authnd/check.md" >}}).

## Jugé par les outils des autres {#judged-by-other-peoples-tools}

Un jeu d'essai construit à partir d'une lecture d'un protocole ne peut que confirmer cette lecture.
Les serveurs sont donc lus par des clients qu'ils n'ont pas écrits : le propre
`ldapsearch` d'OpenLDAP se lie à authnd, le propre `kinit` du MIT obtient des tickets de son royaume,
et OpenSSH lit les certificats et les KRL qu'émet authn-bridge.
