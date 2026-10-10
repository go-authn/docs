---
title: "Le côté fédération"
linkTitle: "Le côté fédération"
weight: 30
description: "Comment authn-bridge lit les métadonnées d'une fédération SAML, épingle leur signataire, tient chaque IdP à ses propres portées, et transforme une assertion en revendications."
tags: [authn-bridge, saml, renater, edugain]
---

De ce côté, authn-bridge est un fournisseur de service SAML. Il est enregistré une fois
auprès de la fédération (la Fédération Éducation-Recherche de RENATER, ou eduGAIN), et il
fait confiance aux **métadonnées** de la fédération : un document signé qui liste chaque
IdP membre, ses clés de signature, et les domaines dont chacun peut se porter garant. Le code
SAML est [go-authn/saml]({{< relref "/libraries/_index.md" >}}).

```hcl
saml {
  key_file  = "/var/lib/authn-bridge/saml.key"   # RSA: IdPs encrypt assertions to it
  cert_file = "/var/lib/authn-bridge/saml.crt"

  metadata_url         = "https://pub.federation.renater.fr/metadata/fer/idps.xml"
  metadata_cert_file   = "/etc/authn-bridge/metadata-signature-2026.pem"
  metadata_fingerprint = "68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0"

  discovery = "https://discovery.renater.fr/renater"   # or leave it out for this provider's own list
  # idps    = ["https://idp.univ-example.fr/idp/shibboleth"]   # restrict; one entry skips the choice

  names             = { fr = "Passerelle OIDC", en = "OIDC gateway" }
  technical_contact = "admin@example.org"
}
```

| clé | par défaut | |
|---|---|---|
| `entity_id` | l'émetteur + `/saml` | le nom de ce fournisseur de service dans la fédération |
| `key_file`, `cert_file` | | la clé RSA et le certificat du fournisseur de service |
| `metadata_url` | | `https://`, `file://` pour une copie que quelque chose d'autre tient à jour, ou `http://` sur la boucle locale uniquement |
| `metadata_cert_file`, `metadata_fingerprint` | | le certificat de signature de la fédération et son empreinte SHA-256, tous deux obligatoires |
| `discovery` | la liste propre à ce fournisseur | un service de découverte externe vers lequel envoyer les personnes |
| `idps` | tous les IdP de la fédération | restreindre la connexion à ces entity IDs |
| `names`, `descriptions`, `information_url`, `privacy_statement_url`, `technical_contact` | l'hôte de l'émetteur comme nom | ce qui figure dans les métadonnées du fournisseur de service |

## Le signataire des métadonnées est épinglé {#the-metadatas-signer-is-pinned}

Le certificat qui signe les métadonnées est un fichier sur cet hôte, et son empreinte
SHA-256 est écrite dans la configuration. Le certificat est vérifié
par rapport à l'empreinte **à chaque démarrage**, si bien qu'un fichier remplacé sur le disque est remarqué
plutôt que cru :

```
authn-bridge: saml: fed/fed.crt is not the certificate with fingerprint 68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0
```

Une clé qui arrive par le même canal que le document dont elle se porte garante ne garantit
rien. L'empreinte vient donc de la page web de la fédération, jamais du
téléchargement qui a apporté le certificat :

```sh
openssl x509 -in /etc/authn-bridge/metadata-signature-2026.pem -noout -fingerprint -sha256
```

## Un document est refusé {#a-document-is-refused}

- quand il n'est pas signé par ce certificat, ou est signé en SHA-1, ou que sa
  signature couvre un autre élément que la racine ;
- **quand il n'a pas de `validUntil`, ou l'a dépassé.** Voici les propres
  métadonnées de RENATER telles que publiées le 29 septembre 2026, lues le 10 octobre :

  ```
  $ authn-bridge check --config v/renater-expired.hcl
  authn-bridge: the federation's metadata: metadata expired at 2026-10-08T07:30:02Z
  ```

- quand son `validUntil` est à plus de 28 jours : un document valide des années
  est un document qu'un rejeu maintient en vie des années ;
- **quand il est plus ancien que celui en usage** (un `validUntil` antérieur). Il est
  validement signé et pas encore expiré, donc rien d'autre ne le refuserait, et il
  peut être celui qui porte une clé révoquée depuis, servi par quiconque se trouve sur le chemin ;
- en `http` simple vers autre chose que la boucle locale. La signature détecterait une
  modification, mais pas un proxy qui retient le nouveau document et continue de servir
  l'ancien.

## Le rafraîchir {#refreshing-it}

Les métadonnées sont récupérées avant que le fournisseur n'écoute, puis de nouveau aux trois
quarts de la `cacheDuration` du document, jamais avant cinq minutes ni
après douze heures, et chaque fois que le `RefreshMetadata` de l'API d'administration le demande.
Un rafraîchissement qui échoue garde la dernière copie valide, **mais seulement jusqu'à son propre
`validUntil`**. Passé ce délai, plus rien n'est garanti, tous les IdP disparaissent, et
`/readyz` dit que le fournisseur n'est pas prêt. Un serveur de fédération brièvement
injoignable ne déconnecte personne ; un serveur injoignable pendant des jours ne laisse pas le
fournisseur se fier à des clés périmées.

Au sein du document, un IdP n'est conservé que s'il parle SAML 2.0 et publie un
`SingleSignOnService` HTTP-Redirect. Une entité décrite deux fois est entièrement
écartée, puisque rien ne dit quelle description est la bonne, et le certificat illisible
d'un membre exclut ce membre, pas la fédération.

## Ce que chaque IdP peut dire {#what-each-idp-may-say}

Une fédération compte des centaines de membres, et n'importe lequel pourrait sinon dire que c'est
`alice@another-university.fr`. Les métadonnées de chaque membre listent ses
`shibmd:Scope`, les domaines dont il peut se porter garant ; une portée en expression régulière est
ignorée, pas honorée.

**Identifiants.** Une valeur à portée (`subject-id`, `pairwise-id`,
`eduPersonPrincipalName`, `eduPersonScopedAffiliation`) hors des portées de l'IdP
qui l'affirme est **écartée**, et une valeur comportant plus d'un `@` n'est dans aucune
portée.

**Groupes.** Lorsque plus d'un IdP est autorisé à se connecter, une valeur `eduPersonEntitlement`
ou `isMemberOf` n'est conservée que si son espace de noms est l'une des portées de cet IdP
ou se trouve sous l'une d'elles :

| valeur | son espace de noms |
|---|---|
| `urn:mace:<domain>:...` | `<domain>` |
| `urn:geant:<domain>:...` (AARC-G002) | `<domain>` |
| `https://<host>/...` | `<host>` |
| toute autre chose | aucun : écartée |

Les groupes décident de ce qu'une personne peut faire, sur chaque serveur de ressources et dans chaque
certificat, donc une valeur que personne ne sait situer n'est pas transmise. Un proxy communautaire
qui affirme des groupes pour des personnes de nombreux établissements est nommé explicitement, par
entity ID, avec les préfixes qu'il peut affirmer :

```hcl
claims {
  trusted_groups = {
    "https://proxy.eduteams.org/saml2/idp/metadata.php" = ["urn:geant:eduteams.org:"]
  }
}
```

Avec exactement un IdP dans `saml { idps }`, cet IdP fait foi pour toute valeur.

## D'une assertion aux revendications {#from-an-assertion-to-claims}

```hcl
claims {
  username = "eppn"            # preferred_username: eppn, subject_id, uid or mail
  groups   = ["entitlement"]   # groups: entitlement, scoped_affiliation, affiliation, is_member_of
}
```

`uid` et `mail` ne sont tenus à aucune portée, et `affiliation` (`staff`,
`student`) ne nomme aucun établissement. Chacun exige donc que `saml { idps }` liste exactement
un IdP ; s'il y en a plus, ils sont [refusés au démarrage]({{< relref "/authn-bridge/configuration.md#what-is-refused-at-startup" >}}).

**`sub`.** L'identifiant sur lequel il repose est pris dans cet ordre : `subject-id`, puis
`pairwise-id`, puis `eduPersonPrincipalName`, puis `eduPersonTargetedID`, puis
un NameID persistant dont le qualificatif est l'IdP lui-même. Il est qualifié par l'entity ID
de l'IdP, et `sub` en est un HMAC-SHA256 sous le sel de sujet :
stable, non réversible, pas une adresse. `public` est le même pour tous les clients,
`pairwise` diffère selon le client. Un IdP qui ne transmet aucun de ces identifiants est refusé,
puisque personne ne pourrait être reconnu deux fois. **L'adresse mail n'est jamais un identifiant**, et
il n'y a pas d'`email_verified` : qu'un IdP affirme une adresse ne signifie pas que quiconque
ait vérifié que la personne la lit.

**Ce que la requête demande à l'IdP.** `prompt=none` devient `IsPassive`, et
un IdP sans session répond `login_required`. `prompt=login` et `max_age=0`
deviennent `ForceAuthn` ; pour tout autre `max_age`, une personne que son IdP a authentifiée
il y a plus longtemps que cela est renvoyée avec `ForceAuthn`. `acr_values` devient
`RequestedAuthnContext`, et un IdP qui répond avec un autre contexte est
refusé : un client qui a demandé un second facteur ne se voit jamais dire qu'il l'a obtenu
quand ce n'est pas le cas.

## Les métadonnées du fournisseur de service {#the-sp-metadata}

`authn-bridge metadata` affiche ce qu'il faut enregistrer auprès de la fédération, sans
rien récupérer (le certificat est abrégé ici) :

```
$ authn-bridge metadata --config etc/bridge.hcl
<?xml version="1.0" encoding="UTF-8"?>
<md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" xmlns:ds="http://www.w3.org/2000/09/xmldsig#" xmlns:mdui="urn:oasis:names:tc:SAML:metadata:ui" xmlns:idpdisc="urn:oasis:names:tc:SAML:profiles:SSO:idp-discovery-protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" entityID="http://127.0.0.1:18080/saml">
  <md:SPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol" AuthnRequestsSigned="false" WantAssertionsSigned="true">
    <md:Extensions>
      <mdui:UIInfo>
        <mdui:DisplayName xml:lang="en">127.0.0.1:18080</mdui:DisplayName>
      </mdui:UIInfo>
    </md:Extensions>
    <md:KeyDescriptor>
      <ds:KeyInfo>
        <ds:X509Data>
          <ds:X509Certificate>MIID…</ds:X509Certificate>
        </ds:X509Data>
      </ds:KeyInfo>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2009/xmlenc11#aes128-gcm"/>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2009/xmlenc11#aes256-gcm"/>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2009/xmlenc11#rsa-oaep"/>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#rsa-oaep-mgf1p"/>
    </md:KeyDescriptor>
    <md:AssertionConsumerService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="http://127.0.0.1:18080/saml/acs" index="0" isDefault="true"/>
    <md:AttributeConsumingService index="0">
      <md:ServiceName xml:lang="en">127.0.0.1:18080</md:ServiceName>
      <md:RequestedAttribute Name="urn:oasis:names:tc:SAML:attribute:subject-id" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:1.3.6.1.4.1.5923.1.1.1.6" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:0.9.2342.19200300.100.1.3" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:2.16.840.1.113730.3.1.241" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:2.5.4.42" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:2.5.4.4" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:1.3.6.1.4.1.5923.1.1.1.7" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
    </md:AttributeConsumingService>
  </md:SPSSODescriptor>
</md:EntityDescriptor>
```

Les assertions doivent être signées (`WantAssertionsSigned="true"`), et sont remises
à `/saml/acs` par HTTP-POST. Le même document est servi à `/saml/metadata`.

## Ce qui est refusé {#what-is-refused}

À l'ACS, tout ce que go-authn/saml refuse : une assertion non signée ou en SHA-1,
plusieurs assertions, une assertion rejouée, un identifiant dans une portée étrangère. Puis les
refus propres à ce fournisseur :

- une réponse d'IdP remise **dans un autre navigateur** : la connexion est retrouvée
  par son propre cookie scellé, jamais par le `RelayState` que porte la réponse,
  sans quoi n'importe qui pourrait connecter quelqu'un d'autre sous sa propre identité ;
- un IdP que la configuration n'autorise plus, ou que l'API d'administration a
  désactivé ;
- une personne ou un établissement [désactivé ici]({{< relref "/authn-bridge/admin.md" >}}),
  quoi qu'en dise l'établissement.

Au démarrage, une liste d'IdP conjointe au service de découverte de RENATER, qui
les liste tous et ne peut pas être restreint :

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
```
