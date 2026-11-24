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

Retirer un IdP de `saml { idps }` met fin à ce dont il répondait, comme le fait
`DisableIdP` (depuis la v0.23.7) : une nouvelle connexion est refusée, et aussi
chaque autorisation de quelqu'un qui est passé par lui, à la prochaine
utilisation, avec `institution not configured` : un jeton d'actualisation (même
après un redémarrage), un mot de passe d'application, une demande de
certificat SSH. Remettez l'IdP et ils fonctionnent de nouveau ; rien n'a besoin
d'être révoqué.

Avec `reflection = true`, sur un fournisseur de test :

```
$ grpcurl -plaintext -unix $PWD/run/admin.sock bridge.admin.v1.AdminService/Status
{
  "version": "v0.23.4",
  "issuer": "http://127.0.0.1:28473",
  "started": "2026-10-26T11:22:17.441725Z",
  "federation": {
    "metadataUrl": "file:///tmp/authn/fed/metadata.xml",
    "idps": 1,
    "usable": 1,
    "validUntil": "2026-11-02T11:22:16Z",
    "lastRefresh": "2026-10-26T11:22:17.442875Z"
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
    "since": "2026-10-26T11:22:17.952680Z"
  },
  "revoked": {}
}
$ grpcurl -plaintext -unix -d '{"entity_id":"https://idp.univ-example.example/idp/shibboleth","reason":"compromised","until":"2026-11-27T08:00:00Z"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisableIdP
{
  "disabled": {
    "entityId": "https://idp.univ-example.example/idp/shibboleth",
    "reason": "compromised",
    "by": "uid=501",
    "since": "2026-10-26T11:21:27.038956Z",
    "until": "2026-11-27T08:00:00Z"
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
disabled IdP https://idp.univ-example.example/idp/shibboleth by uid=501 until 2026-11-27T08:00:00Z: compromised
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

**Les noms ne replient que les lettres ASCII** (depuis la v0.23.8). La liste des désactivés, les principals de certificat et le subject-id comparent les noms d'utilisateur avec `ASCIILower` de go-authn/oidc : un signe Kelvin (U+212A) n'est donc pas un « k », et `kate` et son orthographe avec un signe Kelvin sont deux personnes, avec deux entrées de désactivation et deux principals de certificat. Désactiver l'une ne désactive pas l'autre.

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

## Avis de retrait d'une clé d'accès {#passkey-removal-notices}

Avec un [bloc `mail`]({{< relref "/authn-bridge/configuration.md#mail" >}}) (depuis la
v0.32.0), un compte local est prévenu, à sa propre adresse, quand le retrait d'une clé
d'accès est demandé ou annulé, pour qu'un voleur qui détient une clé ne puisse pas
annuler en silence le retrait voulu par le propriétaire. Cela ne concerne que les
**comptes locaux**, et l'avis est un message par compte et par `window` (10 minutes par
défaut) : les événements qui arrivent entre-temps sont regroupés en un seul résumé. Ce
que voit un opérateur dépend de l'événement :

- **Une demande de retrait dont l'avis ne peut pas partir reste en attente.** Elle n'est
  pas exécutée à la fin de son délai. Le pont réessaie (5 essais, avec une pause
  croissante), puis journalise `GAVE UP` bien visiblement ; un redémarrage la reprend,
  et l'événement suivant aussi. La clé continue de fonctionner entre-temps, comme
  avant. L'enregistrement porte `notice_pending` jusqu'à la remise d'un avis.
- **Une annulation s'applique même si son message échoue.** L'échec est journalisé
  (`mailing <login> failed`) et affiché sur la page du compte, qui dit que l'avis n'a
  pas pu être envoyé.
- **Un compte sans adresse utilisable** n'est pas bloqué : son retrait se déroule comme
  sans bloc `mail`, le journal dit `<login> has no usable mail address ... nobody is
  told`, et la page du compte le dit.

Sans bloc `mail`, rien ne change.

## Le journal, et les comptes locaux {#journal-and-local-accounts}

Depuis la v0.37.0, chaque connexion réussie laisse une ligne dans le journal,
et aucune ne contient de secret : ni code, ni jeton, ni assertion, ni adresse
mail, ni nom, ni groupe.

```text
login: <username> via <idp entityID> for <client_id> from <address>
login: <login> via <issuer>/local with passkey <8 hex> for <client_id> from <address>
account: <username> confirmed through <idp entityID> from <address>
account: audit: <login> stepup <16 hex> from <address>
token: authorization_code issued to <client_id> for <username>
token: refresh_token issued to <client_id> for <username>
```

Les deux premières sont une connexion au point d'autorisation, par un
établissement et par une clé d'accès locale (`<8 hex>` est l'identifiant de la
clé, tel que l'affiche `local: <login> enrolled a passkey (<8 hex>)`). Les deux
suivantes sont la connexion à la page du compte, par un établissement et par
une clé d'accès. Les deux dernières sont les jetons remis à un client.

Lancez `authn-bridge local-account …` en **root** quand le répertoire des
comptes est `root:authn-bridge` 0750 et le fichier 0640, la disposition
documentée : la commande remplace le fichier par un fichier temporaire voisin,
et sous `authn-bridge` elle échoue avec `open
/etc/authn-bridge-local/.accounts-NNN: permission denied`. Elle conserve le
propriétaire et le mode du fichier. Par SSH, `ssh hôte sudo authn-bridge
local-account … --name "Deux mots"` demande une couche de guillemets de plus
(`--name '"Deux mots"'`), car ssh recolle ses arguments en une seule chaîne que
l'interpréteur distant découpe à nouveau.

## Quels comptes un client accepte {#client-accounts}

Depuis la v0.38.0, un bloc `client` peut n'accepter qu'une sorte de personne :

```hcl
client "forgejo" {
  secret_file   = "/etc/authn-bridge/forgejo.secret"
  redirect_uris = ["https://git.example.org/user/oauth2/bridge/callback"]
  accounts      = ["local"]   # "local", "federated", ou les deux (par défaut)
}
```

`accounts = ["local"]` convient à un service qui veut une clé matérielle : une
personne d'un établissement SAML est refusée. La règle est tenue partout où un
droit est accordé ou utilisé, pas seulement là où la connexion est proposée.
Le point d'autorisation envoie la personne vers l'unique chemin que le client
accepte (`prompt=none` pour un client réservé aux comptes locaux répond
`login_required`) ; l'étape de la fédération, l'étape de la clé d'accès et la fin
de la connexion refusent chacune une connexion de l'autre sorte ; l'échange du
code, un renouvellement et une interrogation d'appareil refusent une personne de
l'autre sorte, si bien qu'un droit obtenu avant l'écriture de la restriction
s'arrête avec elle. La réponse est `access_denied`, à l'URI de redirection du
client pendant une connexion et au point de jeton ensuite. `authn-bridge check`
affiche la restriction sur la ligne du client, `local` exige un bloc `local`, et
`bridge_logins_total{result="wrong_account_kind"}` compte les refus. Le journal
dit pourquoi :

```text
login: <username> via <idp entityID> refused for <client_id>: this client takes local accounts only
token: account kind not accepted by this client: <why> (<username> via <idp> for <client_id>)
```

Limite connue : les points de certificats (SSH, X.509, Kerberos, WireGuard) ne
sont liés à aucun client ; `accounts` ne s'y applique donc pas.

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
bridge_build_info{version="v0.23.4",goversion="go1.27.3",revision="6e0156cb516ace9091d4070c425258febc48f6ee"} 1
bridge_start_time_seconds 1793013737
bridge_ready 1
bridge_metadata_valid_until_timestamp_seconds 1793618536
bridge_metadata_idps 1
bridge_metadata_last_refresh_timestamp_seconds 1793013737
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
