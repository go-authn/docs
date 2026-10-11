---
title: "Une personne qui change son propre mot de passe"
linkTitle: "Changer un mot de passe"
weight: 50
description: "La seule écriture qu'accepte authnd : le mot de passe d'une personne, par elle-même, en RFC 3062 ou par un modify RFC 4511, toujours avec l'ancien mot de passe, réécrit dans le fichier qui la déclare."
tags: [authnd, mots de passe, ldappasswd]
---

Une personne peut changer **son propre** mot de passe, et celui de personne d'autre, par
l'opération password modify de RFC 3062 (ce qu'envoie `ldappasswd`) ou par un modify
RFC 4511. Dans les deux cas, **le mot de passe actuel doit être envoyé avec le nouveau,
quelle que soit la façon dont la connexion s'est liée**. Une session liée avec un
[jeton OAUTHBEARER]({{< relref "/authnd/tokens.md" >}}) — de courte durée, et
peut-être à un seul facteur — pourrait sinon le transformer en un mot de passe permanent qui
fonctionne aussi pour `kinit`.

C'est le comportement de ppolicy d'OpenLDAP avec `pwdSafeModify` activé, avec les
codes de résultat que renvoie son `ppolicy.c`. RFC 3062 §3 le permet : « If oldPasswd is
not present, the server MAY use other policy to determine whether or not to
change the password. »

## Avec `ldappasswd` {#with-ldappasswd}

`-t` est un fichier contenant l'ancien mot de passe, `-T` un fichier contenant le nouveau ; `-A` et
`-S` les demandent à la place.

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

L'ancien mot de passe cesse aussitôt de fonctionner, pour une liaison et — avec un
[royaume]({{< relref "/authnd/kerberos.md#a-password-changed-over-ldap" >}}) —
pour `kinit`. Le serveur le dit dans sa sortie :

```
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password
```

authnd ne génère pas de mot de passe : une requête sans nouveau mot de passe est refusée
avec `unwillingToPerform` (*this server does not generate passwords: send the
one you want*). Un mot de passe qu'il aurait inventé devrait être renvoyé sur la
connexion, et le seul endroit où il est sûr d'aboutir est l'historique de défilement
d'un terminal.

## Avec `ldapmodify` {#with-ldapmodify}

Le changement est une **suppression de l'ancienne valeur suivie d'un ajout de la nouvelle,
en une seule requête**. RFC 4511 §4.6 applique les changements d'un modify dans l'ordre et
de façon atomique, si bien que la suppression — et toute la requête avec elle — échoue sauf si la
valeur supprimée est celle qui est enregistrée :

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

Un `replace` seul ne prouve rien, et tout ce qui n'est pas `userPassword` n'est pas
quelque chose que ce serveur modifie :

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

Un modify qui demande un mot de passe **et** autre chose est refusé en entier :
un modify est atomique, et en honorer la moitié annoncerait un succès pour
quelque chose que personne n'a demandé.

## Qui peut changer quoi {#who-can-change-what}

| requête | réponse |
|---|---|
| pas d'ancien mot de passe, ou un `replace: userPassword` seul | `insufficientAccessRights` |
| un ancien mot de passe qui n'est pas l'actuel | `unwillingToPerform` |
| l'entrée de quelqu'un d'autre | `insufficientAccessRights`, *a password may be changed only by the person it belongs to* |
| une connexion anonyme | `insufficientAccessRights`, *an anonymous connection has not said who it is* |
| quelqu'un sans aucun mot de passe — qui n'a pu se lier qu'avec un jeton | `unwillingToPerform` : un jeton porteur n'est pas un mot de passe, et ne définit pas le premier. Il se définit dans la configuration, côté administration |
| quelqu'un servi depuis un bloc `users` | `unwillingToPerform` : authnd lit ces sources et ne les écrit pas |
| le fichier ne peut pas être écrit | `other` (80), *the password could not be written* ; la raison est dans la sortie du serveur |

L'avant-dernier cas, avec le binaire de la version publiée, pour dora, qui vient d'une
base de données SQLite :

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=dora,ou=people,dc=example,dc=org -y dora.pwin -t dora.pwin -T dora.new
Result: Server is unwilling to perform (53)
Additional info: dora is served from a sqlite database, which this server reads and does not write
```

La personne est reconnue **par identité, non par DN** : le nom propre de la session doit
être exactement celui de la cible, octet pour octet, si bien qu'une session liée comme `uid=Backup`
ne peut pas changer le mot de passe de `backup` même si les deux DN sont égaux à la comparaison. Cela
et le [refus des noms qui ne diffèrent que par la casse]({{< relref "/authnd/people.md#order-and-the-one-exception" >}})
sont deux contrôles qui ne dépendent pas l'un de l'autre.

## Où le nouveau mot de passe est écrit {#where-the-new-password-is-written}

Dans **le fichier qui déclare la personne**, et nulle part ailleurs :

- un bloc `user` avec `password_file` voit **ce fichier** réécrit, en conservant
  son propriétaire et son groupe là où le processus le peut, et son mode restreint à
  0600 au plus — jamais élargi ;
- un bloc `user` avec `password` en ligne voit le fichier de configuration réécrit
  avec la nouvelle valeur, en conservant ses commentaires, son ordre et son mode ;
- un bloc `user` avec seulement un `nt_hash` ne reçoit pas de mot de passe : cela
  changerait ce qui peut prouver l'identité de la personne, ce qui est un changement de la configuration.

Chaque écriture va dans un fichier temporaire **dans le même répertoire**, puis un
renommage — si bien qu'un disque plein ou un plantage laisse l'ancien mot de passe, pas un fichier
vide. Cela demande un accès en écriture au répertoire. Sous l'unité fournie par le paquet,
`ProtectSystem=strict` le retire, et un changement est refusé ainsi :

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f safe.ldif
ldap_modify: Other (e.g., implementation specific) error (80)
	additional info: the password could not be written
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

avec la raison dans la sortie du serveur :

```
changing the password for alice: etc/authnd/passwords/alice.pw: open etc/authnd/passwords/.hcldir-863420940: permission denied
```

Gardez donc les mots de passe dans un répertoire à part, accessible en écriture au service,
et la configuration en lecture seule pour lui — le
[complément `ReadWritePaths=`]({{< relref "/authnd/install.md#the-configuration-directory" >}}).
Une personne dont le mot de passe est écrit en ligne exigerait que `/etc/authnd` lui-même soit
accessible en écriture, ce qui permettrait aussi au service de réécrire sa propre configuration.

Après une écriture réussie, les fichiers de configuration sont relus **pour les
blocs `user` seulement** : une modification sans rapport qui attend sur le disque ne prend pas effet
à moitié parce que quelqu'un a changé un mot de passe. Tout le reste attend toujours
un redémarrage. Les fichiers sont tout de même lus en entier, si bien que si l'un d'eux ne
se charge plus, le mot de passe est écrit et le client reçoit *the password
was written but this server did not reload it* — le serveur en cours d'exécution garde
l'ancien jusqu'à son redémarrage.
