---
title: "フェデレーション側"
linkTitle: "フェデレーション側"
weight: 30
description: "authn-bridge が SAML フェデレーションのメタデータを読み、その署名者を固定し、すべての IdP をそれ自身のスコープに縛り、アサーションをクレームに変換する方法。"
tags: [authn-bridge, saml, renater, edugain]
---

この側では、authn-bridge は SAML サービスプロバイダーです。フェデレーション (RENATER の
Fédération Éducation-Recherche、または eduGAIN) に一度登録され、フェデレーションの
**メタデータ**を信頼します。メタデータは署名された一つの文書で、すべてのメンバー IdP、その署名鍵、
各 IdP が保証してよいドメインを列挙しています。SAML のコードは
[go-authn/saml]({{< relref "/libraries/_index.md" >}}) です。

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

| キー | 既定値 | |
|---|---|---|
| `entity_id` | 発行者 + `/saml` | フェデレーション内でのこのサービスプロバイダーの名前 |
| `key_file`、`cert_file` | | SP の RSA 鍵と証明書 |
| `metadata_url` | | `https://`、他のものが保持するコピーなら `file://`、ループバックに限り `http://` |
| `metadata_cert_file`、`metadata_fingerprint` | | フェデレーションの署名証明書とその SHA-256 フィンガープリント。どちらも必須 |
| `discovery` | このプロバイダー自身の一覧 | 人々を送り込む外部のディスカバリーサービス |
| `idps` | フェデレーションのすべての IdP | ログインをこれらのエンティティ ID に制限する |
| `names`、`descriptions`、`information_url`、`privacy_statement_url`、`technical_contact` | 名前としての発行者のホスト | SP メタデータに入るもの |

## メタデータの署名者は固定される {#the-metadatas-signer-is-pinned}

メタデータに署名する証明書はこのホスト上のファイルで、その SHA-256 フィンガープリントは設定に
書かれています。証明書は**起動のたびに**フィンガープリントと照合されるので、ディスク上で
置き換えられたファイルは信頼されずに検出されます。

```
authn-bridge: saml: fed/fed.crt is not the certificate with fingerprint 68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0
```

保証する対象の文書と同じ経路で届く鍵は、何も保証しません。そのためフィンガープリントは
フェデレーションのウェブページから入手し、証明書を運んできたダウンロードからは決して
入手しません。

```sh
openssl x509 -in /etc/authn-bridge/metadata-signature-2026.pem -noout -fingerprint -sha256
```

## 文書が拒否される場合 {#a-document-is-refused}

- その証明書で署名されていない、SHA-1 で署名されている、または署名がルート以外の要素を
  対象としている場合
- **`validUntil` がない、またはそれを過ぎている場合。** これは 2026 年 9 月 29 日に公開された
  RENATER 自身のメタデータを、10 月 10 日に読んだものです。

  ```
  $ authn-bridge check --config v/renater-expired.hcl
  authn-bridge: the federation's metadata: metadata expired at 2026-10-08T07:30:02Z
  ```

- `validUntil` が 28 日より先の場合: 何年も有効な文書は、リプレイによって何年も生かされ続け
  かねません
- **使用中のものより古い場合** (`validUntil` がより早い)。正しく署名されていて、まだ期限切れ
  でもないので、他に拒否するものがなく、途中にいる誰かが提供する、その後に失効した鍵を持つ
  ものかもしれません
- ループバック以外への平文の `http` の場合。署名は変更を検出しますが、新しい文書を止めて古い
  ものを提供し続けるプロキシは検出できません

## メタデータの更新 {#refreshing-it}

メタデータはプロバイダーが待ち受けを始める前に取得され、その後は文書の `cacheDuration` の
四分の三の時点で再度取得されます。五分より早くも、十二時間より遅くもならず、管理 API の
`RefreshMetadata` が求めたときにも取得されます。失敗した更新は最後の正常なコピーを保持しますが、
**そのコピー自身の `validUntil` までに限ります**。それを過ぎると何も保証されず、すべての IdP が
消え、`/readyz` はプロバイダーが ready でないと述べます。フェデレーションのサーバーに短時間
届かないだけなら誰もログアウトされませんが、何日も届かない場合に、プロバイダーが古い鍵を
信頼し続けることはありません。

文書内では、IdP は SAML 2.0 を話し、HTTP-Redirect の `SingleSignOnService` を公開している
場合にのみ保持されます。二度記述されたエンティティは、どちらの記述が正しいか分からないので、
完全に除外されます。あるメンバーの読めない証明書は、フェデレーションではなくそのメンバーだけを
除外します。

## 各 IdP が述べてよいこと {#what-each-idp-may-say}

フェデレーションには数百のメンバーがいて、そのどれもが、そうでなければ自分は
`alice@another-university.example` だと述べることができてしまいます。すべてのメンバーの
メタデータは、保証してよいドメインである `shibmd:Scope` を列挙しており、正規表現のスコープは
尊重されずに無視されます。

**識別子。** スコープ付きの値 (`subject-id`、`pairwise-id`、`eduPersonPrincipalName`、
`eduPersonScopedAffiliation`) が、表明している IdP のスコープの外にあれば**破棄され**、`@` が
二つ以上ある値はどのスコープにも属しません。

**グループ。** ログインを許された IdP が複数ある場合、`eduPersonEntitlement` または
`isMemberOf` の値は、その名前空間がその IdP のスコープのいずれか、またはその配下にある場合に
のみ保持されます。

| 値 | その名前空間 |
|---|---|
| `urn:mace:<domain>:...` | `<domain>` |
| `urn:geant:<domain>:...` (AARC-G002) | `<domain>` |
| `https://<host>/...` | `<host>` |
| それ以外 | なし: 破棄 |

グループは、すべてのリソースサーバーとすべての証明書で、人が何をしてよいかを決めるので、
誰も位置づけられない値は渡されません。多くの機関の人々のグループを表明するコミュニティ
プロキシは、エンティティ ID で明示的に指名され、表明してよいプレフィックスも指定されます。

```hcl
claims {
  trusted_groups = {
    "https://proxy.eduteams.org/saml2/idp/metadata.php" = ["urn:geant:eduteams.org:"]
  }
}
```

`saml { idps }` にちょうど一つの IdP がある場合は、その IdP がすべての値について信頼されます。

## アサーションからクレームへ {#from-an-assertion-to-claims}

```hcl
claims {
  username = "eppn"            # preferred_username: eppn, subject_id, uid or mail
  groups   = ["entitlement"]   # groups: entitlement, scoped_affiliation, affiliation, is_member_of
}
```

`uid` と `mail` はどのスコープにも縛られず、`affiliation` (`staff`、`student`) はどの機関も
指しません。そのためどれも、`saml { idps }` にちょうど一つの IdP が列挙されている必要があり、
複数ある場合は[起動時に拒否されます]({{< relref "/authn-bridge/configuration.md#what-is-refused-at-startup" >}})。

**`sub`。** その元になる識別子は、`subject-id`、`pairwise-id`、`eduPersonPrincipalName`、
`eduPersonTargetedID`、そして修飾子が IdP 自身である永続的な NameID の順で採用されます。
IdP のエンティティ ID で修飾され、`sub` はそれをサブジェクトソルトの下で HMAC-SHA256 にした
ものです。安定していて、元に戻せず、アドレスではありません。`public` はすべてのクライアントで
同じで、`pairwise` はクライアントごとに異なります。これらのどれも出さない IdP は、誰も二度
認識できなくなるので拒否されます。**メールは決して識別子になりません**。`email_verified` も
ありません。IdP がアドレスを表明しても、その人がそれを読めると誰かが確認したことにはならない
からです。

**リクエストが IdP に求めること。** `prompt=none` は `IsPassive` になり、セッションのない IdP は
`login_required` を返します。`prompt=login` と `max_age=0` は `ForceAuthn` になります。それ以外の
`max_age` では、IdP がそれより前に認証した人は `ForceAuthn` 付きで送り返されます。`acr_values` は
`RequestedAuthnContext` になり、別のコンテキストで応答する IdP は拒否されます。第二要素を求めた
クライアントが、実際にはそうでないのに得たと告げられることは決してありません。

## SP メタデータ {#the-sp-metadata}

`authn-bridge metadata` は、何も取得せずに、フェデレーションに登録するものを出力します
(ここでは証明書を短縮しています)。

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

アサーションは署名されていなければならず (`WantAssertionsSigned="true"`)、HTTP-POST で
`/saml/acs` に届けられます。同じ文書が `/saml/metadata` でも提供されます。

## 拒否されるもの {#what-is-refused}

ACS では、go-authn/saml が拒否するすべてです。署名のない、または SHA-1 のアサーション、複数の
アサーション、リプレイされたもの、他のスコープの識別子。そしてこのプロバイダー自身の拒否が
続きます。

- **別のブラウザーに届けられた** IdP の応答: ログインは、応答が運ぶ `RelayState` ではなく、
  その人自身の封印されたクッキーを通じて見つけられます。そうでなければ、誰でも自分の IdP の
  応答を他人のブラウザーに送り、送信者の ID でその人をログインさせられてしまいます
- 設定がもう許可していない、または管理 API が無効化した IdP
- [ここで無効化された]({{< relref "/authn-bridge/admin.md" >}})人や機関。その機関が何と言おうと

起動時には、すべてを列挙して制限できない RENATER のディスカバリーサービスと IdP のリストを
併用している場合に:

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
```
