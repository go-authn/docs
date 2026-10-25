---
title: "管理 API、ヘルス、メトリクス"
linkTitle: "管理 API"
weight: 70
description: "authn-bridge の gRPC 管理 API による人や機関の無効化と、その隣にあるヘルスおよびメトリクスのエンドポイント。"
tags: [authn-bridge, 管理, grpc, メトリクス]
---

どちらも、設定が求めない限りオフであり、公開リスナーでは決して有効になりません。

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

リスナーは grpc-transports/control のもので、go-fileshare と共有しています。ソケットは、
bind から chmod までの間も含めて、他のユーザーには決して到達できず、まだ動いているインスタンス
から奪われることもありません。三つの TLS ファイルがそろっていない TCP は、ループバックを含めて
拒否されます。ローカルのすべてのユーザーが `127.0.0.1` に到達できるためです。

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
```

`-tags nogrpc` でビルドしたバイナリには管理 API がなく、`admin` ブロックのある設定は、それなしで
起動せずに拒否されます。

## サービス {#the-service}

`bridge.admin.v1.AdminService` (`proto/bridge/admin/v1/admin.proto`)。その隣に
`grpc.health.v1` があり、プロバイダーが準備できている間 `SERVING` を報告します。

| | |
|---|---|
| `Status` | バージョン、発行者、開始時刻。フェデレーションのメタデータ (IdP、使用可能数、有効期限、最後の更新、最後のエラー)。メモリ上に保持されているもの |
| `RefreshMetadata` | フェデレーションのメタデータを今すぐ取得し、結果を報告する |
| `ListIdPs` | フェデレーションの IdP を、機関の一覧が示すとおりに (`query`、`limit`、既定は 100) |
| `ListClients` | 設定されたリライングパーティー |
| `RevokePerson` | その人のリフレッシュトークンファミリー、それが得たアクセストークン、進行中のログインとデバイスグラント、アプリケーションパスワードを終了し、証明書ストアがその人について保持するすべてを失効させる: SSH と X.509 の証明書 (次の KRL と CRL へ) と WireGuard 鍵 |
| `DisablePerson`、`EnablePerson` | その人の所属機関が何と言おうと、ログイン時とすべてのトークンでここでの利用を拒否し、保持しているものを失効させる。任意で `until` により時刻まで |
| `DisableIdP`、`EnableIdP` | ある一つの機関が保証する全員に対して同じことを行う。メタデータの更新では解除されない |
| `ListDisabled` | 誰が無効化されているか、理由、実施者、開始時刻、期限 |

`reflection = true` で、テスト用プロバイダーに対して:

```
$ grpcurl -plaintext -unix $PWD/run/admin.sock bridge.admin.v1.AdminService/Status
{
  "version": "v0.23.3",
  "issuer": "http://127.0.0.1:28473",
  "started": "2026-10-25T18:44:30.210885Z",
  "federation": {
    "metadataUrl": "file:///tmp/authn/fed/metadata.xml",
    "idps": 1,
    "usable": 1,
    "validUntil": "2026-11-01T18:43:40Z",
    "lastRefresh": "2026-10-25T18:44:30.211975Z"
  },
  "counts": {}
}
```

## 無効化 {#disabling}

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example","reason":"left the lab"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
{
  "disabled": {
    "username": "alice@univ-example.example",
    "reason": "left the lab",
    "by": "uid=501",
    "since": "2026-10-11T09:48:39.136975Z"
  },
  "revoked": {}
}
$ grpcurl -plaintext -unix -d '{"entity_id":"https://idp.univ-example.example/idp/shibboleth","reason":"compromised","until":"2026-10-12T08:00:00Z"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisableIdP
{
  "disabled": {
    "entityId": "https://idp.univ-example.example/idp/shibboleth",
    "reason": "compromised",
    "by": "uid=501",
    "since": "2026-10-11T09:48:39.192047Z",
    "until": "2026-10-12T08:00:00Z"
  },
  "revoked": {}
}
```

`revoked` は各呼び出しが終了させたもの (リフレッシュファミリー、アクセストークン、ログイン、
アプリケーションパスワード、証明書) を数えます。ここでは有効なものは何もありませんでした。
何かを変更するすべての呼び出しは、実行者とともにログに記録されます。ソケットでは相手の `uid=`、
TLS ではクライアント証明書の `cn=` です。

```
disabled alice@univ-example.example (0 known identities) by uid=501 until enabled again: left the lab
revoked alice@univ-example.example: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
disabled IdP https://idp.univ-example.example/idp/shibboleth by uid=501 until 2026-10-12T08:00:00Z: compromised
revoked IdP https://idp.univ-example.example/idp/shibboleth: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
enabled alice@univ-example.example by uid=501
```

**人は、その人が誰であるかによって無効化されます。** ユーザー名は、eppn、uid、mail、subject-id
がすべてそうであるように、大文字小文字を区別せずに比較されるので、`"Alice@Univ-Example.example"`
での同じ呼び出しは、`alice@univ-example.example` に設定されたものを解除します
(`{"wasDisabled": true}`)。エントリは、その名前で知られているすべての人の安定した ID も記録するので、
IdP からの別の綴りで再び入れることはできません。`@` のない名前は `sub` としても照合され、
IdP がユーザー名を出さない人に備えています。

エントリは何かを失効させる**前に**記録されるので、失効と競合するグラントはそのエントリに
突き当たります。

**無効化は `disabled_file` に保持され、それがなければ拒否されます。** 次の再起動まで無効化
された人は、次のデプロイで再び入れてしまうからです。

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
ERROR:
  Code: FailedPrecondition
  Message: disabling needs disabled_file in the configuration: without it, a restart would forget who is disabled
```

読めないファイルがあると、同じ理由でプロバイダーは起動しません。無効化された機関は、`Status`、
`ListIdPs`、[`check`]({{< relref "/authn-bridge/configuration.md#check-before-a-restart" >}})で
使用不可として数えられます。

無効化がプロバイダーの外に及ぶ範囲は[失効]({{< relref "/authn-bridge/revocation.md" >}})に
あります。証明書については KRL と CRL、トークンについては Shared Signals です。ここで削除された
アプリケーションパスワードは、go-fileshare が次にディレクトリを読み込むときに使えなくなります。
すぐに効果を出すには、`DisablePerson` の後でその `ReloadDirectory` を呼んでください。

{{< callout type="warning" >}}
**`RevokePerson` が終了できないもの**

すでに渡されたアクセストークンは、リソースサーバーが独自に検証する署名付きの表明であり、
そこでは期限 (既定では一時間) が切れるまで有効です。すでに発行された SSH 証明書は、サーバーが
KRL を読まない限り、その有効期間いっぱい有効です。両方が短命なのはそのためです。
{{< /callout >}}

## ヘルスとメトリクス {#health-and-metrics}

go-net-health/endpoint のもので、go-fileshare と同様に `metrics` リスナーにあります。これは
公開リスナーであってはなりません (そうなる設定は拒否されます)。

| | |
|---|---|
| `/healthz` | プロセスが応答している間は up |
| `/readyz` | フェデレーションのメタデータが読み込まれ、その `validUntil` 以内にあり、状態データベースに届くのを待っている失効がない間は ready |
| `/metrics` | Prometheus テキスト形式の `bridge_*` ファミリー |

```
$ curl -s http://127.0.0.1:28475/metrics | grep "^bridge_"
bridge_build_info{version="v0.23.3",goversion="go1.27.3",revision="b04769c43c24f684df9e0b5a0d1cb6997ee90d95"} 1
bridge_start_time_seconds 1792953870
bridge_ready 1
bridge_metadata_valid_until_timestamp_seconds 1793558620
bridge_metadata_idps 1
bridge_metadata_last_refresh_timestamp_seconds 1792953870
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

結果別のログインのカウンター (`bridge_logins_total`)、グラント別のトークンのカウンター
(`bridge_tokens_issued_total`)、アプリケーションパスワードのカウンター
(`bridge_app_passwords_total`) は、何かを数えて初めて現れます。**どのラベルも人や機関を指しません。**
どの大学の人々がいつサービスを使うかは、プロバイダーが公開すべきことではないからです。
`bridge_metadata_valid_until_timestamp_seconds` が示す時刻に達する前にアラートを設定して
ください。それを過ぎると、誰もログインできなくなります。
