---
title: "페더레이션 측"
linkTitle: "페더레이션 측"
weight: 30
description: "authn-bridge가 SAML 페더레이션의 메타데이터를 읽고, 서명자를 고정하고, 모든 IdP를 자신의 스코프로 제한하고, 어서션을 클레임으로 바꾸는 방법."
tags: [authn-bridge, saml, renater, edugain]
---

이 측면에서 authn-bridge는 SAML 서비스 공급자입니다. 페더레이션(RENATER의 Fédération
Éducation-Recherche 또는 eduGAIN)에 한 번 등록되며, 페더레이션의 **메타데이터**를
신뢰합니다. 메타데이터는 모든 구성원 IdP, 그들의 서명 키, 각 IdP가 보증할 수 있는
도메인을 나열한 서명된 문서 하나입니다. SAML 코드는
[go-authn/saml]({{< relref "/libraries/_index.md" >}})입니다.

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

| 키 | 기본값 | |
|---|---|---|
| `entity_id` | 발급자 + `/saml` | 페더레이션에서 이 서비스 공급자의 이름 |
| `key_file`, `cert_file` | | SP의 RSA 키와 인증서 |
| `metadata_url` | | `https://`, 다른 것이 관리하는 사본이면 `file://`, 루프백에서만 `http://` |
| `metadata_cert_file`, `metadata_fingerprint` | | 페더레이션의 서명 인증서와 그 SHA-256 지문, 둘 다 필수 |
| `discovery` | 이 공급자 자체의 목록 | 사람들을 보낼 외부 디스커버리 서비스 |
| `idps` | 페더레이션의 모든 IdP | 로그인을 이 엔티티 ID로 제한 |
| `names`, `descriptions`, `information_url`, `privacy_statement_url`, `technical_contact` | 이름으로 발급자의 호스트 | SP 메타데이터에 들어가는 것 |

## 메타데이터의 서명자는 고정됩니다 {#the-metadatas-signer-is-pinned}

메타데이터에 서명하는 인증서는 이 호스트의 파일이고, 그 SHA-256 지문은 구성에
적혀 있습니다. 인증서는 **매번 시작할 때** 지문과 대조되므로, 디스크에서 바뀐
파일은 신뢰되지 않고 발견됩니다.

```
authn-bridge: saml: fed/fed.crt is not the certificate with fingerprint 68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0
```

보증하는 문서와 같은 경로로 도착한 키는 아무것도 보증하지 못합니다. 그래서 지문은
인증서를 가져온 다운로드가 아니라 페더레이션의 웹 페이지에서 가져옵니다.

```sh
openssl x509 -in /etc/authn-bridge/metadata-signature-2026.pem -noout -fingerprint -sha256
```

## 문서가 거부되는 경우 {#a-document-is-refused}

- 그 인증서로 서명되지 않았거나, SHA-1로 서명되었거나, 서명이 루트가 아닌 다른
  요소를 덮는 경우
- **`validUntil`이 없거나 이미 지난 경우.** 다음은 2026년 9월 29일에 게시된 RENATER
  자체 메타데이터를 10월 10일에 읽은 것입니다.

  ```
  $ authn-bridge check --config v/renater-expired.hcl
  authn-bridge: the federation's metadata: metadata expired at 2026-10-08T07:30:02Z
  ```

- `validUntil`이 28일보다 더 먼 경우: 수년간 유효한 문서는 재생 공격이 수년간 살려
  둘 수 있는 문서입니다
- **사용 중인 것보다 오래된 경우**(더 이른 `validUntil`). 유효하게 서명되었고 아직
  만료되지 않았으므로 다른 어떤 것도 이를 거부하지 않으며, 그 사이 폐기된 키를 가진
  문서를 경로에 있는 누군가가 제공하는 것일 수 있습니다
- 루프백이 아닌 곳으로의 일반 `http`. 서명이 변경은 잡아내겠지만, 새 문서를 붙잡고
  이전 문서를 계속 제공하는 프록시는 잡아내지 못합니다

## 갱신 {#refreshing-it}

메타데이터는 공급자가 수신하기 전에 가져오고, 문서의 `cacheDuration`의 4분의 3
시점에 다시 가져오며(5분보다 빠르지 않게, 12시간보다 늦지 않게), 관리 API의
`RefreshMetadata`가 요청할 때마다 가져옵니다. 갱신이 실패하면 마지막으로 성공한
사본을 유지하지만, **그 자체의 `validUntil`까지만** 유지합니다. 그 뒤에는 아무것도
보증되지 않고, 모든 IdP가 사라지며, `/readyz`는 공급자가 준비되지 않았다고
알려 줍니다. 잠시 접근할 수 없는 페더레이션 서버는 아무도 로그아웃시키지 않지만,
며칠 동안 접근할 수 없는 서버는 공급자가 오래된 키를 계속 신뢰하게 두지 않습니다.

문서 안에서 IdP는 SAML 2.0을 사용하고 HTTP-Redirect `SingleSignOnService`를
게시하는 경우에만 유지됩니다. 두 번 기술된 엔티티는 어느 쪽이 맞는지 알 수 없으므로
통째로 제외되며, 한 구성원의 읽을 수 없는 인증서는 페더레이션이 아니라 그
구성원만 제외합니다.

## 각 IdP가 말할 수 있는 것 {#what-each-idp-may-say}

페더레이션에는 수백 개의 구성원이 있고, 그렇지 않으면 그중 어느 것이든 자신이
`alice@another-university.example`이라고 말할 수 있습니다. 모든 구성원의 메타데이터는
자신의 `shibmd:Scope`, 즉 보증할 수 있는 도메인을 나열하며, 정규 표현식 스코프는
존중되지 않고 무시됩니다.

**식별자.** 어서션한 IdP의 스코프 밖에 있는 스코프 값(`subject-id`, `pairwise-id`,
`eduPersonPrincipalName`, `eduPersonScopedAffiliation`)은 **버려지며**, `@`가 둘
이상인 값은 어떤 스코프에도 속하지 않습니다.

**그룹.** 로그인이 허용된 IdP가 둘 이상이면 `eduPersonEntitlement` 또는
`isMemberOf` 값은 그 네임스페이스가 해당 IdP의 스코프 중 하나이거나 그 아래에
있을 때만 유지됩니다.

| 값 | 네임스페이스 |
|---|---|
| `urn:mace:<domain>:...` | `<domain>` |
| `urn:geant:<domain>:...` (AARC-G002) | `<domain>` |
| `https://<host>/...` | `<host>` |
| 그 밖의 모든 것 | 없음: 버려짐 |

그룹은 모든 리소스 서버와 모든 인증서에서 사람이 무엇을 할 수 있는지를 결정하므로,
위치를 알 수 없는 값은 전달되지 않습니다. 많은 기관의 사람들에 대해 그룹을 어서션하는
커뮤니티 프록시는 엔티티 ID로 명시적으로 지명하며, 어서션할 수 있는 접두사와 함께
지정합니다.

```hcl
claims {
  trusted_groups = {
    "https://proxy.eduteams.org/saml2/idp/metadata.php" = ["urn:geant:eduteams.org:"]
  }
}
```

`saml { idps }`에 IdP가 정확히 하나이면 그 IdP는 모든 값에 대해 신뢰됩니다.

## 어서션에서 클레임으로 {#from-an-assertion-to-claims}

```hcl
claims {
  username = "eppn"            # preferred_username: eppn, subject_id, uid or mail
  groups   = ["entitlement"]   # groups: entitlement, scoped_affiliation, affiliation, is_member_of
}
```

`uid`와 `mail`은 어떤 스코프에도 묶여 있지 않고, `affiliation`(`staff`,
`student`)은 기관을 지명하지 않습니다. 그래서 각각 `saml { idps }`가 정확히 하나의
IdP를 나열해야 하며, 더 많으면
[시작 시 거부됩니다]({{< relref "/authn-bridge/configuration.md#what-is-refused-at-startup" >}}).

**`sub`.** 그 뒤의 식별자는 이 순서로 취합니다. `subject-id`, 그다음 `pairwise-id`,
그다음 `eduPersonPrincipalName`, 그다음 `eduPersonTargetedID`, 그다음 한정자가 IdP
자신인 영구 NameID. 이는 IdP의 엔티티 ID로 한정되고, `sub`는 주체 솔트 아래의 그것의
HMAC-SHA256이며, 안정적이고 되돌릴 수 없고 주소가 아닙니다. `public`은 모든
클라이언트에 같고 `pairwise`는 클라이언트마다 다릅니다. 이 중 아무것도 내주지 않는
IdP는 거부됩니다. 아무도 두 번 인식될 수 없기 때문입니다. **메일은 절대 식별자가
아니며**, `email_verified`도 없습니다. IdP가 주소를 어서션하는 것은 누군가가 그
사람이 그 주소를 읽는다는 것을 확인했다는 뜻이 아닙니다.

**요청이 IdP에 요구하는 것.** `prompt=none`은 `IsPassive`가 되고, 세션이 없는 IdP는
`login_required`로 응답합니다. `prompt=login`과 `max_age=0`은 `ForceAuthn`이 되며,
그 밖의 `max_age`에 대해서는 IdP가 그보다 오래 전에 인증한 사람이 `ForceAuthn`과
함께 다시 보내집니다. `acr_values`는 `RequestedAuthnContext`가 되고, 다른 컨텍스트로
응답하는 IdP는 거부됩니다. 두 번째 인증 요소를 요청한 클라이언트는 받지 못했는데도
받았다는 말을 절대 듣지 않습니다.

## SP 메타데이터 {#the-sp-metadata}

`authn-bridge metadata`는 아무것도 가져오지 않고 페더레이션에 등록할 내용을
출력합니다(인증서는 여기서 줄였습니다).

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
          <ds:X509Certificate>MIIE…</ds:X509Certificate>
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

어서션은 서명되어야 하며(`WantAssertionsSigned="true"`), HTTP-POST로 `/saml/acs`에
전달됩니다. 같은 문서가 `/saml/metadata`에서 제공됩니다.

## 거부되는 것 {#what-is-refused}

ACS에서는 go-authn/saml이 거부하는 모든 것: 서명되지 않았거나 SHA-1인 어서션, 여러
어서션, 재생된 어서션, 외부 스코프의 식별자. 그다음 이 공급자 자체의 거부:

- **다른 브라우저로** 전달된 IdP 응답: 로그인은 응답이 담고 있는 `RelayState`가
  아니라 자체의 봉인된 쿠키로 찾습니다. 그렇지 않으면 누구든 자신의 IdP 응답을 다른
  사람의 브라우저로 보내 그 사람을 보낸 사람의 신원으로 로그인시킬 수 있습니다
- 구성이 더 이상 허용하지 않거나 관리 API가 비활성화한 IdP
- 소속 기관이 무엇이라고 하든,
  [여기서 비활성화된]({{< relref "/authn-bridge/admin.md" >}}) 사람이나 기관

시작할 때, 모든 IdP를 나열하며 제한할 수 없는 RENATER의 디스커버리 서비스와 함께
IdP 목록을 지정한 경우:

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
```
