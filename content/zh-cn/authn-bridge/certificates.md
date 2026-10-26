---
title: "证书"
linkTitle: "证书"
weight: 50
description: "authn-bridge 签发的 SSH 用户证书、其 EuroHPC 联邦平台配置档，以及它为基于 TLS 的 NFS 签发的 X.509 客户端证书。"
tags: [authn-bridge, ssh, x509, eurohpc]
---

登录过的人员可以让其 SSH 公钥获得认证，或获得签发的 X.509 客户端
证书，有效期为几个小时。信任提供方 CA 的服务器会让
他们进入，而无需在那里编辑任何账户文件。每个证书都在**发放之前
记录在 `certificates_file` 中**：无法记录的证书不会被签发，因为它永远
无法吊销，而被吊销的证书则发布在
[KRL 和 CRL]({{< relref "/authn-bridge/revocation.md" >}}) 中。

## SSH 证书 {#ssh-certificates}

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

`authn-bridge ssh-cert --issuer https://login.example.org --client sftp` 用代码
登录，用带有 `ssh` scope 的令牌将 `~/.ssh/id_ed25519.pub`（或 `--key`）发送到
`/ssh/certificate`，并在其旁边写入
`<key>-cert.pub`，`ssh` 和 `sftp` 会在那里找到它。

CA 密钥必须是 Ed25519：除非另行指定，RSA CA 密钥会使用 SHA-1 签名，
而 OpenSSH 自 8.8 起默认拒绝这一点。

**证书声明了什么。**

- **恰好一个 principal**，即人员的 `preferred_username`，除非
  客户端的配置档指定了另一个声明。没有 principal 的证书对
  *任何*用户都有效（PROTOCOL.certkeys），因此没有用户名的人员得不到证书。包含
  逗号、空格、引号、反斜杠或控制字符的名称会被
  拒绝（`403`）：`sshd` 把 `principals="a,b"` 和 `AuthorizedPrincipalsFile`
  条目当作列表读取，因此一个这样的名称就成了两个。
- **Key ID** `<principal> sub=<sub> jti=<token id>`：即 `sshd` 所记录的内容。
- 默认**没有 `permit-*` 扩展**。SFTP 不需要任何扩展，而
  不允许 pty、转发和 rc 文件的证书，只授予文件访问权限，
  别无其他。
- **人员的组**放在 `groups@go-authn.org` 扩展中，每行一个，
  当令牌携带组时。OpenSSH 会忽略它；它是经过签名的，因此按组授权的
  服务器可以信任它。
- **有效期**从五分钟前（以应对时钟不一致）开始，到从现在起
  `validity` 之后为止，或到 IdP 会话结束为止，以较早者为准。
- **密钥**必须是 Ed25519、ECDSA P-256/384/521、安全密钥（`sk-`），或
  至少 2048 位的 RSA。证书不能作为密钥提交。

## EuroHPC SSH CA 配置档 {#the-eurohpc-ssh-ca-profile}

EuroHPC 联邦平台的 SSH CA（GÉANT / MyAccessID）签发有效期一小时的
Ed25519 证书，其中有一个在整个联邦内指称该人员的 principal，
以及 GÉANT 的 `ssh-domain-grant@core.aai.geant.org` 扩展中证书所面向的主机。
客户端可以让其证书按这种形式签发。每个键都是按客户端设置且可选的；
没有设置任何键的客户端得到的是上面那种证书。

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

| 键 | |
|---|---|
| `ssh_principal_claim` | `preferred_username`、`sub`、`voperson_id` 或 `eduperson_principal_name`。后两者由 `eduperson` scope 释放，令牌必须持有该 scope（`authn-bridge ssh-cert --scope eduperson`）；否则，或者当 IdP 没有释放这样的属性时，答复为 `403` 并说明是哪一个 |
| `ssh_extensions` | 取自 `permit-pty`、`permit-user-rc`、`permit-port-forwarding`、`permit-agent-forwarding`、`permit-X11-forwarding` |
| `ssh_source_address` | 地址或 CIDR 前缀，以规范形式写入 `source-address` |
| `ssh_validity` | 对此客户端，绝不长于 `ssh_ca` 的 `validity`（相等是可以接受的） |
| `ssh_domain_grants` | 域模式，由 [go-authn/sshcert]({{< relref "/sshcert/_index.md" >}}) 的 `ValidatePattern` 检查，并由其 `EncodeDomainGrant` 编码 |

### 配置档拒绝什么 {#what-the-profile-refuses}

以下每一项都在启动时由 `authn-bridge check` 给出：

```
authn-bridge: client "efp": ssh_validity = 24h0m0s: longer than the ssh_ca validity, 12h0m0s
authn-bridge: client "efp": ssh_extensions: "no-touch-required" is not one of permit-X11-forwarding, permit-agent-forwarding, permit-port-forwarding, permit-pty, permit-user-rc
authn-bridge: client "src": ssh_source_address: "192.0.2.1/24" has bits set under its mask: 192.0.2.0/24?
authn-bridge: client "x": ssh_principal_claim, ssh_extensions, ssh_source_address, ssh_validity and ssh_domain_grants shape SSH certificates: they need ssh_certificates = true
```

不提供 `no-touch-required`：它会免除人员**自己的**
安全密钥的用户在场测试，而这不是提供方可以为
某个客户端的所有人随意放弃的。

域授权首先要符合规范的语法，然后要符合本提供方
自己的策略：小写、至少两个标签，且通配符只能位于
可注册域之下。最后一个通配符右侧保持固定的部分不得
是公共后缀（Public Suffix List）：`*.ac.uk` 会授权其下的
每一个机构。

```
authn-bridge: client "efp": ssh_domain_grants: "*.ac.uk": a wildcard over the public suffix "ac.uk" grants every domain under it
authn-bridge: client "efp": ssh_domain_grants: "Login.hpc.example.org": written in lower case, as hosting entities' domains are compared
authn-bridge: client "efp": ssh_domain_grants: "login.hpc.*": sshcert: invalid domain pattern: pattern "login.hpc.*" has a wildcard in its rightmost label
```

### 在站点上信任它 {#trusting-it-from-a-site}

`GET /ssh/config` 以 EFP 发布自己密钥的形式发布 CA 密钥，因此
站点只需用本提供方的 URL 遵循 EFP 的信任说明：

```
$ curl -s http://127.0.0.1:28473/ssh/config
{"PublicKey":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPnW/W/MeVAMgt4fciWbbiJ/BS4vXURfwoc7K5cET1Ma"}
```

```sh
curl -s https://login.example.org/ssh/config | jq -r '.PublicKey' > /etc/ssh/bridge-ssh-ca.pub
echo "TrustedUserCAKeys /etc/ssh/bridge-ssh-ca.pub" >> /etc/ssh/sshd_config
```

sshd 会忽略域授权。站点通过
`AuthorizedPrincipalsCommand` 按其过滤：[sshcert-authorize]({{< relref "/sshcert/authorize.md" >}})，
它会拒绝授权未指明本主机的证书，以及完全没有
授权的证书。CA 不在 OpenID 发现文档中：没有任何 OpenID Connect
元数据会指称 SSH CA。

与 EFP 自己的 CA 仍然不同的是：在 `ssh_principal_claim =
"voperson_id"`（如上）时，principal 是该人员所属机构释放的 `subject-id`，
为小写，而不是 MyAccessID 标识符；令牌携带组时才会有组
扩展；并且**存在 KRL**，即
`GET /ssh/krl`，列出在此处被禁用的人员的证书。

## 用于基于 TLS 的 NFS 的 X.509 客户端证书 {#x509-client-certificates-for-nfs-over-tls}

基于 TLS 的 NFS（RFC 9289）可以用证书来指称客户端。

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

`authn-bridge nfs-cert --issuer ... --client nfs` 在人员的机器上生成 P-256 密钥，
用带有 `nfs` scope 的令牌将证书请求发送到 `/x509/cert`，
并写入证书和密钥。CA 密钥必须是
P-256，其证书必须是可以签署证书和 CRL 的 CA。

**证书声明了什么。** 请求的主体和扩展会被
忽略：被认证的是令牌所属的人员，而不是他们所请求的内容。

- 人员，`user@domain`，作为**一个** subjectAltName `otherName`
  `1.3.6.1.4.1.2238.1.1.1`，保存一个 UTF8String，FreeBSD 的
  `rpc.tlsservd -u` 会从那里读取它。不含 `@` 的用户名，或不足三个字节的用户名，
  会被拒绝。
- 每个组作为紧挨着它的一个 URI 名称：
  `tag:go-authn.github.io,2026:group:<the group, percent-encoded>`。
- CN 是用户名；超过 64 个字符时，主体为空，
  且 subjectAltName 为关键（RFC 5280）。
- 仅用于客户端认证，并带有 CRL 分发点：
  `<issuer>/x509/crl`。
- 有效期从五分钟前开始，到 `validity`、IdP 会话或 CA 自身
  证书的结束时间为止，以最先结束者为准。
- P-256 或 RSA（2048 位及以上）密钥，以及由它签名的请求。

{{< callout type="warning" >}}
**证书指称的是机器，而不是机器的使用者**

RFC 9289：服务器“cannot utilize the remote TLS peer identity to
authenticate RPC users”。Linux 为每个挂载设置客户端证书，因此
使用该挂载的每个人都是它所指称的那个人。这适用于
由一个人使用的机器，`authn-bridge nfs-cert` 也会这样提示。
{{< /callout >}}

## 在禁用期间保持打开的证书请求 {#a-certificate-request-held-open-across-a-disabling}

令牌在请求开始时检查，请求体在之后读取，
速度取决于客户端发送的快慢。因此证书先被记录，然后
再次检查令牌和人员：如果在此期间人员被禁用，或
令牌被吊销，刚刚记录的证书会被吊销，答复为
`401`。要么吊销看到了该证书，要么该证书
看到了吊销。
