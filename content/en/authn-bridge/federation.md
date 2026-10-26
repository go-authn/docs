---
title: "The federation side"
linkTitle: "The federation side"
weight: 30
description: "How authn-bridge reads a SAML federation's metadata, pins its signer, holds every IdP to its own scopes, and turns an assertion into claims."
tags: [authn-bridge, saml, renater, edugain]
---

On this side authn-bridge is a SAML service provider. It is registered once with
the federation (RENATER's Fédération Éducation-Recherche, or eduGAIN), and it
trusts the federation's **metadata**: one signed document that lists every
member IdP, their signing keys, and the domains each may vouch for. The SAML
code is [go-authn/saml]({{< relref "/libraries/_index.md" >}}).

```hcl
saml {
  key_file  = "/var/lib/authn-bridge/saml.key"   # RSA: IdPs encrypt assertions to it
  cert_file = "/var/lib/authn-bridge/saml.crt"

  metadata_url         = "https://pub.federation.renater.fr/metadata/fer/idps.xml"
  metadata_cert_file   = "/etc/authn-bridge/metadata-signature-2026.pem"
  metadata_fingerprint = "68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0"

  discovery = "https://discovery.renater.fr/renater"   # or leave it out for this provider's own list
  # idps    = ["https://idp.univ-example.example/idp/shibboleth"]   # restrict; one entry skips the choice

  names             = { fr = "Passerelle OIDC", en = "OIDC gateway" }
  technical_contact = "admin@example.org"
}
```

| key | default | |
|---|---|---|
| `entity_id` | the issuer + `/saml` | this service provider's name in the federation |
| `key_file`, `cert_file` | | the SP's RSA key and certificate |
| `metadata_url` | | `https://`, `file://` for a copy something else keeps, or `http://` on loopback only |
| `metadata_cert_file`, `metadata_fingerprint` | | the federation's signing certificate and its SHA-256 fingerprint, both required |
| `discovery` | this provider's own list | an external discovery service to send people to |
| `idps` | every IdP of the federation | restrict login to these entity IDs |
| `names`, `descriptions`, `information_url`, `privacy_statement_url`, `technical_contact` | the issuer's host as the name | what goes in the SP metadata |

## The metadata's signer is pinned

The certificate that signs the metadata is a file on this host, and its SHA-256
fingerprint is written in the configuration. The certificate is checked
against the fingerprint **at every start**, so a file replaced on disk is noticed
rather than trusted:

```
authn-bridge: saml: fed/fed.crt is not the certificate with fingerprint 68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0
```

A key that arrives over the same channel as the document it vouches for vouches
for nothing. So the fingerprint comes from the federation's web page, never from
the download that brought the certificate:

```sh
openssl x509 -in /etc/authn-bridge/metadata-signature-2026.pem -noout -fingerprint -sha256
```

## A document is refused

- when it is not signed by that certificate, or is signed with SHA-1, or its
  signature covers another element than the root;
- **when it has no `validUntil`, or is past it.** This is RENATER's own
  metadata as it was published on 29 September 2026, read on 10 October:

  ```
  $ authn-bridge check --config v/renater-expired.hcl
  authn-bridge: the federation's metadata: metadata expired at 2026-10-08T07:30:02Z
  ```

  *Not run again: that metadata is no longer published, so this is the output captured on 10 October 2026.*

- when its `validUntil` is more than 28 days away: a document valid for years
  is one a replay keeps alive for years;
- **when it is older than the one in use** (an earlier `validUntil`). It is
  validly signed and not yet expired, so nothing else would refuse it, and it
  may be the one with a key since revoked, served by whoever stands on the path;
- over plain `http` to anything but loopback. The signature would catch a
  change, but not a proxy that holds back the new document and keeps serving
  the old one.

## Refreshing it

The metadata is fetched before the provider listens, then again at three
quarters of the document's `cacheDuration`, never sooner than five minutes nor
later than twelve hours, and whenever the admin API's `RefreshMetadata` asks.
A refresh that fails keeps the last good copy, **but only until its own
`validUntil`**. After that nothing is vouched for, every IdP disappears, and
`/readyz` says the provider is not ready. A federation server briefly
unreachable logs nobody out; one unreachable for days does not leave the
provider trusting stale keys.

Within the document, an IdP is kept only if it speaks SAML 2.0 and publishes an
HTTP-Redirect `SingleSignOnService`. An entity described twice is dropped
altogether, since nothing says which description is right, and one member's
unreadable certificate leaves out that member, not the federation.

## What each IdP may say

A federation has hundreds of members, and any of them could otherwise say it is
`alice@another-university.example`. Every member's metadata lists its
`shibmd:Scope`s, the domains it may vouch for; a regular-expression scope is
ignored, not honoured.

**Identifiers.** A scoped value (`subject-id`, `pairwise-id`,
`eduPersonPrincipalName`, `eduPersonScopedAffiliation`) outside the asserting
IdP's scopes is **dropped**, and a value with more than one `@` is not in any
scope.

**Groups.** With more than one IdP allowed to log in, an `eduPersonEntitlement`
or `isMemberOf` value is kept only if its namespace is one of that IdP's scopes
or under one:

| value | its namespace |
|---|---|
| `urn:mace:<domain>:...` | `<domain>` |
| `urn:geant:<domain>:...` (AARC-G002) | `<domain>` |
| `https://<host>/...` | `<host>` |
| anything else | none: dropped |

Groups decide what a person may do, at every resource server and in every
certificate, so a value nobody can place is not passed on. A community proxy
that asserts groups for people of many institutions is named explicitly, by
entity ID, with the prefixes it may assert:

```hcl
claims {
  trusted_groups = {
    "https://proxy.eduteams.org/saml2/idp/metadata.php" = ["urn:geant:eduteams.org:"]
  }
}
```

With exactly one IdP in `saml { idps }`, that IdP is trusted for every value.

## From an assertion to claims

```hcl
claims {
  username = "eppn"            # preferred_username: eppn, subject_id, uid or mail
  groups   = ["entitlement"]   # groups: entitlement, scoped_affiliation, affiliation, is_member_of
}
```

`uid` and `mail` are not held to any scope, and `affiliation` (`staff`,
`student`) names no institution. So each needs `saml { idps }` to list exactly
one IdP; with more, they are [refused at startup]({{< relref "/authn-bridge/configuration.md#what-is-refused-at-startup" >}}).

**`sub`.** The identifier behind it is taken in this order: `subject-id`, then
`pairwise-id`, then `eduPersonPrincipalName`, then `eduPersonTargetedID`, then
a persistent NameID whose qualifier is the IdP itself. It is qualified by the
IdP's entity ID, and `sub` is an HMAC-SHA256 of it under the subject salt:
stable, not reversible, not an address. `public` is the same for every client,
`pairwise` differs per client. An IdP that releases none of these is refused,
since nobody could be recognised twice. **Mail is never an identifier**, and
there is no `email_verified`: an IdP asserting an address is not anybody
having verified that the person reads it.

**What the request asks of the IdP.** `prompt=none` becomes `IsPassive`, and
an IdP with no session answers `login_required`. `prompt=login` and `max_age=0`
become `ForceAuthn`; for any other `max_age`, a person whose IdP authenticated
them longer ago than that is sent back with `ForceAuthn`. `acr_values` becomes
`RequestedAuthnContext`, and an IdP that answers with another context is
refused: a client that asked for a second factor is never told it got one
when it did not.

## The SP metadata

`authn-bridge metadata` prints what to register with the federation, without
fetching anything (the certificate is shortened here):

```
$ authn-bridge metadata --config etc/bridge.hcl
<?xml version="1.0" encoding="UTF-8"?>
<md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" xmlns:ds="http://www.w3.org/2000/09/xmldsig#" xmlns:mdui="urn:oasis:names:tc:SAML:metadata:ui" xmlns:idpdisc="urn:oasis:names:tc:SAML:profiles:SSO:idp-discovery-protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" entityID="http://127.0.0.1:28473/saml">
  <md:SPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol" AuthnRequestsSigned="false" WantAssertionsSigned="true">
    <md:Extensions>
      <mdui:UIInfo>
        <mdui:DisplayName xml:lang="en">127.0.0.1:28473</mdui:DisplayName>
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
    <md:AssertionConsumerService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="http://127.0.0.1:28473/saml/acs" index="0" isDefault="true"/>
    <md:AttributeConsumingService index="0">
      <md:ServiceName xml:lang="en">127.0.0.1:28473</md:ServiceName>
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

Assertions must be signed (`WantAssertionsSigned="true"`), and are delivered
to `/saml/acs` by HTTP-POST. The same document is served at `/saml/metadata`.

## What is refused

At the ACS, everything go-authn/saml refuses: an unsigned or SHA-1 assertion,
several assertions, a replayed one, an identifier in a foreign scope. Then this
provider's own refusals:

- an IdP response delivered **into another browser**: the login is found
  through its own sealed cookie, never through the `RelayState` the response
  carries; otherwise anybody could send their own IdP response to somebody
  else's browser and log that person in under the sender's identity;
- an IdP that the configuration no longer allows, or that the admin API has
  disabled;
- a person or an institution [disabled here]({{< relref "/authn-bridge/admin.md" >}}),
  whatever the institution says.

At startup, a list of IdPs together with RENATER's discovery service, which
lists them all and cannot be restricted:

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
```
