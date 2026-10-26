---
title: "sshcert-authorize"
linkTitle: "sshcert-authorize"
weight: 10
description: "Ce que vérifie sshcert-authorize quand sshd l'exécute comme AuthorizedPrincipalsCommand, ce qu'elle refuse, et pourquoi un certificat sans délégation de domaine est refusé lui aussi."
tags: [sshcert, ssh, sshd, eurohpc]
---

`sshd` lui demande, pour chaque connexion par certificat, quels principals peuvent se connecter au
compte. Elle répond avec les principals du compte seulement si la délégation de domaine du certificat
nomme cet hôte ; sinon elle ne répond rien, et `sshd` refuse
le certificat. Elle prend les arguments, les drapeaux, la sortie et le format de journal du
`ssh-cert-authorize` de GÉANT, et diffère par ce qu'elle refuse.

## Comment sshd l'appelle {#how-sshd-calls-it}

```
# /etc/ssh/sshd_config
TrustedUserCAKeys /etc/ssh/efp-ssh-ca.pub
AuthorizedPrincipalsCommand /usr/local/bin/sshcert-authorize %u %k
AuthorizedPrincipalsCommandUser nobody
```

```sh
install -o root -g root -m 0755 sshcert-authorize /usr/local/bin/
echo login.example.org > /etc/ssh/cert-allowed-domain.conf
```

et, pour chaque compte local, les principals qui peuvent s'y connecter, un par ligne,
dans `/etc/ssh/auth_principals/<account>`. sshd n'exécute la commande que depuis un chemin
appartenant à root et que personne d'autre ne peut modifier.

`%u` est le compte auquel on se connecte. `%k` est le certificat, en base64 ; une ligne entière
`ssh-...-cert-v01@openssh.com BASE64` est lue aussi, et quand l'argument est
absent le certificat est lu sur l'entrée standard. Un troisième argument, quand il y en a un
(le `%t` de sshd), doit être le type du certificat, sinon le certificat est refusé.

| sortie | affiche | sshd |
|---|---|---|
| `0` | les principals du compte, un par ligne | laisse entrer le certificat si l'un de ses principals en fait partie |
| `1` | rien | le refuse |
| `2` | rien | le refuse : les arguments étaient erronés |

{{< callout type="info" >}}
**Elle ne vérifie ni la signature, ni l'AC, ni les dates de validité**

Rien dans la commande ne vérifie la signature du certificat ni sa
période de validité : sshd, qui fait confiance à l'AC par `TrustedUserCAKeys`,
s'en charge. La commande tranche une seule question : le certificat est-il
destiné à cet hôte et à ce compte.
{{< /callout >}}

## Ce qu'elle refuse {#what-it-refuses}

Dans l'ordre où elle vérifie :

1. un nom de compte vide, `.`, `..`, ou qui contient `/`, `\` ou un NUL ;
2. un hôte sans domaine configuré, ou dont le domaine n'est pas un nom d'hôte valide ;
3. un certificat qui ne s'analyse pas, une clé ordinaire, ou un certificat d'hôte ;
4. un `%t` qui n'est pas le type du certificat ;
5. avec `--krl`, un certificat que la liste révoque, ou **tous** les certificats quand
   la liste ne peut pas être lue ou a expiré ;
6. une délégation de domaine présente et malformée, **quels que soient les drapeaux** ;
7. **aucune délégation de domaine**, sauf avec `--allow-no-grant` ;
8. une délégation dont aucun des motifs ne correspond à l'un des noms de l'hôte ;
9. un compte sans fichier de principals, ou avec un fichier vide.

Les noms de l'hôte sont `--domain`, ou la variable que nomme `--domain-env`, ou les
lignes de `--domain-file` (lignes vides et commentaires `#` ignorés ; plusieurs lignes sont
plusieurs noms, dont n'importe lequel peut correspondre).

Avec des certificats signés par une AC de test pour le compte `alice`, dont le
fichier de principals liste `a1b2c3@univ-example.example`, sur un hôte appelé
`login.hpc.example.org` :

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
```

La dernière ligne est la réponse que lit sshd ; les lignes qui la précèdent sont le journal, ici sur
l'erreur standard. Un certificat qui délègue d'autres hôtes :

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-other-cert.pub)"
INFO: action=cert_processed serial=1003 key_id="a1b2c3@univ-example.example other host" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="domain not granted" grant=["*.elsewhere.example.net"] serial=1003 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

Un certificat sans délégation :

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="no domain grant" serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

Un compte sans fichier de principals, et une clé ordinaire :

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals bob "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=bob domain=login.hpc.example.org reason="no principals file for the user" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice.pub)"
WARNING: action=denied user=alice domain=login.hpc.example.org reason="a ssh-ed25519 key, not a certificate"
```

Chacune de ces exécutions est sortie avec `1`, et n'a rien affiché sur la sortie standard.

## Pourquoi un certificat sans délégation est refusé {#why-a-certificate-with-no-grant-is-refused}

Le `ssh-cert-authorize` de GÉANT laisse passer un certificat sans délégation de domaine
(« might be valid for non-domain-based auth »), ainsi qu'un certificat dont il ne peut pas
analyser la délégation, ou dont la délégation est vide. Dès lors, un site qui fait confiance à **deux** AC dans
`TrustedUserCAKeys` (celle de la fédération, et la sienne pour son personnel, ou une AC de test)
laisse entrer un certificat de la seconde AC sur chaque hôte, pour n'importe quel principal d'un
fichier de principals, sans aucune vérification de domaine. Le filtre de domaine n'est un filtre
que si un certificat qui ne dit pas où il peut être utilisé est refusé.

Un site qui veut vraiment le comportement de GÉANT le dit, et la commande journalise chaque
fois qu'elle l'applique :

```
$ sshcert-authorize --syslog=false --allow-no-grant --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=no_grant_allowed user=alice domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
```

Même alors, une délégation présente mais malformée est refusée.

## `--krl` {#krl}

`RevokedKeys` est la vérification propre de sshd, faite avant que la commande ne s'exécute, pour chaque clé
et chaque certificat, et elle révoque aussi une clé d'AC ; préférez-la. `--krl FILE` vérifie une
KRL OpenSSH dans la commande, et ajoute ce que sshd ne fait pas : elle refuse
**tous** les certificats une fois la liste expirée (son extension `expires@go-authn.github.io`,
que sshd ignore), et tous les certificats quand la liste ne peut pas être
lue. Une liste sans expiration est utilisée sans expiration.

Trois exécutions : avec la KRL qu'écrit [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}),
d'abord une liste à jour, puis celle qui refuse en cas de doute, qu'il écrit quand la liste de l'émetteur
[expire]({{< relref "/authn-revokd/lapse.md" >}}) ; et enfin avec `--krl` qui nomme un fichier
qui n'existe pas :

```
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="certificate revoked" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
$ sshcert-authorize --syslog=false --krl missing.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="KRL unreadable: open missing.krl: no such file or directory" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

La deuxième exécution est refusée parce que la liste qui refuse en cas de doute révoque la **clé de l'AC**
du certificat : la vérification couvre la clé propre du certificat, son numéro de série et son identifiant de clé, et
la clé qui l'a signé. La troisième est refusée parce que la liste ne peut pas être lue : l'absence
de liste n'est pas prise pour « rien de révoqué ».

## Drapeaux {#flags}

```
$ sshcert-authorize -help
usage: sshcert-authorize [flags] USER [CERTIFICATE [KEYTYPE]]

An sshd AuthorizedPrincipalsCommand (%u %k) that refuses a certificate whose
ssh-domain-grant@core.aai.geant.org extension does not grant this host, or that has none.

  -allow-no-grant
    	let in a certificate with no domain grant (GÉANT's behaviour); a malformed grant is still refused
  -debug
    	log details
  -domain string
    	the host's domain (overrides --domain-env and --domain-file)
  -domain-env string
    	environment variable holding the host's domain
  -domain-file string
    	file holding the host's domain, one name per line (default "/etc/ssh/cert-allowed-domain.conf")
  -extension string
    	name of the domain-grant extension (default "ssh-domain-grant@core.aai.geant.org")
  -krl string
    	refuse certificates this OpenSSH KRL revokes, and every certificate once it has expired or cannot be read
  -principals-dir string
    	directory of principals files, one per user (default "/etc/ssh/auth_principals")
  -syslog
    	log to syslog, facility AUTH (--syslog=false: to stderr) (default true)
  -version
    	print the version and exit
```

Les **journaux** sont des lignes `key=value` (`action=cert_processed`, `action=denied`,
`action=authorized`, avec `serial` et `ca_fingerprint`), vers syslog, facilité
AUTH, par défaut. sshd jette l'erreur standard de la commande, gardez donc syslog activé
en production ; `--debug` écrit aussi tout sur l'erreur standard. Une valeur qui
vient du client, comme le nom de compte, est mise entre guillemets quand elle contient une
espace, un `=`, un guillemet ou un caractère de contrôle, de sorte qu'elle ne peut pas falsifier un champ du journal.

**`-version`** affiche la version du module, dans un binaire de version comme dans un
binaire compilé par `go install` :

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.9
$ sshcert-authorize -version
sshcert-authorize v0.1.9
```

Avant la v0.1.5, un binaire issu de `go install` affichait `sshcert-authorize dev`.
