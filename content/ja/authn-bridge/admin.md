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

`saml { idps }` から IdP を外すと、`DisableIdP` と同じように、その IdP が保証していたものが終わります（v0.23.7 から）。
新しいログインは拒否され、その IdP を経由した人のあらゆる許可も、次に使われたときに
`institution not configured` で拒否されます。対象はリフレッシュトークン（再起動をまたいでも）、
アプリケーションパスワード、SSH 証明書の要求です。IdP を戻せばそれらは再び動作し、失効させる必要はありません。

`reflection = true` で、テスト用プロバイダーに対して:

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

## 無効化 {#disabling}

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

`revoked` は各呼び出しが終了させたもの (リフレッシュファミリー、アクセストークン、ログイン、
アプリケーションパスワード、証明書) を数えます。ここでは有効なものは何もありませんでした。
何かを変更するすべての呼び出しは、実行者とともにログに記録されます。ソケットでは相手の `uid=`、
TLS ではクライアント証明書の `cn=` です。

```
disabled alice@univ-example.example (0 known identities) by uid=501 until enabled again: left the lab
revoked alice@univ-example.example: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
disabled IdP https://idp.univ-example.example/idp/shibboleth by uid=501 until 2026-11-27T08:00:00Z: compromised
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

**名前の畳み込みは ASCII 文字だけです** (v0.23.8 以降)。無効化リスト、証明書のプリンシパル、subject-id は、ユーザー名を go-authn/oidc の `ASCIILower` で比較するので、ケルビン記号 (U+212A) は "k" ではありません。`kate` とケルビン記号を使った綴りは別の 2 人で、無効化エントリも証明書のプリンシパルも 2 つになります。一方を無効化しても、もう一方は無効化されません。

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

## パスキー削除の通知 {#passkey-removal-notices}

[`mail` ブロック]({{< relref "/authn-bridge/configuration.md#mail" >}}) (v0.32.0 以降) があると、
ローカルアカウントは、パスキーの削除が要求または取り消されたときに、自分のアドレスで知らされます。
鍵を一つ手に入れた泥棒が、所有者の削除を黙って取り消すことはできません。対象は**ローカルアカウント
のみ**で、通知はアカウントごとに `window` (既定 10 分) あたり 1 通です。その間に届いたイベントは
一つのダイジェストにまとめられます。運用者に何が見えるかは、イベントによって変わります:

- **通知を送れない削除リクエストは保留のままです。** 遅延が終わっても実行されません。ブリッジは
  (5 回、間隔を延ばしながら) 再試行し、その後に `GAVE UP` を大きくログに出します。再起動すると
  再開され、次のイベントでも再開されます。その間も、鍵はこれまでどおり使えます。レコードには、
  通知が配達されるまで `notice_pending` が付きます。
- **取り消しは、そのメールが失敗しても適用されます。** 失敗はログ (`mailing <login> failed`) に
  記録され、アカウントのページに、通知を送れなかったと表示されます。
- **使えるアドレスのないアカウント**は妨げられません。その削除は `mail` ブロックがないときと同じ
  ように進み、ログには `<login> has no usable mail address ... nobody is told` と出て、アカウントの
  ページもそう表示します。

`mail` ブロックがなければ、何も変わりません。

## ジャーナルとローカルアカウント {#journal-and-local-accounts}

v0.37.0 以降、サインインに成功するたびにジャーナルへ 1 行が残ります。どの行にも
秘密は含まれません。コード、トークン、アサーション、メールアドレス、氏名、
グループは出力されません。

```text
login: <username> via <idp entityID> for <client_id> from <address>
login: <login> via <issuer>/local with passkey <8 hex> for <client_id> from <address>
account: <username> confirmed through <idp entityID> from <address>
account: audit: <login> stepup <16 hex> from <address>
token: authorization_code issued to <client_id> for <username>
token: refresh_token issued to <client_id> for <username>
```

最初の 2 行は認可エンドポイントでのログインで、機関経由とローカルのパスキーによる
ものです(`<8 hex>` は `local: <login> enrolled a passkey (<8 hex>)` が出力する
パスキーの ID です)。次の 2 行はアカウントページへのサインインで、機関経由と
パスキーによるものです。最後の 2 行はクライアントに渡されたトークンです。

アカウントのディレクトリが `root:authn-bridge` 0750、ファイルが 0640(文書化された
構成)の場合、`authn-bridge local-account …` は **root** で実行してください。
このコマンドは隣に一時ファイルを作ってファイルを置き換えるため、`authn-bridge`
として実行すると `open /etc/authn-bridge-local/.accounts-NNN: permission denied`
で失敗します。ファイルの所有者とモードは保たれます。SSH 経由では、
`ssh host sudo authn-bridge local-account … --name "Two words"` にもう一段の
引用符が必要です(`--name '"Two words"'`)。ssh は引数を 1 つの文字列に連結し、
リモート側のシェルがそれを再び分割するためです。

## クライアントが受け付けるアカウント {#client-accounts}

v0.38.0 から、`client` ブロックは 1 種類の人だけを受け付けるように設定できます。

```hcl
client "forgejo" {
  secret_file   = "/etc/authn-bridge/forgejo.secret"
  redirect_uris = ["https://git.example.org/user/oauth2/bridge/callback"]
  accounts      = ["local"]   # "local", "federated", or both (the default)
}
```

`accounts = ["local"]` は、ハードウェアキーを求めるサービス向けです。SAML の
機関に属する人は拒否されます。この規則は、ログインが提示される場所だけでなく、
権限が付与または使用されるすべての場所で守られます。認可エンドポイントは、
クライアントが受け付ける唯一の経路へ人を案内します(ローカル専用クライアントへの
`prompt=none` は `login_required` を返します)。フェデレーションの段階、パスキーの段階、
ログインの終了は、それぞれ他方の種類のログインを拒否します。コードの交換、更新、
デバイスのポーリングも他方の種類の人を拒否するため、制限が書かれる前に得られた
権限は制限とともに止まります。応答は `access_denied` で、ログイン中はクライアントの
リダイレクト URI に、その後はトークンエンドポイントで返されます。
`authn-bridge check` はクライアントの行に制限を表示し、`local` には `local` ブロックが
必要で、`bridge_logins_total{result="wrong_account_kind"}` が拒否を数えます。
ジャーナルには理由が残ります。

```text
login: <username> via <idp entityID> refused for <client_id>: this client takes local accounts only
token: account kind not accepted by this client: <why> (<username> via <idp> for <client_id>)
```

既知の制限: 証明書エンドポイント(SSH、X.509、Kerberos、WireGuard)は特定の
クライアントに結び付いていないため、`accounts` は適用されません。

## Web から招待する管理者 {#web-invitations}

v0.39.0 から、管理者はホストのシェルなしで `/account/invite` からローカル
アカウントを招待できます(ログイン名、メールアドレス、任意の名前)。招待は
コマンドラインのものと同じで、リンクは招待された人へのメールでのみ送られます。
管理者は `local` ブロックで、使用できる認証器のモデルとともに指定します。

```hcl
local {
  admins        = ["alice"]
  admin_aaguids = ["9dd8d593-2213-438a-97f8-d6b813d51c27"]
  mds_dir       = "/var/lib/authn-bridge/mds"
  admin_min_certification = "L2"   # optional
}
```

このページには `mail` ブロック、3 分以内のユーザー検証付きアサーション、CSRF
トークンが必要で、管理者 1 人あたり 1 時間に 10 アカウントまで招待できます。
管理者のパスキーのモデルは、申告ではなく**証明**されていなければなりません。
登録時にブラウザへ direct attestation を求め、go-authn/webauthn v0.5.0 が検証し
(`x5c` チェーンを持つ `packed` ステートメントで、その証明書が認証器の AAGUID と
等しい `id-fido-gen-ce-aaguid` 拡張を持つこと。`self` と `none` は検証されますが
モデルを証明せず、この拡張のない証明書も同様です)、そのモデルを go-authn/fido v0.16.0 の `mds` により FIDO
MDS3 メタデータと照合します。そこで初めて bridge はモデルを記録し、ページはそれ
以外を読みません。後からメタデータで失効または侵害とされたモデルは、ページを
開けなくなります。モデルが証明されないまま登録された鍵でもサインインはできます
が、何も開きません。

**最低限の認定レベル。** `admin_min_certification`（省略可。`"L1"`、`"L1plus"`、
`"L2"`、`"L2plus"`、`"L3"`、`"L3plus"` のいずれか。それ以外の値は設定エラーで、
`admins` がなければ拒否されます）は、管理者のパスキーのモデルが持つべき FIDO
認定レベルの下限で、同じ MDS3 メタデータから読み取ります。順序は仕様のもの
（MDS 3.1 §3.1.4.1）で、L1 < L1plus < L2 < L2plus < L3 < L3plus です。レベルは
モデルの*現在の*レベル、つまり有効な最新の `FIDO_CERTIFIED_Lx` ステータス
レポート（§3.1.3）です。そのようなレポートがないモデル（従来の
`FIDO_CERTIFIED` はどのレベルにも数えません）は、どの下限も満たしません。失効
や侵害のステータスと同様に、登録時**とページを開くたび**に確認されます。後で
下限を下回る格下げや失効があったモデルでも、ログインはできますが、管理者
ページは開けなくなります。未設定ならレベルは要求されません。authn-bridge
v0.41.0 (go-authn/fido v0.17.0) から利用できます。

メタデータは `mds_dir` に保存されます。省略可能で、既定値は
`/var/lib/authn-bridge/mds`、絶対パスでなければならず、`admins` がなければ拒否
されます。取得するのはバックグラウンドの goroutine で、リクエストが取得する
ことはありません。ホストには次が必要です。

- サービスが書き込めるディレクトリ(`mds_dir`。既定以外のパスはユニットの
  `ReadWritePaths=` に含めること)
- `mds3.fidoalliance.org` への外向き HTTPS と、その証明書の CRL 配布ポイントへの
  外向きの平文 HTTP
- 正しい時計

サービスはメタデータなしで起動して再試行します。取得されるまで管理者の鍵は
証明されず、ページは拒否します。

**管理者の鍵を登録し直す。** v0.39.0 より前に登録された鍵には検証済みの
アテステーションがありません。各管理者について、既存の鍵でサインインし、
`/account` を開き、鍵で確認し、許可された認証器(たとえば YubiKey Bio)で
パスキーを追加します。ブラウザが求める製造元とモデルの共有を承諾してください。
応答に `attested: true` と出れば、`/account/invite` が使えます。その後、古い鍵を
削除します。

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

結果別のログインのカウンター (`bridge_logins_total`)、グラント別のトークンのカウンター
(`bridge_tokens_issued_total`)、アプリケーションパスワードのカウンター
(`bridge_app_passwords_total`) は、何かを数えて初めて現れます。**どのラベルも人や機関を指しません。**
どの大学の人々がいつサービスを使うかは、プロバイダーが公開すべきことではないからです。
`bridge_metadata_valid_until_timestamp_seconds` が示す時刻に達する前にアラートを設定して
ください。それを過ぎると、誰もログインできなくなります。
