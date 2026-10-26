---
title: "管理 API、健康检查和指标"
linkTitle: "管理 API"
weight: 70
description: "通过 authn-bridge 的 gRPC 管理 API 禁用人员或机构，以及它旁边的健康检查和指标端点。"
tags: [authn-bridge, 管理, grpc, 指标]
---

除非配置要求，否则两者都是关闭的，并且都绝不会出现在
公共监听器上。

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

该监听器来自 grpc-transports/control，与 go-fileshare 共用。套接字
不会被其他用户访问，即使在 bind 与 chmod 之间也不会，并且
绝不会从仍在运行的实例手中夺取。没有全部三个 TLS 文件的 TCP 会
被拒绝，环回地址也不例外，因为每个本地用户都可以访问 `127.0.0.1`：

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
```

用 `-tags nogrpc` 构建的二进制文件没有管理 API，并且会拒绝带有
`admin` 块的配置，而不是在没有它的情况下启动。

## 服务 {#the-service}

`bridge.admin.v1.AdminService`（`proto/bridge/admin/v1/admin.proto`），旁边是
`grpc.health.v1`，它在提供方就绪时报告 `SERVING`。

| | |
|---|---|
| `Status` | 版本、签发方、启动时间；联邦的元数据（IdP、可用数量、有效期至、上次刷新、上次错误）；内存中保存的内容 |
| `RefreshMetadata` | 立即获取联邦的元数据，并说明结果如何 |
| `ListIdPs` | 联邦的 IdP，与机构列表所显示的一致（`query`、`limit`，默认 100） |
| `ListClients` | 已配置的依赖方 |
| `RevokePerson` | 终止其刷新令牌族、由此获得的访问令牌、进行中的登录和设备授权，以及其应用密码，并吊销证书存储中为其保存的一切：SSH 和 X.509 证书（进入下一个 KRL 和 CRL）以及 WireGuard 密钥 |
| `DisablePerson`、`EnablePerson` | 在此处拒绝某人，包括登录时和每个令牌上，无论其机构怎么说，并吊销其所持有的内容；可选地设置 `until` 时间 |
| `DisableIdP`、`EnableIdP` | 对某一机构所担保的所有人做同样的事；元数据刷新不会解除它 |
| `ListDisabled` | 谁被禁用、原因、由谁禁用、从何时起、到何时为止 |

设置 `reflection = true`，针对测试提供方：

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

## 禁用 {#disabling}

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

`revoked` 统计每次调用所终止的内容（刷新令牌族、访问令牌、登录、
应用密码、证书）；这里没有任何有效内容。每个
改变了某些内容的调用都会记录日志，说明是谁发起的：套接字上对端的 `uid=`，
或 TLS 上客户端证书的 `cn=`：

```
disabled alice@univ-example.example (0 known identities) by uid=501 until enabled again: left the lab
revoked alice@univ-example.example: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
disabled IdP https://idp.univ-example.example/idp/shibboleth by uid=501 until 2026-11-27T08:00:00Z: compromised
revoked IdP https://idp.univ-example.example/idp/shibboleth: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
enabled alice@univ-example.example by uid=501
```

**人员是按其真实身份被禁用的。** 用户名的比较不区分大小写，
eppn、uid、mail 和 subject-id 都是如此，因此用
`"Alice@Univ-Example.example"` 发出的同一调用会解除为 `alice@univ-example.example`
设置的禁用（`{"wasDisabled": true}`）。该条目还会记录
以该名称为人所知的所有人的稳定身份，因此其 IdP 给出的另一种写法不会让
他们重新进入。不含 `@` 的名称也会作为 `sub` 进行匹配，用于其
IdP 不释放用户名的人员。

条目在吊销任何内容**之前**记录，因此与吊销竞争的授权
会遇到该条目。

**禁用保存在 `disabled_file` 中，没有它则会被拒绝。** 禁用到下一次
重启为止的人员，会被下一次部署放回来：

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
ERROR:
  Code: FailedPrecondition
  Message: disabling needs disabled_file in the configuration: without it, a restart would forget who is disabled
```

无法读取的文件会因同样的原因使提供方无法启动。被禁用的机构在
`Status`、`ListIdPs` 和
[`check`]({{< relref "/authn-bridge/configuration.md#check-before-a-restart" >}})中都算作不可用。

禁用在提供方之外产生的影响见
[吊销]({{< relref "/authn-bridge/revocation.md" >}})：证书使用 KRL 和
CRL，令牌使用 Shared Signals。在此处移除的应用密码，
会在 go-fileshare 下次读取其目录时失效；
请在 `DisablePerson` 之后调用其 `ReloadDirectory`，以使效果立即生效。

{{< callout type="warning" >}}
**`RevokePerson` 无法终止的内容**

已经发放的访问令牌是资源服务器自行检查的签名声明，
在那里直到过期之前都有效（默认一小时）。已经签发的
SSH 证书在其有效期内一直有效，除非服务器读取
KRL，这正是两者都很短的原因。
{{< /callout >}}

## 健康检查和指标 {#health-and-metrics}

来自 go-net-health/endpoint，与 go-fileshare 相同，位于 `metrics` 监听器上，该监听器
不得是公共监听器（使其成为公共监听器的配置会被拒绝）：

| | |
|---|---|
| `/healthz` | 进程能应答时即为正常 |
| `/readyz` | 联邦的元数据已加载且在其 `validUntil` 之内，并且没有等待写入状态数据库的吊销时即为就绪 |
| `/metrics` | Prometheus 文本，`bridge_*` 系列 |

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

按结果统计的登录计数器（`bridge_logins_total`）、按授权类型统计的令牌计数器
（`bridge_tokens_issued_total`）和应用密码计数器
（`bridge_app_passwords_total`）只有在统计到某些内容之后才会出现。**没有任何标签指名人员或机构**：哪些
大学的人员使用该服务，以及何时使用，不应由提供方来
公布。请在 `bridge_metadata_valid_until_timestamp_seconds` 所给出的
时间到达之前设置告警：过了这个时间，没有人能够登录。
