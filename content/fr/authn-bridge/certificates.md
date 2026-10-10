---
title: "Certificats"
linkTitle: "Certificats"
weight: 50
description: "Les certificats SSH d'utilisateur que signe authn-bridge, leur profil EuroHPC Federation Platform, et les certificats clients X.509 qu'il émet pour NFS sur TLS."
tags: [authn-bridge, ssh, x509, eurohpc]
---

Une personne qui s'est connectée peut faire certifier une clé publique SSH, ou faire émettre un certificat
client X.509, pour quelques heures. Un serveur qui fait confiance à l'AC (autorité de certification) du fournisseur
la laisse entrer sans fichier de comptes à modifier sur place. Chaque certificat est **enregistré dans
`certificates_file` avant d'être remis** : un certificat qui ne peut pas être enregistré n'est
pas émis, puisqu'il ne pourrait jamais être révoqué, et les certificats révoqués sont publiés dans
la [KRL et la CRL]({{< relref "/authn-bridge/revocation.md" >}}).

## Certificats SSH {#ssh-certificates}

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

ssh_ca {
  key_file = "/var/lib/authn-bridge/ssh-ca"   # authn-bridge keygen --ssh-ca; Ed25519
  validity = "12h"                            # the default; a week at most
}

client "sftp" {
  device           = true
  ssh_certificates = true
}
```

`authn-bridge ssh-cert --issuer https://login.example.org --client sftp` se
connecte avec un code, envoie `~/.ssh/id_ed25519.pub` (ou `--key`) à
`/ssh/certificate` avec un jeton de la portée `ssh`, et écrit
`<key>-cert.pub` à côté, là où `ssh` et `sftp` le trouvent.

La clé de l'AC doit être Ed25519 : une clé d'AC RSA signe en SHA-1 sauf indication
contraire, ce qu'OpenSSH refuse par défaut depuis la 8.8.

**Ce que dit le certificat.**

- **Exactement un principal**, le `preferred_username` de la personne, sauf si le
  profil du client indique une autre revendication. Un certificat sans principal est valide
  pour *n'importe quel* utilisateur (PROTOCOL.certkeys), aussi une personne sans nom d'utilisateur n'en reçoit-elle aucun. Un
  nom contenant une virgule, une espace, un guillemet, une barre oblique inverse ou un caractère de contrôle est
  refusé (`403`) : `sshd` lit `principals="a,b"` et les entrées de `AuthorizedPrincipalsFile`
  comme des listes, si bien qu'un tel nom en fait deux.
- **Key ID** `<principal> sub=<sub> jti=<token id>` : ce que journalise `sshd`.
- **Aucune extension `permit-*`** par défaut. SFTP n'en a besoin d'aucune, et un certificat
  qui n'autorise ni pty, ni redirection, ni fichier rc donne accès aux fichiers et à
  rien d'autre.
- **Les groupes de la personne** dans l'extension `groups@go-authn.org`, un par ligne,
  quand le jeton porte des groupes. OpenSSH l'ignore ; elle est signée, aussi un serveur
  qui autorise par groupe peut-il s'y fier.
- **Valide** depuis cinq minutes avant l'émission (pour les horloges en désaccord) jusqu'à `validity`
  à partir de maintenant, ou jusqu'à la fin de la session de l'IdP si elle arrive plus tôt.
- **La clé** doit être Ed25519, ECDSA P-256/384/521, une clé de sécurité (`sk-`), ou
  RSA d'au moins 2048 bits. Un certificat est refusé en guise de clé.

## Le profil de l'AC SSH EuroHPC {#the-eurohpc-ssh-ca-profile}

L'AC SSH de l'EuroHPC Federation Platform (GÉANT / MyAccessID) émet des certificats Ed25519
valides une heure, avec un principal qui désigne la personne dans toute
la fédération, et les hôtes auxquels ils sont destinés dans l'extension
`ssh-domain-grant@core.aai.geant.org` de GÉANT. Un client peut faire émettre ses
certificats sous cette forme. Chaque clé est propre au client et facultative ; un
client qui n'en définit aucune reçoit le certificat ci-dessus.

```hcl
client "efp" {
  device              = true
  ssh_certificates    = true
  ssh_principal_claim = "voperson_id"               # the default is preferred_username
  ssh_validity        = "1h"                        # never longer than ssh_ca's, nor the IdP's session
  ssh_extensions      = ["permit-pty"]              # none by default
  ssh_domain_grants   = ["login.hpc.example.org"]   # the hosting entity's hosts
  # ssh_source_address = ["192.0.2.0/24"]           # the source-address critical option
}
```

| clé | |
|---|---|
| `ssh_principal_claim` | `preferred_username`, `sub`, `voperson_id` ou `eduperson_principal_name`. Les deux derniers sont communiqués par la portée `eduperson`, que le jeton doit détenir (`authn-bridge ssh-cert --scope eduperson`) ; sinon, ou quand l'IdP n'a communiqué aucun attribut de ce genre, la réponse est un `403` qui dit lequel |
| `ssh_extensions` | parmi `permit-pty`, `permit-user-rc`, `permit-port-forwarding`, `permit-agent-forwarding`, `permit-X11-forwarding` |
| `ssh_source_address` | adresses ou préfixes CIDR, écrits sous forme canonique dans `source-address` |
| `ssh_validity` | plus courte que la `validity` de `ssh_ca`, pour ce client |
| `ssh_domain_grants` | motifs de domaine, vérifiés par le `ValidatePattern` de [go-authn/sshcert]({{< relref "/sshcert/_index.md" >}}) et encodés par son `EncodeDomainGrant` |

### Ce que le profil refuse {#what-the-profile-refuses}

Chaque refus au démarrage, d'après `authn-bridge check` :

```
authn-bridge: client "efp": ssh_validity = 24h0m0s: longer than the ssh_ca validity, 12h0m0s
authn-bridge: client "efp": ssh_extensions: "no-touch-required" is not one of permit-X11-forwarding, permit-agent-forwarding, permit-port-forwarding, permit-pty, permit-user-rc
authn-bridge: client "src": ssh_source_address: "192.0.2.1/24" has bits set under its mask: 192.0.2.0/24?
authn-bridge: client "x": ssh_principal_claim, ssh_extensions, ssh_source_address, ssh_validity and ssh_domain_grants shape SSH certificates: they need ssh_certificates = true
```

`no-touch-required` n'est pas proposé : il lève le test de présence de l'utilisateur sur la
clé de sécurité **propre** à la personne, et ce n'est pas au fournisseur d'y renoncer pour
toutes les personnes d'un client.

Une délégation de domaine est tenue à la syntaxe de la spécification, puis à la
politique propre de ce fournisseur : en minuscules, au moins deux labels, et un joker seulement sous un
domaine enregistrable. Ce qui reste fixe à droite du dernier joker ne doit pas
être un suffixe public (la Public Suffix List) : `*.ac.uk` accorderait l'accès à tous
les établissements en dessous.

```
authn-bridge: client "efp": ssh_domain_grants: "*.ac.uk": a wildcard over the public suffix "ac.uk" grants every domain under it
authn-bridge: client "efp": ssh_domain_grants: "Login.hpc.example.org": written in lower case, as hosting entities' domains are compared
authn-bridge: client "efp": ssh_domain_grants: "login.hpc.*": sshcert: invalid domain pattern: pattern "login.hpc.*" has a wildcard in its rightmost label
```

### Lui faire confiance depuis un site {#trusting-it-from-a-site}

`GET /ssh/config` publie la clé de l'AC sous la forme dans laquelle EFP publie la sienne, si bien qu'un
site suit les instructions de confiance d'EFP avec l'URL de ce fournisseur :

```
$ curl -s http://127.0.0.1:28473/ssh/config
{"PublicKey":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHFRUBlwxcGmmqW2lBI9bJyN4LL0/4U0NZwOOwBFPWw9"}
```

```sh
curl -s https://login.example.org/ssh/config | jq -r '.PublicKey' > /etc/ssh/bridge-ssh-ca.pub
echo "TrustedUserCAKeys /etc/ssh/bridge-ssh-ca.pub" >> /etc/ssh/sshd_config
```

sshd ignore la délégation de domaine. Le site filtre selon elle avec un
`AuthorizedPrincipalsCommand` : [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}),
qui refuse un certificat dont la délégation ne nomme pas l'hôte, et un certificat sans
aucune délégation. L'AC n'est pas dans le document de découverte OpenID : aucune métadonnée
OpenID Connect ne nomme une AC SSH.

Ce qui reste différent de l'AC propre d'EFP : le principal est le `subject-id`
que l'établissement de la personne a communiqué, et non un identifiant MyAccessID ; l'extension
des groupes est présente quand le jeton porte des groupes ; et **il y a une KRL**,
`GET /ssh/krl`, qui liste les certificats des personnes désactivées ici.

## Certificats clients X.509, pour NFS sur TLS {#x509-client-certificates-for-nfs-over-tls}

NFS sur TLS (RFC 9289) peut désigner le client par son certificat.

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

x509_ca {
  key_file  = "/var/lib/authn-bridge/nfs-ca/ca.key"   # authn-bridge keygen --x509-ca /var/lib/authn-bridge/nfs-ca
  cert_file = "/var/lib/authn-bridge/nfs-ca/ca.crt"   # what go-fileshare trusts
  validity  = "12h"                                   # the default; a week at most
}

client "nfs" {
  device            = true
  x509_certificates = true
}
```

`authn-bridge nfs-cert --issuer ... --client nfs` crée une clé P-256 sur la
machine de la personne, envoie une demande de certificat à `/x509/cert` avec un jeton de
la portée `nfs`, et écrit le certificat et la clé. La clé de l'AC doit être
P-256, et son certificat celui d'une AC qui signe des certificats et des CRL.

**Ce que dit le certificat.** Le sujet et les extensions de la demande sont
ignorés : ce qui est certifié, c'est la personne du jeton, pas ce qu'elle a demandé.

- La personne, `user@domain`, comme **un seul** `otherName` subjectAltName
  `1.3.6.1.4.1.2238.1.1.1` contenant une UTF8String, là où le
  `rpc.tlsservd -u` de FreeBSD le lit. Un nom d'utilisateur sans `@`, ou de moins de trois octets, est
  refusé.
- Chaque groupe comme un nom URI à côté :
  `tag:go-authn.github.io,2026:group:<the group, percent-encoded>`.
- Le CN est le nom d'utilisateur ; au-delà de 64 caractères, le sujet est vide et le
  subjectAltName critique (RFC 5280).
- Authentification client uniquement, et un point de distribution de CRL :
  `<issuer>/x509/crl`.
- Valide depuis cinq minutes avant l'émission jusqu'à `validity`, la session de l'IdP ou le
  certificat propre de l'AC, selon ce qui se termine en premier.
- Une clé P-256 ou RSA (2048 bits et plus), et une demande signée par elle.

{{< callout type="warning" >}}
**Un certificat désigne la machine, pas la personne qui l'utilise**

RFC 9289 : le serveur « cannot utilize the remote TLS peer identity to
authenticate RPC users ». Linux définit le certificat client par montage, si bien que
toute personne utilisant ce montage est la personne qu'il désigne. C'est fait pour une machine
qu'une seule personne utilise, et `authn-bridge nfs-cert` le dit.
{{< /callout >}}

## Une demande de certificat maintenue ouverte pendant une désactivation {#a-certificate-request-held-open-across-a-disabling}

Le jeton est vérifié au début de la demande et le corps lu ensuite, au
rythme auquel le client l'envoie. Aussi un certificat est-il d'abord enregistré, puis
le jeton et la personne sont vérifiés de nouveau : si la personne a été désactivée, ou le
jeton révoqué, entre-temps, le certificat qui vient d'être enregistré est révoqué et la
réponse est `401`. Soit la révocation a vu le certificat, soit le certificat
voit la révocation.
