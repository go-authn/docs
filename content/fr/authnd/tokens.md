---
title: "Un jeton à la liaison, dans un champ qui n'est pas le mot de passe"
linkTitle: "Jetons (OIDC)"
weight: 75
description: "Le bloc oidc : un jeton OpenID Connect transporté dans une liaison SASL OAUTHBEARER, combien de facteurs il compte, et ce qui est refusé."
tags: [authnd, oidc, oauthbearer, sasl]
---

[go-authn/oidc]({{< relref "/libraries/_index.md" >}}) vérifie un jeton et en tire une
identité. La façon évidente d'en porter un jusqu'à un serveur LDAP est le champ du mot de passe,
et cela fonctionne une fois puis cesse : le champ du mot de passe est l'endroit où le
[bloc `mfa`]({{< relref "/authnd/mfa.md" >}}) retire le code au bout, et
un jeton ne peut pas être les deux.

Le jeton va donc là où le protocole lui a prévu une place. Les identifiants d'une liaison
**SASL** sont une chaîne d'octets à la forme propre au mécanisme, et la forme
`OAUTHBEARER` de RFC 7628 est un en-tête GS2 suivi de paires clé/valeur, dont l'une
est `auth=Bearer <token>` :

```
n,,^Aauth=Bearer eyJ…^A^A
```

Le champ du mot de passe n'est pas touché. Sur un même écouteur, au même moment, une
personne peut taper un mot de passe avec un code au bout et une autre envoyer un
jeton.

```hcl
oidc {
  issuer   = "https://login.example.org/realms/staff"   # the "iss" a token must carry, and where discovery starts
  audience = "ldap"                                     # this server's client id at the provider

  # username_claim = "preferred_username"   which claim names the person here
  # jwks_url       = "…"                    skips discovery, for a provider that does not publish it
  # allow_plaintext = true                  only when TLS is terminated in front of this process
}
```

`issuer` et `audience` sont obligatoires. Sans `username_claim`, le nom est
`preferred_username`, puis `email` quand `email_verified` est vrai, puis `sub`.
Avec le bloc, le root DSE annonce le mécanisme :

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' supportedSASLMechanisms
dn:
supportedSASLMechanisms: OAUTHBEARER
```

Sans lui, chaque liaison SASL reçoit `authMethodNotSupported` — *pas de cette
façon*, ce qui envoie un client ailleurs que *mauvais mot de passe*.

## La découverte a lieu au démarrage {#discovery-happens-at-startup}

Le document de découverte et les clés du fournisseur sont lus au démarrage du serveur,
et par `check`. Un fournisseur injoignable arrête le serveur là où
quelqu'un regarde, plutôt que de refuser chaque liaison plus tard :

```
$ authnd check cases/oidc.hcl
authnd: oidc "https://127.0.0.1:1/realms/staff": oidc: reading https://127.0.0.1:1/realms/staff/.well-known/openid-configuration: Get "https://127.0.0.1:1/realms/staff/.well-known/openid-configuration": dial tcp 127.0.0.1:1: connect: connection refused
```

Un émetteur qui n'est pas en `https` est refusé, sauf en bouclage :

```
$ authnd check cases/oidc-http.hcl
authnd: oidc "http://login.example.org/realms/staff": oidc: http://login.example.org/realms/staff is not https: the key set decides every signature, and over cleartext so does anybody on the way
```

## Combien de facteurs vaut un jeton ? {#how-many-factors-is-a-token}

**Ce que l'émetteur dit avoir vérifié, et rien de plus.** Un jeton porte
l'`amr` de RFC 8176, les méthodes que le fournisseur a utilisées. C'est la seule preuve
qui existe, c'est donc ce que compte la politique `mfa`, **par nature** :

| méthode `amr` | nature |
|---|---|
| `pwd`, `pin`, `kba`, `mca` | connaissance |
| `otp`, `hwk`, `swk`, `sms`, `tel`, `sc`, `pop`, `user`, `wia`, `mfa` | possession |
| `fpt`, `face`, `iris`, `retina`, `vbm`, `geo` | inhérence |
| toute autre | inconnue, ce qui ne satisfait jamais `distinct_kinds` |
| aucun `amr` | un facteur, possession — le jeton lui-même |

Deux méthodes d'une même nature font un facteur. L'alternative serait que ce serveur
invente un second facteur que personne n'a accompli ; et un serveur qui croit
l'émetteur sur *qui* est cette personne n'a pas de raison distincte de ne pas le croire sur
*comment* il l'a vérifié.

Avec un bloc `mfa`, `check` le dit :

```
$ authnd check sasl
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS
alice  the configuration file  a password                             uid and cn
tess   the configuration file  a password and a one-time-code secret  uid and cn

a bind carries a password with a 6-digit code after it, of two different kinds
or a token from http://127.0.0.1:18481, over SASL OAUTHBEARER over TLS
  a token counts for the factors its amr claim names, so one with no amr is refused by this policy
alice has no second factor here, so a password cannot satisfy this policy; a token whose amr names two kinds still can
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

alice n'a pas de `totp_secret`, si bien qu'un mot de passe avec un code ne peut jamais suffire
dans son cas ; un jeton dont l'`amr` nomme deux natures le peut, comme le montre la première liaison
ci-dessous.

## À quoi ressemblent les liaisons {#what-the-binds-look-like}

L'émetteur est ici un petit fournisseur de test en bouclage, et `oidctool` un client de
test écrit pour ces pages : il signe un jeton pour le nom donné, avec
l'`amr` donné, l'envoie dans une liaison `OAUTHBEARER` (avec un `authzid` quand un
cinquième argument en nomme un), et affiche le code de résultat de la liaison et les
identifiants SASL du serveur. Contre la configuration ci-dessus, en `ldaps://` :

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 0, serverSaslCreds 

$ ./oidctool alice '' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","kba"]' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls tess
bind result 14, serverSaslCreds {"status":"insufficient_scope","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}

$ ./oidctool zed '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 14, serverSaslCreds {"status":"invalid_token","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}
```

0 est le succès, 49 `invalidCredentials`, 14 `saslBindInProgress`. Un jeton
`["pwd","kba"]` nomme deux méthodes d'une même nature, il compte donc une fois. Et
vers la même configuration sans `cert_file` ni `key_file`, sur un écouteur
en clair :

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3893 clear
bind result 13
```

13 est `confidentialityRequired` : un jeton n'est pas accepté sur une connexion
qui n'est pas chiffrée.

Ce que le serveur a écrit pour les quatre liaisons refusées sur `ldaps://` :

```
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: the token is for "alice" and asks to act as "tess"; this server does not delegate
zed was refused: the token verified, and no source here publishes anybody by that name
```

et pour celle en clair :

```
a token was refused: OAUTHBEARER was offered over a connection that is not encrypted, and allow_plaintext is not set
```

Une liaison `OAUTHBEARER` réussie laisse la connexion liée comme
`uid=<name>,ou=people,<base_dn>`, écrit comme l'est chaque autre entrée.

## Ce qu'il refuse {#what-it-refuses}

- **Un jeton en clair.** Un jeton porteur n'a pas besoin d'autre moitié : quiconque le lit
  sur le réseau est cette personne jusqu'à son expiration. `allow_plaintext = true`
  existe pour un déploiement qui termine TLS devant ce processus, et
  `check` dit alors *a token may cross this socket in the clear*.
- **Une demande d'être quelqu'un d'autre.** L'en-tête GS2 peut nommer un `authzid`. Un
  jeton pour alice portant une demande d'agir en tant que tess est refusé, et non traité
  discrètement comme l'un ou l'autre.
- **Un jeton pour quelqu'un qu'aucune source ici ne publie.** Le client reçoit seulement
  `invalid_token` ; quels noms existent n'est pas une information à livrer une devinette
  à la fois. La raison est dans la sortie du serveur.
- **La liaison de canal (channel binding).** Un en-tête GS2 avec `p=` — le client exige
  la liaison de canal — est refusé : ce serveur ne la fait pas, et accepter
  l'en-tête sans rien lier laisserait le client croire que le canal a été
  vérifié.
- **Un mécanisme que ce serveur ne parle pas**, avec `authMethodNotSupported`.

Un refus du jeton lui-même est celui de RFC 7628 §3.2.3 : une erreur JSON portant
`openid-configuration`, renvoyée comme `saslBindInProgress` pour que le client puisse
envoyer le `^A` qui clôt l'échange. Un jeton qui se vérifie mais ne
satisfait pas la politique `mfa` reçoit simplement `invalidCredentials`, comme le montrent
les deuxième et troisième liaisons ci-dessus.

{{< callout type="info" >}}
**Un jeton ne définit pas de mot de passe**

Une personne qui ne s'est jamais connectée qu'avec un jeton ne peut pas se servir de cette session pour
se donner un premier mot de passe, et une personne qui en a un doit toujours l'envoyer
pour le changer. Voir [changer un mot de passe]({{< relref "/authnd/passwords.md" >}}).
{{< /callout >}}
