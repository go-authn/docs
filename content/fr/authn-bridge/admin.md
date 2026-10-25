---
title: "L'API d'administration, la santé et les métriques"
linkTitle: "API d'administration"
weight: 70
description: "Désactiver une personne ou un établissement par l'API d'administration gRPC d'authn-bridge, et les points d'accès de santé et de métriques à côté."
tags: [authn-bridge, administration, grpc, métriques]
---

Les deux sont désactivées sauf si la configuration les demande, et aucune n'est jamais sur
l'écouteur public.

```hcl
admin {
  listen = "unix:///run/authn-bridge/admin.sock"   # mode 0600
  # or over the network, mutual TLS and nothing less (loopback included):
  # listen         = "10.0.0.5:9443"
  # tls_cert_file  = "/etc/authn-bridge/admin.crt"
  # tls_key_file   = "/etc/authn-bridge/admin.key"
  # client_ca_file = "/etc/authn-bridge/operators-ca.crt"
  # reflection     = true                          # for grpcurl; off by default
}

metrics { listen = "127.0.0.1:9101" }              # /healthz /readyz /metrics

disabled_file = "/var/lib/authn-bridge/disabled.json"
```

L'écouteur est celui de grpc-transports/control, partagé avec go-fileshare. Le socket
n'est jamais accessible à un autre utilisateur, pas même entre bind et chmod, et n'est
jamais pris à une instance encore en cours d'exécution. TCP sans les trois fichiers TLS est
refusé, interface de bouclage comprise, puisque tout utilisateur local peut atteindre `127.0.0.1` :

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
```

Un binaire compilé avec `-tags nogrpc` n'a pas d'API d'administration, et refuse une configuration
comportant un bloc `admin` plutôt que de démarrer sans elle.

## Le service {#the-service}

`bridge.admin.v1.AdminService` (`proto/bridge/admin/v1/admin.proto`), avec
`grpc.health.v1` à côté, qui répond `SERVING` tant que le fournisseur est prêt.

| | |
|---|---|
| `Status` | version, émetteur, heure de démarrage ; les métadonnées de la fédération (IdP, utilisables, valides jusqu'à, dernier rafraîchissement, dernière erreur) ; ce qui est gardé en mémoire |
| `RefreshMetadata` | récupérer les métadonnées de la fédération maintenant, et dire comment cela s'est passé |
| `ListIdPs` | les IdP de la fédération, tels que la liste des établissements les montre (`query`, `limit`, 100 par défaut) |
| `ListClients` | les parties utilisatrices (relying parties) configurées |
| `RevokePerson` | mettre fin à ses familles de jetons de rafraîchissement, aux jetons d'accès qu'elles ont obtenus, à ses connexions et autorisations d'appareil en cours et à son mot de passe d'application, et révoquer tout ce que le magasin de certificats détient pour cette personne : certificats SSH et X.509 (dans la prochaine KRL et la prochaine CRL) et clés WireGuard |
| `DisablePerson`, `EnablePerson` | refuser quelqu'un ici, à la connexion et à chaque jeton, quoi qu'en dise son établissement, et révoquer ce que la personne détient ; éventuellement jusqu'à une heure donnée (`until`) |
| `DisableIdP`, `EnableIdP` | la même chose pour toutes les personnes dont un établissement se porte garant ; un rafraîchissement des métadonnées ne le lève pas |
| `ListDisabled` | qui est désactivé, pourquoi, par qui, depuis quand et jusqu'à quand |

Avec `reflection = true`, sur un fournisseur de test :

```
$ grpcurl -plaintext -unix $PWD/run/admin.sock bridge.admin.v1.AdminService/Status
{
  "version": "v0.23.3",
  "issuer": "http://127.0.0.1:28473",
  "started": "2026-10-25T18:44:30.210885Z",
  "federation": {
    "metadataUrl": "file:///tmp/authn/fed/metadata.xml",
    "idps": 1,
    "usable": 1,
    "validUntil": "2026-11-01T18:43:40Z",
    "lastRefresh": "2026-10-25T18:44:30.211975Z"
  },
  "counts": {}
}
```

## Désactiver {#disabling}

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example","reason":"left the lab"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
{
  "disabled": {
    "username": "alice@univ-example.example",
    "reason": "left the lab",
    "by": "uid=501",
    "since": "2026-10-11T09:48:39.136975Z"
  },
  "revoked": {}
}
$ grpcurl -plaintext -unix -d '{"entity_id":"https://idp.univ-example.example/idp/shibboleth","reason":"compromised","until":"2026-10-12T08:00:00Z"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisableIdP
{
  "disabled": {
    "entityId": "https://idp.univ-example.example/idp/shibboleth",
    "reason": "compromised",
    "by": "uid=501",
    "since": "2026-10-11T09:48:39.192047Z",
    "until": "2026-10-12T08:00:00Z"
  },
  "revoked": {}
}
```

`revoked` compte ce à quoi chaque appel a mis fin (familles de rafraîchissement, jetons d'accès, connexions,
mots de passe d'application, certificats) ; rien n'était actif ici. Chaque appel qui
modifie quelque chose est journalisé avec son auteur, le `uid=` du pair sur le socket
ou le `cn=` du certificat client sur TLS :

```
disabled alice@univ-example.example (0 known identities) by uid=501 until enabled again: left the lab
revoked alice@univ-example.example: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
disabled IdP https://idp.univ-example.example/idp/shibboleth by uid=501 until 2026-10-12T08:00:00Z: compromised
revoked IdP https://idp.univ-example.example/idp/shibboleth: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
enabled alice@univ-example.example by uid=501
```

**Une personne est désactivée en tant que qui elle est.** Les noms d'utilisateur se comparent sans tenir compte de la casse,
comme eppn, uid, mail et subject-id, si bien que le même appel avec
`"Alice@Univ-Example.example"` lève ce qui a été posé pour `alice@univ-example.example`
(`{"wasDisabled": true}`). L'entrée enregistre aussi l'identité stable de
toutes les personnes connues sous ce nom, si bien qu'une autre graphie venant de leur IdP ne les laisse pas
revenir. Un nom sans `@` est aussi comparé comme un `sub`, pour une personne dont
l'IdP ne communique aucun nom d'utilisateur.

L'entrée est enregistrée **avant** que quoi que ce soit ne soit révoqué, si bien qu'une autorisation en concurrence avec
la révocation rencontre l'entrée.

**La désactivation est conservée dans `disabled_file`, et refusée sans lui.** Quelqu'un
désactivé jusqu'au prochain redémarrage serait réadmis par le prochain déploiement :

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
ERROR:
  Code: FailedPrecondition
  Message: disabling needs disabled_file in the configuration: without it, a restart would forget who is disabled
```

Un fichier illisible empêche le fournisseur de démarrer, pour la même
raison. Un établissement désactivé compte comme non utilisable dans `Status`, `ListIdPs` et
[`check`]({{< relref "/authn-bridge/configuration.md#check-before-a-restart" >}}).

Ce que la désactivation atteint au-delà du fournisseur est décrit sur
[révocation]({{< relref "/authn-bridge/revocation.md" >}}) : la KRL et la
CRL pour les certificats, les signaux partagés (Shared Signals) pour les jetons. Un mot de passe d'application
supprimé ici cesse de fonctionner dans go-fileshare quand il relit son annuaire ;
appelez son `ReloadDirectory` après `DisablePerson` pour que l'effet soit immédiat.

{{< callout type="warning" >}}
**Ce à quoi `RevokePerson` ne peut pas mettre fin**

Un jeton d'accès déjà remis est une déclaration signée qu'un serveur de ressources
vérifie de lui-même, valide là-bas jusqu'à son expiration (une heure par défaut). Un
certificat SSH déjà émis dure toute sa validité sauf si le serveur lit
la KRL, ce qui explique que les deux soient courts.
{{< /callout >}}

## Santé et métriques {#health-and-metrics}

Ceux de go-net-health/endpoint, comme dans go-fileshare, sur l'écouteur `metrics`, qui
ne doit pas être l'écouteur public (une configuration qui le fait est refusée) :

| | |
|---|---|
| `/healthz` | actif tant que le processus répond |
| `/readyz` | prêt tant que les métadonnées de la fédération sont chargées et dans leur `validUntil`, et qu'aucune révocation n'attend d'atteindre la base de données d'état |
| `/metrics` | texte Prometheus, familles `bridge_*` |

```
$ curl -s http://127.0.0.1:28475/metrics | grep "^bridge_"
bridge_build_info{version="v0.23.3",goversion="go1.27.3",revision="b04769c43c24f684df9e0b5a0d1cb6997ee90d95"} 1
bridge_start_time_seconds 1792953870
bridge_ready 1
bridge_metadata_valid_until_timestamp_seconds 1793558620
bridge_metadata_idps 1
bridge_metadata_last_refresh_timestamp_seconds 1792953870
bridge_metadata_refreshes_total{result="failed"} 0
bridge_metadata_refreshes_total{result="ok"} 1
bridge_logins_in_progress 0
bridge_devices_waiting 0
bridge_refresh_families 0
bridge_access_tokens 0
bridge_disabled{kind="idp"} 0
bridge_disabled{kind="person"} 0
bridge_ssh_certificates_total 0
bridge_x509_certificates_total 0
```

Les compteurs des connexions par issue (`bridge_logins_total`), des jetons par type d'autorisation
(`bridge_tokens_issued_total`) et des mots de passe d'application (`bridge_app_passwords_total`)
n'apparaissent qu'une fois qu'ils ont compté quelque chose. **Aucune étiquette ne nomme une personne ou un établissement** : quelles
universités ont des personnes qui utilisent le service, et quand, ce n'est pas au fournisseur de le
publier. Alertez sur `bridge_metadata_valid_until_timestamp_seconds` avant que l'instant
qu'elle donne soit atteint : au-delà, personne ne peut se connecter.
