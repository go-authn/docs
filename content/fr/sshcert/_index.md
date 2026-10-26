---
title: "sshcert"
linkTitle: "sshcert"
weight: 40
description: "L'extension de délégation de domaine GÉANT / EuroHPC des certificats utilisateur SSH, et sshcert-authorize, la commande qui refuse en cas de doute et à laquelle sshd demande si un certificat est destiné à cet hôte."
tags: [sshcert, ssh, eurohpc]
---

**Un certificat émis par l'AC d'une fédération n'est pas, à lui seul, une permission pour chaque
hôte qui fait confiance à cette AC.** L'AC SSH de l'EuroHPC Federation Platform écrit les
hôtes auxquels un certificat est destiné dans une extension,
`ssh-domain-grant@core.aai.geant.org`, et `sshd` l'ignore. go-authn/sshcert
lit et écrit cette extension, et sa commande, `sshcert-authorize`, est ce que
`sshd` exécute pour la faire respecter. Go pur, `CGO_ENABLED=0`. Ces pages décrivent
la v0.1.9.

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.9
$ sshcert-authorize -version
sshcert-authorize v0.1.9
```

| | |
|---|---|
| [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}) | l'`AuthorizedPrincipalsCommand` : ce qu'elle vérifie, ce qu'elle refuse, et comment sshd l'appelle |

## L'extension {#the-extension}

Sa donnée est un tableau JSON compact de motifs d'hôtes, `["login.example.org"]`. Un
`*` correspond à **un ou plusieurs** caractères à l'intérieur d'une seule étiquette, et les noms se comparent
sans tenir compte de la casse :

| motif | correspond à | ne correspond pas à |
|---|---|---|
| `login.example.org` | `login.example.org`, `LOGIN.example.org` | `www.login.example.org` |
| `*.example.org` | `a.example.org` | `example.org`, `a.b.example.org` |
| `prod-*.example.org` | `prod-1.example.org` | `prod-.example.org` |
| `*.*.example.org` | `a.b.example.org` | `a.example.org` |

La lecture est stricte : seul ce qu'écrit l'encodeur est accepté. Pas
d'espace, rien après `]`, pas d'échappements JSON, pas de doublons, au plus 64
motifs, chacun fait de lettres, de chiffres, de traits d'union et de `*`, en étiquettes de 1 à 63
octets, au plus 253 octets, et **pas de `*` dans l'étiquette la plus à droite**. `null`, les objets,
les nombres et les tableaux imbriqués sont refusés. `[]` est accepté, et ne délègue aucun hôte.

Une délégation présente et malformée n'est jamais signalée comme absente. Cette
différence est toute la raison d'être de la commande.

## Qui l'utilise {#who-uses-it}

- **[authn-bridge]({{< relref "/authn-bridge/certificates.md#the-eurohpc-ssh-ca-profile" >}})**
  écrit l'extension pour les `ssh_domain_grants` d'un client, après avoir vérifié chaque
  motif avec le `ValidatePattern` de ce paquet.
- Le serveur SFTP de **go-fileshare** la lit avec `ssh_domains`, et refuse un
  certificat sans délégation à moins que `ssh_accept_ungranted` ne soit défini.
- **sshcert-authorize** est la même vérification pour un `sshd` ordinaire.

## Licence {#licence}

BSD-3-Clause.
