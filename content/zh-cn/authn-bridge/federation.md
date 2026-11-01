---
title: "联邦一侧"
linkTitle: "联邦一侧"
weight: 30
description: "authn-bridge 如何读取 SAML 联邦的元数据、固定其签名者、让每个 IdP 受其自身 scope 约束，并把断言转换为声明。"
tags: [authn-bridge, saml, renater, edugain]
---

在这一侧，authn-bridge 是 SAML 服务提供方。它向联邦（RENATER 的 Fédération
Éducation-Recherche，或 eduGAIN）注册一次，并且
信任联邦的**元数据**：一份已签名的文档，列出每个
成员 IdP、它们的签名密钥，以及各自可以为之担保的域。SAML
代码是 [go-authn/saml]({{< relref "/libraries/_index.md" >}})。

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

| 键 | 默认值 | |
|---|---|---|
| `entity_id` | 签发方 + `/saml` | 此服务提供方在联邦中的名称 |
| `key_file`、`cert_file` | | SP 的 RSA 密钥和证书 |
| `metadata_url` | | `https://`，由其他程序维护的副本用 `file://`，或仅限环回的 `http://` |
| `metadata_cert_file`、`metadata_fingerprint` | | 联邦的签名证书及其 SHA-256 指纹，二者都是必需的 |
| `discovery` | 本提供方自己的列表 | 将人员引导至的外部发现服务 |
| `idps` | 联邦的所有 IdP | 将登录限制在这些实体 ID 之内 |
| `names`、`descriptions`、`information_url`、`privacy_statement_url`、`technical_contact` | 以签发方的主机作为名称 | 写入 SP 元数据的内容 |

## 元数据的签名者被固定 {#the-metadatas-signer-is-pinned}

为元数据签名的证书是此主机上的一个文件，而其 SHA-256
指纹写在配置中。**每次启动**都会对照指纹检查该证书，
因此磁盘上被替换的文件会被发现，
而不是被信任：

```
authn-bridge: saml: fed/fed.crt is not the certificate with fingerprint 68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0
```

与它所担保的文档通过同一渠道到达的密钥，什么也担保不了。
因此指纹来自联邦的网页，绝不来自
获取证书的那次下载：

```sh
openssl x509 -in /etc/authn-bridge/metadata-signature-2026.pem -noout -fingerprint -sha256
```

## 文档被拒绝的情形 {#a-document-is-refused}

- 当它不是由该证书签名、使用 SHA-1 签名，或其
  签名覆盖的不是根元素之外的另一个元素时；
- **当它没有 `validUntil`，或已超过该时间时。** 这是 RENATER 自己的
  元数据，发布于 2026 年 9 月 29 日，在 10 月 10 日读取：

  ```
  $ authn-bridge check --config v/renater-expired.hcl
  authn-bridge: the federation's metadata: metadata expired at 2026-10-08T07:30:02Z
  ```

  *没有重新运行：该元数据已不再发布，这是 2026 年 10 月 10 日捕获的输出。*

- 当其 `validUntil` 距今超过 28 天时：有效期长达数年的文档
  会被重放攻击保持数年有效；
- **当它比正在使用的文档更旧时**（`validUntil` 更早）。它
  签名有效且尚未过期，因此没有其他机制会拒绝它，
  而它可能是含有此后已被吊销密钥的那一份，由路径上的
  任何人提供；
- 通过普通 `http` 访问环回之外的任何地址时。签名可以发现
  更改，却发现不了扣留新文档并继续提供
  旧文档的代理。

## 刷新 {#refreshing-it}

元数据在提供方监听之前获取，然后按 go-authn/saml 的 `Federation.Run` 的计划
（自 v0.23.6 起）再次获取：绝不安排在文档 `validUntil` 剩余时间的一半之后，
并介于五分钟与十二小时之间（否则取其 `cacheDuration` 的四分之三），
并且每当管理 API 的 `RefreshMetadata` 要求时也会获取。没有剩余的有效元数据时，
获取在一分钟后重试，之后间隔加倍，直到一小时。直到 v0.23.5，循环无论有效期还剩多少，
都继续等待 `cacheDuration` 的四分之三（没有则十二小时），所以临近有效期结束时的一次刷新失败，
可能让提供方在联邦服务器恢复之后仍有最长十二小时没有任何 IdP。
刷新失败时保留上一份良好的副本，**但只保留到其自身的
`validUntil`**：在此之前登录继续使用它，无论联邦服务器是缓慢、宕机，还是提供了无法验证的文档。
此后不再为任何内容担保，每个 IdP 都会消失，
`/readyz` 会表明提供方尚未就绪。联邦服务器短暂
无法访问不会使任何人退出登录；无法访问数日也不会让
提供方继续信任过期的密钥。

网桥的时钟与 IdP 的时钟可以在任一方向上相差三分钟：时间在此范围内的断言会被接受，相差一小时的则被拒绝并返回
400 页面。用来记住断言以免它被接受两次的键，以其 SHA-256 存储（自 v0.23.6 起）：过长的 IdP `entityID`
或断言 ID 超过了状态数据库的 `VARCHAR(128)` 列，严格模式下的 PostgreSQL 和 MySQL 会拒绝它，
所以写入一直处于挂起状态，提供方一直未就绪。SQLite 不受影响。配置不发生任何变化。

在文档之内，IdP 只有在支持 SAML 2.0 并发布
HTTP-Redirect `SingleSignOnService` 时才会保留。被描述了两次的实体
会被整个丢弃，因为没有任何内容说明哪个描述才是正确的，而某个成员
无法读取的证书只会使该成员被排除，而不是整个联邦。

## 每个 IdP 可以声明什么 {#what-each-idp-may-say}

联邦有数百个成员，否则其中任何一个都可以声称自己是
`alice@another-university.example`。每个成员的元数据都列出其
`shibmd:Scope`，即它可以为之担保的域；正则表达式 scope 会
被忽略，而不是被遵从。

**标识符。** 位于断言方 IdP 的 scope 之外的带 scope 的值（`subject-id`、`pairwise-id`、
`eduPersonPrincipalName`、`eduPersonScopedAffiliation`）会被**丢弃**，
含有多个 `@` 的值不属于任何 scope。

**组。** 当允许登录的 IdP 多于一个时，`eduPersonEntitlement`
或 `isMemberOf` 的值只有在其命名空间是该 IdP 的某个 scope
或位于其下时才会保留：

| 值 | 其命名空间 |
|---|---|
| `urn:mace:<domain>:...` | `<domain>` |
| `urn:geant:<domain>:...`（AARC-G002） | `<domain>` |
| `https://<host>/...` | `<host>` |
| 其他任何值 | 无：丢弃 |

组决定人员可以做什么，在每个资源服务器上、在每个
证书中都是如此，因此无人能够确定归属的值不会被传递。为许多机构的人员
断言组的社区代理，需要按实体 ID 明确指名，并给出它可以断言的
前缀：

```hcl
claims {
  trusted_groups = {
    "https://proxy.eduteams.org/saml2/idp/metadata.php" = ["urn:geant:eduteams.org:"]
  }
}
```

当 `saml { idps }` 中恰好只有一个 IdP 时，该 IdP 的每个值都受到信任。

## 从断言到声明 {#from-an-assertion-to-claims}

```hcl
claims {
  username = "eppn"            # preferred_username: eppn, subject_id, uid or mail
  groups   = ["entitlement"]   # groups: entitlement, scoped_affiliation, affiliation, is_member_of
}
```

`uid` 和 `mail` 不受任何 scope 约束，而 `affiliation`（`staff`、
`student`）不指明任何机构。因此每一个都需要 `saml { idps }` 恰好列出一个
IdP；有更多时，它们会在[启动时被拒绝]({{< relref "/authn-bridge/configuration.md#what-is-refused-at-startup" >}})。

**`sub`。** 其背后的标识符按以下顺序取得：`subject-id`，然后
`pairwise-id`，然后 `eduPersonPrincipalName`，然后 `eduPersonTargetedID`，然后
是限定符为 IdP 自身的持久 NameID。它由
IdP 的实体 ID 限定，而 `sub` 是在主体盐值之下对它计算的 HMAC-SHA256：
稳定、不可逆，也不是地址。`public` 对每个客户端都相同，
`pairwise` 则因客户端而异。不释放其中任何一项的 IdP 会被拒绝，
因为无法两次识别出同一个人。**邮件地址绝不是标识符**，并且
没有 `email_verified`：IdP 断言某个地址，并不等于有人
验证过此人会读取该邮箱。

**请求向 IdP 提出什么要求。** `prompt=none` 变为 `IsPassive`，
没有会话的 IdP 会答复 `login_required`。`prompt=login` 和 `max_age=0`
变为 `ForceAuthn`；对于任何其他 `max_age`，如果其 IdP 认证该人员的
时间比这更早，则该人员会被带着 `ForceAuthn` 送回。`acr_values` 变为
`RequestedAuthnContext`，而以另一个上下文作答的 IdP 会被
拒绝：要求第二因素的客户端绝不会在实际上
没有得到时被告知已经得到。

## SP 元数据 {#the-sp-metadata}

`authn-bridge metadata` 输出要向联邦注册的内容，不会获取任何
内容（此处证书已缩短）：

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

断言必须经过签名（`WantAssertionsSigned="true"`），并通过 HTTP-POST
投递到 `/saml/acs`。同一份文档也在 `/saml/metadata` 提供。

## 什么会被拒绝 {#what-is-refused}

在 ACS 处，go-authn/saml 拒绝的一切：未签名或使用 SHA-1 的断言、
多个断言、被重放的断言、位于外来 scope 中的标识符。然后是本
提供方自己的拒绝：

- **投递到另一个浏览器中**的 IdP 响应：登录是
  通过其自身密封的 cookie 找到的，绝不是通过响应所携带的 `RelayState`；
  否则任何人都可以把自己的 IdP 响应发送到别人的
  浏览器，并以发送者的身份让那个人登录；
- 配置不再允许的 IdP，或管理 API
  已将其禁用的 IdP；
- [在此处被禁用]({{< relref "/authn-bridge/admin.md" >}})的人员或机构，
  无论机构怎么说。

启动时，带有 IdP 列表同时又使用 RENATER 的发现服务的配置会被拒绝，
因为该发现服务列出所有 IdP，无法被限制：

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
```

### 测试了什么 {#tested}

自 v0.23.6 起，README 的 “What it refuses” 列出了通过 ACS 端到端测试的内容：XML 签名包装（XSW1 到 XSW8 及其相同 ID
的变体）、注释截断（CVE-2017-11427）、DOCTYPE 和实体展开、面向其他受众、接收方、请求或目的地的断言，以及重放。
有针对 ACS（`FuzzACSAccept`）、联邦元数据、访问令牌验证（含 `alg` 混淆种子）、登录 Cookie 和重定向 URI 匹配的模糊测试器：
`FuzzACSAccept` 在三分钟内运行了 992,517 次，有 595 个语料条目，没有失败，其余四个各运行约 90 秒，没有失败。
混沌测试把网桥的时钟移动两分钟（接受）和一小时（拒绝），并让元数据服务器缓慢、宕机、回答 500、返回乱码、HTML、被截断
或被篡改的文档，或什么都不返回。速率限制器不再把倒退的时钟当作负时间（它过去会按跳变的大小清空每个桶；生产环境的时钟
不会倒退，所以这是纵深防御）。
