---
title: "它吊销什么，以及服务器如何得知"
linkTitle: "吊销"
weight: 60
description: "authn-bridge 为其吊销的证书发布的、带签名并标注日期的 KRL 和 CRL，以及覆盖任何列表都无法逐一指名之内容的 Shared Signals 发送方。"
tags: [authn-bridge, 吊销, krl, crl, 共享信号]
---

禁用人员或机构（[管理 API]({{< relref "/authn-bridge/admin.md" >}})）
会终止一切回到提供方的内容：刷新令牌、`/userinfo`、
新证书、应用密码。已经发放出去的内容
在别处凭密钥检查，有三种机制可以触及它：

| 凭据 | 收回方式 |
|---|---|
| 此 CA 签发的 SSH 证书 | **KRL**，`GET /ssh/krl`，其签名位于 `/ssh/krl.sig` |
| X.509 客户端证书 | **CRL**，`GET /x509/crl` |
| 访问令牌、opkssh 证书，以及服务器独立验证的任何内容 | **Shared Signals** `session-revoked` 事件 |

吊销是永久的。重新启用某人并不会让其
证书恢复；他们会得到新的证书。可以从中撤销吊销的列表，
就是能访问管理 API 的人可以编辑的列表。

## 列表 {#the-lists}

两者都按 go-authn/revocation 的协议签发，使它们可以经过
任何途径（镜像、普通 HTTP、文件）传递，并且仍然可以被读取它们的人
检查：

| | KRL | CRL |
|---|---|---|
| 格式 | OpenSSH `PROTOCOL.krl`，由 go-authn/krl 写出：`sshd` 的 `RevokedKeys` 和 `ssh-keygen -Q` 读取的格式 | DER，RFC 5280 |
| 签名 | 由 SSH CA 密钥生成的分离式 SSHSIG，命名空间 `krl@go-authn.github.io` | 由签发证书的 CA 签名 |
| 有效期至 | 其 `expires@go-authn.github.io` 扩展（sshd 会忽略它） | 其 `nextUpdate` |
| 排序依据 | 其 `krl_version`，然后是其生成日期 | 其 CRL Number，然后是 `thisUpdate` |

每个列表都声明在签发**一小时**之后不再有效。列表会被
保留并原样提供，直到过去一半时间，或直到有内容被吊销；
下一个请求随后会得到新的签发版本。新的签发版本的日期绝不早于
它所取代的版本，即使时钟回拨也是如此，因为读取方会把同一版本的
较早签发版本当作回滚而拒绝。CRL Number 在每次签发时递增。

来自测试提供方、没有吊销任何内容的 KRL：

```
$ curl -s -D - -o var/bridge.krl http://127.0.0.1:28473/ssh/krl
HTTP/1.1 200 OK
Cache-Control: max-age=60
Content-Type: application/octet-stream
Etag: "c543d4dd9acedf716b34ea3af912a62f"
Date: Mon, 26 Oct 2026 11:21:59 GMT
Content-Length: 130

$ ssh-keygen -Q -l -f var/bridge.krl
# KRL version 0
# Generated at 20261026T122159
# Comment: go-authn/bridge http://127.0.0.1:28473
```

**ETag 是内容的 ETag。** 读取方用 `If-None-Match` 轮询，只要其持有的签发版本
仍是所提供的那个，就会得到
`304`；由于内容至少每半小时就会改变，轮询的读取方
永远不会把副本保留到过期之后：

```
$ curl -s -o /dev/null -H 'If-None-Match: "d2ab8a48f397a1f55bf3e8e513a4dea9"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl
304
```

**签名使用 `If-Match` 获取**，对应列表的 ETag。期间
重新签发的列表会答复 `412`，而不是给出与它
不匹配的签名：

```
$ curl -s -o var/bridge.krl.sig -H 'If-Match: "d2ab8a48f397a1f55bf3e8e513a4dea9"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
200
$ curl -s -o /dev/null -H 'If-Match: "stale"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
412
```

`ssh-keygen` 检查签名，并拒绝任何其他命名空间中的签名：

```
$ ssh-keygen -Y verify -f allowed -I bridge -n krl@go-authn.github.io -s bridge.krl.sig < bridge.krl
Good "krl@go-authn.github.io" signature for bridge with ED25519 key SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

其中 `allowed` 是这一行：
`bridge namespaces="krl@go-authn.github.io" <the CA key from /ssh/config>`。

十五秒之后签发的 CRL：

```
$ openssl crl -inform DER -in var/bridge.crl -noout -text
Certificate Revocation List (CRL):
    Version 2 (0x1)
    Signature Algorithm: ecdsa-with-SHA256
    Issuer: CN=go-authn bridge NFS client CA
    Last Update: Oct 26 11:22:15 2026 GMT
    Next Update: Oct 26 12:22:15 2026 GMT
    CRL extensions:
        X509v3 Authority Key Identifier: 
            AE:A8:A1:10:13:A3:B3:EA:FD:73:42:E2:71:56:D2:7D:DF:AA:4D:2C
        X509v3 CRL Number: 
            1793013735127
No Revoked Certificates.
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:44:02:20:79:e1:1f:d6:ae:86:01:01:41:d3:b2:2e:7d:20:
        13:3c:12:6c:7a:ee:3e:e9:e0:6f:33:28:af:ba:26:a4:06:5c:
        02:20:4a:b3:14:47:1c:23:14:f9:96:96:f0:78:40:28:2d:bd:
        c8:f3:37:75:24:fc:56:50:ba:3d:58:95:4e:b2:d7:dc
```

证书会一直留在列表中直到过期：过期的证书
在各处都会被拒绝，无需列出。

### 谁读取它们 {#who-reads-them}

- 普通的 `sshd`，或 nginx 和其他 TLS 服务器：
  [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})获取这些列表，
  只保留通过验证的列表，将它们写到服务器读取的位置，并在
  列表过期时对 sshd 故障即拒绝。
- [go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)
  自行获取并验证它们，并且在没有当前有效列表时拒绝提供方的
  证书。

## 共享信号 {#shared-signals}

访问令牌或 opkssh 证书是在使用它们的地方检查的，任何
列表都无法逐一指名。因此提供方是 OpenID Shared Signals 发送方：在
`DisablePerson`、`RevokePerson` 和 `DisableIdP` 时，它会为每个提出请求的接收方排入一个 CAEP
**`session-revoked`** 事件（在事件时间之前签发给该主体的一切
都作废）。

```hcl
state { ... }            # required: a queue a restart empties loses revocations
ssf {}                   # event_retention = "192h" by default

client "fileshare-ssf" { # a receiver: client credentials, scope ssf
  secret_file  = "/etc/authn-bridge/fileshare-ssf.secret"
  ssf_receiver = true
  audience     = ["fileshare"]
}
```

```
$ curl -s http://127.0.0.1:28473/.well-known/ssf-configuration | jq .
{
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "delivery_methods_supported": [
    "urn:ietf:rfc:8936"
  ],
  "configuration_endpoint": "http://127.0.0.1:28473/ssf/streams",
  "status_endpoint": "http://127.0.0.1:28473/ssf/streams/status",
  "add_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:add",
  "remove_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:remove",
  "verification_endpoint": "http://127.0.0.1:28473/ssf/streams/verify",
  "spec_version": "1_0",
  "authorization_schemes": [
    {
      "spec_urn": "urn:ietf:rfc:6749"
    }
  ]
}
```

- **仅支持轮询投递**（RFC 8936）：由接收方发起询问；这里不会主动
  向外连接。
- 接收方使用来自 **client credentials** 授权的访问令牌进行认证，
  适用于带有密钥的 `ssf_receiver` 客户端，scope 为 `ssf`。
  它只能看到自己的流，最多十个。
- 事件是 SET（RFC 8417），用 ID 令牌密钥签名，没有 `exp` 也没有
  `sub`。主体默认是**账户**，`acct:<username>`：`sub`
  可能是成对的，每个客户端一个。配置了
  `ssf_subject_format = "iss_sub"` 的接收方则得到签发方和公开的 `sub`。
- 禁用一个机构，会为提供方在其中留有记录的每个人员各产生一个事件，
  外加一个其主体为**租户**（即机构的实体 ID）的事件，
  附带其 scope，用于覆盖提供方已经遗忘的人员。
- 流和未送达的事件保存在 `state` 数据库中，直到被
  确认或 `event_retention` 过期。接收方报告出错的事件
  会被再次发出，最多十次。

没有 `state` 块的 SSF 块会被拒绝：

```
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```
