---
title: "Un second facteur, sur un protocole à un seul champ"
linkTitle: "Second facteur"
weight: 70
description: "Le bloc mfa : un code à usage unique au bout du mot de passe, comment il est découpé et vérifié, ce qui est compté contre qui, et qui ne peut pas se lier sous ce régime."
tags: [authnd, mfa, totp]
---

La liaison simple d'LDAP transporte un nom et un mot de passe, rien d'autre — aucune place
pour un code, aucun aller-retour pour en demander un, et un client qui parle LDAP n'en
apprendra pas. Le code va donc au **bout** du mot de passe, ce que font les
appliances qui font cela, et ce que les gens savent déjà taper :

```
password:  hunter2314159
           ^^^^^^^ ^^^^^^
           password  the six digits on their phone
```

```hcl
mfa {
  factors        = 2
  distinct_kinds = true     # two things they KNOW are not two factors
  # digits = 6, period = 30 (seconds) and window = 1 are the defaults
}

user "tess" {
  password_file = "/etc/authnd/passwords/tess.pw"
  totp_secret   = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"   # ⛔ this IS the second factor
}
```

| clé | défaut | |
|---|---|---|
| `factors` | 2 | 1 est refusé (*a password and nothing else: remove the block, or ask for 2*) ; au-delà de 2 aussi, puisqu'une liaison transporte un mot de passe et un code, et pas de troisième chose |
| `distinct_kinds` | `false` | les facteurs doivent être de natures différentes — ce qu'on entend normalement par « deux facteurs » |
| `digits` | 6 | de 6 à 10 (RFC 4226) |
| `period` | 30 | secondes de validité d'un code |
| `window` | 1 | pas acceptés de part et d'autre de l'instant présent, pour des horloges qui diffèrent. Chaque pas est un pas de temps de devinette offert à quelqu'un d'autre : le régler en connaissance de cause |
| `readers` | `false` | si les [lecteurs]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}}) portent aussi un code. Un compte de service n'a pas de téléphone ; celui qui en a un reçoit un `totp_secret` dans son bloc `reader` |

Le secret peut tout aussi bien venir d'une colonne de base de données (la cinquième) ou d'un
attribut LDAP (`totp_attribute`) ; voir [les personnes]({{< relref "/authnd/people.md" >}}).
Un `totp_secret` de moins de 128 bits (RFC 4226 R6) dans un bloc `user` ou `reader`
arrête le serveur, en nommant la personne, plutôt que de faire échouer plus tard chacune
de ses connexions :

```
$ authnd check cases/shorttotp.hcl
authnd: user "alice": totp_secret is 80 bits, and RFC 4226 requires at least 128: enrol again with a longer secret
```

## Qui ne peut pas se lier sous ce régime {#who-cannot-bind-under-it}

```
$ authnd check mfa
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS
alice  the configuration file  a password                             uid and cn
tess   the configuration file  a password and a one-time-code secret  uid and cn

a bind carries a password with a 6-digit code after it, of two different kinds
alice has no second factor here, and cannot bind while one is required
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

C'est la question à poser avant d'activer le bloc.

## À quoi ressemblent les liaisons {#what-the-binds-look-like}

La même configuration, servie ; le code de tess est calculé à partir de son secret au
moment de la liaison :

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.only
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
dn:uid=tess,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.badcode
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.code
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin
dn:cn=reader,dc=example,dc=org
```

`tess.only` est son mot de passe sans code ; `tess.both` son mot de passe et le
code courant, envoyés deux fois ; `tess.badcode` son mot de passe et `000000` ;
`alice.code` le mot de passe d'alice et six chiffres. Le client apprend une seule chose —
*invalid credentials* — quelle que soit la moitié fausse : laquelle, c'est un fait sur
le compte, et le dire à quelqu'un qui n'a rien prouvé resserre sa prochaine
tentative. La sortie du serveur, elle, le dit :

```
tess was refused: mfa: 2 factor(s) needed, 0 answered: your password (knowledge): directory: wrong password; your authenticator app (possession): not looked at, since the password in front of it was wrong
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code has already been used
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
alice was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): not available
  your authenticator app: mfa: this factor cannot be asked here: totp: nobody enrolled an authenticator for this person
```

## Ce qui découle du champ unique {#what-follows-from-the-one-field}

- **Le découpage se fait à la longueur.** Les `digits` derniers caractères sont le code. Un
  mot de passe qui se termine par des chiffres ne pose pas de problème — c'est pourquoi le mot de passe
  de tess seul a été lu comme un mauvais mot de passe suivi d'un code. Un champ *pas plus long*
  qu'un code est refusé plutôt que deviné, car un mot de passe court ne peut pas
  être distingué d'un code.
- **Les deux moitiés sont toujours vérifiées.** S'arrêter tôt sur un mauvais mot de passe
  dirait, par le temps mis, quelle moitié était fausse.
- **Un code ne sert qu'une fois.** Il est valide pendant un pas entier, donc un serveur qui
  en accepte un deux fois accepte un rejeu ; chaque pas jusqu'au dernier accepté
  est refusé, pas seulement le même.
- **Les devinettes sont limitées par nom**, avec les valeurs par défaut de go-authn/totp : après cinq
  mauvais codes d'affilée, une personne est refusée pendant quinze minutes, bon
  code compris, et après cent, la personne est bloquée jusqu'au redémarrage
  d'authnd. Les compteurs sont tenus en mémoire, par processus.
- **Seul un code derrière le bon mot de passe est compté** : sinon quiconque
  connaît un nom pourrait geler son titulaire en cinq liaisons. Derrière un mauvais mot de passe,
  le code est quand même calculé, contre rien qui s'en souvienne — la première
  ligne de la sortie ci-dessus, *not looked at*.
- **Un lecteur est compté sous son DN tel que la configuration l'écrit**, si bien que
  `CN=Reader` n'obtient pas de nouveau crédit à lui.
- **Personne d'enrôlé n'est pas un mauvais code.** Une personne sans secret n'a
  rien répondu plutôt que mal répondu, et la sortie du serveur
  dit *nobody enrolled an authenticator for this person*.

## Pas avec un royaume {#not-with-a-realm}

Un bloc `kerberos` et un bloc `mfa` dans une même configuration sont refusés : un
`kinit` prouve le mot de passe et rien d'autre, et ce KDC n'a pas de
pré-authentification à second facteur. Voir
[le royaume]({{< relref "/authnd/kerberos.md#not-beside-an-mfa-block" >}}).

## Les jetons, sous la même politique {#tokens-under-the-same-policy}

Un jeton à la liaison, avec un [bloc `oidc`]({{< relref "/authnd/tokens.md" >}}),
est compté d'après ce que son émetteur dit avoir vérifié — la revendication `amr`. Un jeton sans
`amr` vaut un facteur, et cette politique le refuse.
