---
title: "La configuration"
linkTitle: "Configuration"
weight: 20
description: "Comment s'organise la configuration HCL d'authn-bridge, ce qu'affiche check, et ce qui est refusé avant que quiconque puisse se connecter."
tags: [authn-bridge, configuration]
---

Un fichier HCL, ou un répertoire de fichiers HCL : `--config /etc/authn-bridge` lit chaque
`*.hcl` qui s'y trouve dans l'ordre des noms et les fusionne, et `--config` peut être donné plus
d'une fois. La configuration est lue au démarrage et plus jamais ensuite.

```hcl
issuer            = "https://login.example.org"       # https; compared whole by every relying party
listen            = "127.0.0.1:8080"                  # the default: plain HTTP behind a TLS proxy
signing_key_file  = "/var/lib/authn-bridge/oidc.key"  # authn-bridge keygen --key
subject_salt_file = "/var/lib/authn-bridge/salt"      # authn-bridge keygen --salt; never change it
disabled_file     = "/var/lib/authn-bridge/disabled.json"
certificates_file = "/var/lib/authn-bridge/certificates.json"

saml {
  key_file             = "/var/lib/authn-bridge/saml.key"
  cert_file            = "/var/lib/authn-bridge/saml.crt"
  metadata_url         = "https://pub.federation.renater.fr/metadata/fer/idps.xml"
  metadata_cert_file   = "/etc/authn-bridge/metadata-signature-2026.pem"
  metadata_fingerprint = "68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0"
}

state {
  driver   = "sqlite"                                 # or postgres, mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}

client "my-app" {
  secret_file   = "/etc/authn-bridge/my-app.secret"   # absent: a public client
  redirect_uris = ["https://app.example.org/callback"]
}
```

Sont requis `issuer`, `signing_key_file`, `subject_salt_file`, un bloc `saml`
avec les cinq clés ci-dessus, et au moins un `client`. Tout le reste a une
valeur par défaut ou est désactivé.

## `check`, avant un redémarrage {#check-before-a-restart}

`check` lit la configuration comme le fait le serveur, charge chaque clé qu'elle
nomme, **récupère les métadonnées de la fédération**, et dit ce qui serait servi :

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-10-17T19:16:33Z
client        sftp (public, public subject, audience [sftp])
client        efp (public, public subject, audience [efp])
client        nfs (public, public subject, audience [nfs])
```

*Usable here* exclut un IdP que `saml { idps }` ne liste pas, et un IdP que
l'[API d'administration]({{< relref "/authn-bridge/admin.md" >}}) a désactivé : avec
l'établissement ci-dessus désactivé, la même commande affiche
`federation    1 IdPs, 0 usable here`. Une entrée `idps` que la fédération ne
liste pas est refusée ici, alors que le serveur démarrerait avec elle :

```
federation    1 IdPs, 0 usable here, valid until 2026-10-17T19:16:33Z
authn-bridge: idps names "https://idp.nowhere.example/idp", which the federation does not list
```

`authn-bridge metadata` affiche les métadonnées SAML à enregistrer auprès de la
fédération. Voir [le côté fédération]({{< relref "/authn-bridge/federation.md" >}}).

## Le niveau supérieur {#the-top-level}

| clé | défaut | |
|---|---|---|
| `issuer` | | le nom du fournisseur et la base de chaque URL. `https`, ou `http` sur un hôte de bouclage pour les tests ; pas de requête, pas de fragment ; un `/` final est supprimé |
| `listen` | `127.0.0.1:8080` | l'écouteur public |
| `cert_file`, `key_file` | | servir TLS à partir de ces fichiers, relus quand ils changent ; ensemble ou pas du tout |
| `acme` | | servir TLS plutôt avec un certificat d'une AC ACME (ci-dessous) ; pas avec `cert_file` |
| `signing_key_file` | | RSA, signe les jetons d'identité (RS256) ; une clé P-256 ici est refusée |
| `access_token_key_file` | la clé de signature | une clé P-256 qui signe les jetons d'accès en ES256 ; refusée si c'est la clé de signature |
| `retired_signing_key_files` | | des clés qui ont signé auparavant : toujours publiées à `/jwks`, jamais utilisées pour signer |
| `subject_salt_file` | | au moins 32 octets |
| `code_lifetime` | `1m` | dix minutes au plus (RFC 6749 4.1.2) |
| `token_lifetime` | `1h` | jetons d'accès |
| `id_token_lifetime` | `5m` | jetons d'identité |
| `trusted_proxies` | | adresses ou préfixes dont on croit le `X-Forwarded-For` |
| `requests_per_minute` | `120` | connexions, autorisations d'appareil et envois à l'ACS qu'une adresse peut lancer par minute ; `0` désactive la limite |
| `disabled_file` | | où sont conservés les personnes et établissements désactivés ; sans lui, la désactivation est refusée |
| `certificates_file` | | chaque certificat et chaque clé WireGuard émis ; requis avec `ssh_ca`, `x509_ca` ou `wireguard` |

Les blocs :

| bloc | page |
|---|---|
| `saml`, `claims` | [le côté fédération]({{< relref "/authn-bridge/federation.md" >}}) |
| `client` | ci-dessous, et [jetons]({{< relref "/authn-bridge/tokens.md" >}}) |
| `state` | ci-dessous |
| `ssh_ca`, `x509_ca` | [certificats]({{< relref "/authn-bridge/certificates.md" >}}) |
| `app_passwords`, `wireguard` | [jetons]({{< relref "/authn-bridge/tokens.md" >}}) |
| `ssf` | [révocation]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |
| `admin`, `metrics` | [l'API d'administration]({{< relref "/authn-bridge/admin.md" >}}) |
| `acme` | ci-dessous |

## Un client {#a-client}

| clé | défaut | |
|---|---|---|
| `secret_file` | | le secret du client, au moins 16 caractères ; absent, un client **public** |
| `redirect_uris` | | comparées exactement, sauf qu'une URI de bouclage peut changer de port (RFC 8252) ; `http` seulement sur l'interface de bouclage |
| `audience` | l'ID du client | à qui ses jetons d'accès sont adressés |
| `subject` | `public` | ou `pairwise` : un `sub` différent pour ce client (OIDC Core 8.1) |
| `name` | l'ID du client | affiché sur la page de confirmation d'appareil |
| `device` | `false` | l'autorisation d'appareil (RFC 8628) ; un tel client n'a besoin d'aucune URI de redirection |
| `refresh_lifetime` | désactivé | jetons de rafraîchissement, et combien de temps après la **connexion** ils prennent fin |
| `pkce` | `required` | ou `or_nonce`, pour un client confidentiel seulement : un `nonce` au lieu de PKCE |
| `id_token_claims` | `false` | copier aussi les revendications communiquées dans le jeton d'identité (opkssh en a besoin) |
| `ssh_certificates`, `ssh_*` | | [certificats SSH]({{< relref "/authn-bridge/certificates.md#ssh-certificates" >}}) |
| `x509_certificates` | | [certificats clients NFS]({{< relref "/authn-bridge/certificates.md#x509-client-certificates-for-nfs-over-tls" >}}) |
| `app_passwords` | | peut définir le [mot de passe d'application]({{< relref "/authn-bridge/tokens.md#application-passwords" >}}) de la personne |
| `wireguard_keys`, `wireguard_peers` | | [WireGuard]({{< relref "/authn-bridge/tokens.md#wireguard-keys" >}}) |
| `ssf_receiver`, `ssf_subject_format` | | un [récepteur de signaux partagés (Shared Signals)]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |

Un client sans URI de redirection doit être un client d'appareil, un récepteur SSF ou une
passerelle WireGuard, sinon il n'y aurait rien qu'il puisse faire.

## `state` : ce qu'un redémarrage ne doit pas oublier {#state-what-a-restart-must-not-forget}

```hcl
state {
  driver   = "postgres"                  # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}
```

Les familles de jetons de rafraîchissement, les jetons de rafraîchissement et ceux retirés, les jetons
d'accès honorés à `/userinfo` et pour les certificats, les assertions SAML déjà
acceptées et les connexions auxquelles il a déjà été répondu, les flux SSF et leurs événements non
livrés : écrits au fil de l'eau dans une seule table, `bridge_state` (créée si elle manque), et
lus au démarrage. Un jeton de rafraîchissement est conservé sous forme de son SHA-256, jamais tel quel.
Sans ce bloc, ils vivent en mémoire, et un redémarrage déconnecte tout le monde.

Une connexion en cours n'y figure pas. Elle voyage dans son propre cookie, scellé avec
AES-256-GCM sous une clé dérivée du sel des sujets, si bien que le navigateur ne peut
ni le lire ni le modifier.

## `acme` {#acme}

```hcl
acme {
  accept_terms_of_service = true                     # the operator's agreement; no default
  cache_dir               = "/var/lib/authn-bridge/acme"
  email                   = "noc@example.org"
  # directory_url         = "..."                    # Let's Encrypt by default
  # eab_key_id            = "..."                    # External Account Binding (GÉANT TCS / HARICA)
  # eab_hmac_key_file     = "/etc/authn-bridge/harica-eab.key"
  # http_listen           = ":80"                    # http-01, and a redirect to https
  # directory_ca_file     = "..."                    # a private ACME CA's own TLS
}
```

Le certificat est pour l'hôte de l'émetteur. `cache_dir` contient des clés privées, et
le fournisseur refuse de démarrer sur un répertoire qu'un autre utilisateur pourrait atteindre ou faire pointer ailleurs.

## Ce qui est refusé au démarrage {#what-is-refused-at-startup}

Chacun de ces messages est la sortie de `authn-bridge check` sur une configuration qui
l'a provoqué. Le serveur refuse les mêmes configurations.

**Un émetteur, une redirection, un secret qui fuient :**

```
authn-bridge: issuer "http://login.example.org": an issuer is https (http only on loopback, for testing)
authn-bridge: client "web": redirect URI "http://app.example.org/callback": a code sent over cleartext http is a code anybody on the path has
authn-bridge: client "web": a secret of 5 characters is a password somebody can guess
authn-bridge: code_lifetime = 15m0s: an authorization code lives ten minutes at most
```

**Un nom que n'importe quel établissement pourrait revendiquer :**

```
authn-bridge: claims: username = "uid" is not held to an IdP's scopes, so any IdP of the federation could name anybody: it needs saml { idps } to list exactly one IdP; with more, use eppn or subject_id
authn-bridge: claims: groups = "affiliation" carries no institution, so any IdP of the federation could grant any of its values: it needs saml { idps } to list exactly one IdP; with more, use scoped_affiliation
```

**Quelque chose d'émis qui ne pourrait jamais être repris :**

```
authn-bridge: ssh_ca: certificates_file is required with ssh_ca or x509_ca: a certificate that is not recorded can never be revoked
authn-bridge: ssh_ca: validity = 200h0m0s: more than a week, and a certificate lives that long on every server its revocation has not reached
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```

**Un écouteur qui ne devrait pas être accessible :**

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
authn-bridge: metrics: listen is the public listener; metrics have one of their own
```

**Une configuration qui dit deux fois la même chose :**

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
authn-bridge: client "sftp" is declared twice
```

Les refus propres au profil SSH sont sur [certificats]({{< relref "/authn-bridge/certificates.md#what-the-profile-refuses" >}}),
et ceux de la fédération sur [le côté fédération]({{< relref "/authn-bridge/federation.md#what-is-refused" >}}).
