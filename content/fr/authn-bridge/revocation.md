---
title: "Ce qu'il révoque, et comment les serveurs l'apprennent"
linkTitle: "Révocation"
weight: 60
description: "La KRL et la CRL signées et datées qu'authn-bridge publie pour les certificats qu'il a révoqués, et le transmetteur Shared Signals qui atteint ce qu'aucune liste ne peut nommer."
tags: [authn-bridge, révocation, krl, crl, signaux partagés]
---

Désactiver une personne ou un établissement ([l'API d'administration]({{< relref "/authn-bridge/admin.md" >}}))
met fin à tout ce qui revient vers le fournisseur : jetons de rafraîchissement, `/userinfo`,
nouveaux certificats, mots de passe d'application. Ce qu'il a déjà distribué est
vérifié ailleurs, par rapport à des clés, et trois mécanismes l'atteignent :

| identifiant | repris par |
|---|---|
| un certificat SSH signé par cette AC | la **KRL**, `GET /ssh/krl`, avec sa signature à `/ssh/krl.sig` |
| un certificat client X.509 | la **CRL**, `GET /x509/crl` |
| un jeton d'accès, un certificat opkssh, tout ce qu'un serveur vérifie seul | un événement **Shared Signals** `session-revoked` |

La révocation est définitive. Réactiver une personne ne lui rend pas ses
certificats ; elle en reçoit de nouveaux. Une liste dont on pourrait retirer une révocation
est une liste que quiconque atteint l'API d'administration pourrait modifier.

## Les listes {#the-lists}

Les deux sont émises comme le dit le protocole de go-authn/revocation, afin qu'elles puissent transiter
par n'importe quoi (un miroir, du HTTP simple, un fichier) et rester vérifiables par quiconque
les lit :

| | KRL | CRL |
|---|---|---|
| format | OpenSSH `PROTOCOL.krl`, écrite par go-authn/krl : ce que lisent le `RevokedKeys` de `sshd` et `ssh-keygen -Q` | DER, RFC 5280 |
| signée | par une SSHSIG détachée avec la clé de l'AC SSH, espace de noms `krl@go-authn.github.io` | par l'AC qui signe les certificats |
| à jour jusqu'à | son extension `expires@go-authn.github.io` (que sshd ignore) | son `nextUpdate` |
| ordonnée par | sa `krl_version`, puis sa date de génération | son CRL Number, puis `thisUpdate` |

Chaque liste indique qu'elle cesse d'être à jour **une heure** après son émission. Une liste est
conservée et servie telle quelle jusqu'à mi-chemin de cette échéance, ou jusqu'à ce que quelque chose soit
révoqué ; la requête suivante reçoit alors une nouvelle émission. Une émission n'est jamais datée d'avant
celle qu'elle remplace, même si l'horloge recule, puisqu'un lecteur refuse une
émission antérieure de la même version comme un retour en arrière. Le CRL Number augmente à chaque
émission.

La KRL d'un fournisseur de test sans rien de révoqué :

```
$ curl -s -D - -o var/bridge.krl http://127.0.0.1:28473/ssh/krl
HTTP/1.1 200 OK
Cache-Control: max-age=60
Content-Type: application/octet-stream
Etag: "c543d4dd9acedf716b34ea3af912a62f"
Date: Mon, 26 Oct 2026 11:21:59 GMT
Content-Length: 130

$ ssh-keygen -Q -l -f var/bridge.krl
# KRL version 0
# Generated at 20261026T122159
# Comment: go-authn/bridge http://127.0.0.1:28473
```

**L'ETag est celui du contenu.** Un lecteur interroge avec `If-None-Match`, et reçoit
`304` tant que l'émission qu'il détient est toujours celle servie ; puisque le contenu
change au moins toutes les demi-heures, un lecteur qui interroge ne garde jamais une copie au-delà de son
expiration :

```
$ curl -s -o /dev/null -H 'If-None-Match: "d2ab8a48f397a1f55bf3e8e513a4dea9"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl
304
```

**La signature est récupérée avec `If-Match`** sur l'ETag de la liste. Une liste
réémise entre-temps répond `412`, plutôt qu'une signature qui ne lui
correspond pas :

```
$ curl -s -o var/bridge.krl.sig -H 'If-Match: "d2ab8a48f397a1f55bf3e8e513a4dea9"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
200
$ curl -s -o /dev/null -H 'If-Match: "stale"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
412
```

`ssh-keygen` vérifie la signature, et la refuse dans tout autre espace de noms :

```
$ ssh-keygen -Y verify -f allowed -I bridge -n krl@go-authn.github.io -s bridge.krl.sig < bridge.krl
Good "krl@go-authn.github.io" signature for bridge with ED25519 key SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

où `allowed` est la ligne
`bridge namespaces="krl@go-authn.github.io" <the CA key from /ssh/config>`.

La CRL, émise quinze secondes plus tard :

```
$ openssl crl -inform DER -in var/bridge.crl -noout -text
Certificate Revocation List (CRL):
    Version 2 (0x1)
    Signature Algorithm: ecdsa-with-SHA256
    Issuer: CN=go-authn bridge NFS client CA
    Last Update: Oct 26 11:22:15 2026 GMT
    Next Update: Oct 26 12:22:15 2026 GMT
    CRL extensions:
        X509v3 Authority Key Identifier: 
            AE:A8:A1:10:13:A3:B3:EA:FD:73:42:E2:71:56:D2:7D:DF:AA:4D:2C
        X509v3 CRL Number: 
            1793013735127
No Revoked Certificates.
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:44:02:20:79:e1:1f:d6:ae:86:01:01:41:d3:b2:2e:7d:20:
        13:3c:12:6c:7a:ee:3e:e9:e0:6f:33:28:af:ba:26:a4:06:5c:
        02:20:4a:b3:14:47:1c:23:14:f9:96:96:f0:78:40:28:2d:bd:
        c8:f3:37:75:24:fc:56:50:ba:3d:58:95:4e:b2:d7:dc
```

Un certificat reste dans sa liste jusqu'à son expiration : un certificat expiré est
refusé partout sans être listé.

### Qui les lit {#who-reads-them}

- Un `sshd` ordinaire, ou nginx et d'autres serveurs TLS :
  [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) récupère les listes,
  ne garde que celles qui se vérifient, les écrit là où les serveurs les lisent, et
  refuse en cas de doute pour sshd quand une liste expire.
- [go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)
  les récupère et les vérifie lui-même, et refuse les certificats du fournisseur
  tant qu'il ne détient aucune liste à jour.

## Shared Signals {#shared-signals}

Un jeton d'accès ou un certificat opkssh est vérifié là où il est utilisé, et aucune
liste ne peut le nommer. Le fournisseur est donc un transmetteur OpenID Shared Signals : sur
`DisablePerson`, `RevokePerson` et `DisableIdP`, il met en file un événement CAEP
**`session-revoked`** (tout ce qui a été émis pour ce sujet avant l'heure de
l'événement est nul) pour chaque récepteur qui l'a demandé.

```hcl
state { ... }            # required: a queue a restart empties loses revocations
ssf {}                   # event_retention = "192h" by default

client "fileshare-ssf" { # a receiver: client credentials, scope ssf
  secret_file  = "/etc/authn-bridge/fileshare-ssf.secret"
  ssf_receiver = true
  audience     = ["fileshare"]
}
```

```
$ curl -s http://127.0.0.1:28473/.well-known/ssf-configuration | jq .
{
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "delivery_methods_supported": [
    "urn:ietf:rfc:8936"
  ],
  "configuration_endpoint": "http://127.0.0.1:28473/ssf/streams",
  "status_endpoint": "http://127.0.0.1:28473/ssf/streams/status",
  "add_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:add",
  "remove_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:remove",
  "verification_endpoint": "http://127.0.0.1:28473/ssf/streams/verify",
  "spec_version": "1_0",
  "authorization_schemes": [
    {
      "spec_urn": "urn:ietf:rfc:6749"
    }
  ]
}
```

- **Remise par interrogation uniquement** (RFC 8936) : le récepteur demande ; rien ici n'appelle vers l'extérieur.
- Un récepteur s'authentifie avec un jeton d'accès obtenu par l'octroi **client
  credentials**, pour un client `ssf_receiver` doté d'un secret, portée `ssf`.
  Il ne voit que ses propres flux, dix au plus.
- Les événements sont des SET (RFC 8417) signés avec la clé des jetons d'identité, sans `exp` ni
  `sub`. Le sujet est le **compte**, `acct:<username>`, par défaut : un `sub`
  peut être pairwise, un par client. Un récepteur configuré
  `ssf_subject_format = "iss_sub"` reçoit à la place l'émetteur et le `sub` public.
- Un établissement désactivé donne un événement par personne dont le fournisseur garde une trace
  là-bas, et un dont le sujet est le **tenant**, l'entity ID de l'établissement,
  avec ses portées, qui couvre les personnes que le fournisseur a oubliées.
- Les flux et les événements non remis sont conservés dans la base `state` jusqu'à
  leur acquittement ou l'écoulement d'`event_retention`. Un événement qu'un récepteur signale en
  erreur est redistribué, jusqu'à dix fois.

Le bloc SSF est refusé sans bloc `state` :

```
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```
