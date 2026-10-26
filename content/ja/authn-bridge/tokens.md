---
title: "トークン、パスワード、鍵"
linkTitle: "トークン"
weight: 40
description: "アプリケーションが authn-bridge から得るもの: ID トークンとアクセストークン、デバイスグラント、SMB と S3 のためのアプリケーションパスワード、そして WireGuard 鍵。"
tags: [authn-bridge, oidc, トークン, wireguard]
---

ここでのすべての認証情報は、その人の所属機関での同じログインから始まります。違うのは、その
認証情報が誰のためのものか、そしてどう取り消されるかです。証明書は
[専用のページ]({{< relref "/authn-bridge/certificates.md" >}})にあります。

## プロバイダーが公開するもの {#what-the-provider-publishes}

```
$ curl -s http://127.0.0.1:28473/.well-known/openid-configuration | jq .
{
  "authorization_endpoint": "http://127.0.0.1:28473/authorize",
  "authorization_response_iss_parameter_supported": true,
  "claims_parameter_supported": false,
  "claims_supported": [
    "sub",
    "iss",
    "aud",
    "exp",
    "iat",
    "auth_time",
    "nonce",
    "acr",
    "name",
    "given_name",
    "family_name",
    "preferred_username",
    "email",
    "groups",
    "eduperson_principal_name",
    "eduperson_scoped_affiliation",
    "eduperson_entitlement",
    "entitlements",
    "eduperson_assurance",
    "eduperson_orcid",
    "schac_home_organization",
    "voperson_id"
  ],
  "code_challenge_methods_supported": [
    "S256"
  ],
  "device_authorization_endpoint": "http://127.0.0.1:28473/device_authorization",
  "grant_types_supported": [
    "authorization_code",
    "refresh_token",
    "urn:ietf:params:oauth:grant-type:device_code"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ],
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "request_parameter_supported": false,
  "request_uri_parameter_supported": false,
  "response_modes_supported": [
    "query"
  ],
  "response_types_supported": [
    "code"
  ],
  "scopes_supported": [
    "openid",
    "profile",
    "email",
    "eduperson",
    "groups"
  ],
  "subject_types_supported": [
    "public",
    "pairwise"
  ],
  "token_endpoint": "http://127.0.0.1:28473/token",
  "token_endpoint_auth_methods_supported": [
    "client_secret_basic",
    "client_secret_post",
    "none"
  ],
  "userinfo_endpoint": "http://127.0.0.1:28473/userinfo"
}
```

認可コードフローで、**すべてのクライアントに PKCE S256 が必須**です。`code_challenge_method` の
ないリクエストは、S256 として読まれずに拒否されます。RFC 7636 では `plain` が既定だからです。
`pkce = "or_nonce"` と設定された機密クライアントは、代わりに OpenID の `nonce` を送れます。

## ID トークン {#the-id-token}

クライアントのため、そしてログインについてのもので、人についてのものではありません。RS256、
`aud` はクライアント ID、`sub`、`auth_time`、`at_hash`、リクエストに `nonce` があればそれ、
IdP がどの認証コンテキストを使ったかを述べた場合は `acr` を含みます。有効期間は
`id_token_lifetime` で、既定は五分です。

**人についての情報は何も含まれません。** スコープが公開するクレームは `/userinfo` にあります。
OIDC Core 5.4 が、アクセストークンが発行されるときについて述べているとおりで、それは常に
発行されます。ID トークン自体が認証情報であるクライアント、たとえば opkssh は、
`id_token_claims = true` を設定してそれらをコピーさせます。ID トークンは `openid` スコープの
あるリクエストにのみ発行されます。

| スコープ | 公開するもの |
|---|---|
| `profile` | `name`、`given_name`、`family_name`、`preferred_username` |
| `email` | `email` (`email_verified` は決して含まない) |
| `eduperson` | `eduperson_principal_name`、`eduperson_scoped_affiliation`、`eduperson_entitlement` と `entitlements`、`eduperson_assurance`、`eduperson_orcid`、`schac_home_organization`、`voperson_id` (SAML の `subject-id` を小文字にしたもの) |
| `groups` | `groups` |

## アクセストークン {#the-access-token}

RFC 9068 が述べるとおり、クライアントの `audience` にあるリソースサーバー向けです。
`signing_key_file` (RS256) または `access_token_key_file` (ES256) で署名され、`typ: at+jwt`、
有効期間は `token_lifetime` (既定は一時間) です。リソースサーバーが誰にも尋ねずに判断するために
必要なものを運びます。`preferred_username`、`groups`、`idp` (保証した IdP のエンティティ ID)、
`scope`、`client_id`、そして IdP がセッションの終了時刻を述べた場合は `session_end` です。
グループはクライアントごとに省けます: [後述](#what-it-leaves-out)。

`audience` が複数のリソースサーバーを指すクライアントは、RFC 8707 の `resource` を使って、
そのうち一つ宛てのトークンを要求できます。
[複数のリソースサーバー]({{< relref "/authn-bridge/resources.md" >}})を参照してください。

### 何を含めないか、そしてその理由 {#what-it-leaves-out}

**`auth_time` も `acr` もありません**。RFC 9068 はどちらも許していますが、それらは OIDC Core が
置く場所である ID トークンに残ります。アクセストークンからそれを読むものはありません。
`jti` でトークンを検索するこのプロバイダーも、go-fileshare も読みません。ところがアクセス
トークンは、SSH の keyboard-interactive の回答としても貼り付けられ (ssh-oidc の mccli、
motley-cue が `/userinfo` で検証)、OpenSSH はそのうち 1023 文字を読みます。IdP の `acr` だけでも、
`urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport` は約 90 文字になります。
v0.22.0 より前は、アクセストークンは両方を運んでいました。

長い eppn と三つの AARC エンタイトルメントを持つ ES256 アクセストークン
(`access_token_key_file`) の長さを、authn-bridge の `TestES256AccessTokens` で、実際の長さの
発行者を用いて、RENATER のメタデータの `shibmd:Scope` の長さ (743 スコープ) に対して測定
しました。

| スコープの長さ | | 文字数 |
|---|---|---|
| 13 | 中央値 | 885 |
| 22 | 95 パーセンタイル | 945 |
| 29 | 99 パーセンタイル | 992 |
| 44 | 最長 | **1092: 超過** |

v0.22.0 より前は、同じトークンは 1014 / 1074 / 1121 / 1221 文字で、95 パーセンタイル以降は超過
していました。今も収まらないのは、最長のスコープと、とりわけ多数のグループです。すべての
エンタイトルメントがその URN 全体を追加し、IdP が送る数に上限はありません。3072 ビット鍵で署名
された RS256 のアクセストークンは、グループが一つもなくても約 1150 文字なので、SSH 向けの
トークンは ES256 で署名されます。1023 文字を超えると、mccli は代わりに motley-cue にワンタイム
パスワードを求めますが、これは motley-cue が既定で許可しています。素の `ssh` に貼り付ける
トークンは、収まらなければなりません。

**求めるクライアントにはグループを含めない** (v0.23.0)。すべてのグループがその URN 全体を追加し、
IdP が送る数に上限がないので、どの鍵も署名アルゴリズムも、グループを運ぶトークンが確実に収まる
ようにはしません。`access_token_groups = false` のクライアントは、その人の `groups` を含まない
アクセストークンを得ます。

```hcl
client "oidc-agent" {
  device              = true
  audience            = ["ssh"]
  access_token_groups = false
}
```

これは ssh-oidc のためのものです。oidc-agent がトークンを取得し、mccli が keyboard-interactive の
回答としてそれを貼り付け、motley-cue が `/userinfo` で検証して、そこでグループを読みます。
authn-bridge の `TestAccessTokenWithoutGroups` で測定した、50 のグループに属する人の ES256
トークンは、最長の RENATER スコープ (44) と実際の長さの発行者で、732 文字です。

テスト用フェデレーションで、三つのグループに属する人が、デバイスグラントでそのクライアント経由
でログインします。

```
$ authn-bridge token --issuer http://127.0.0.1:28473 --client oidc-agent --scope "openid eduperson groups" --cache var/tokens.json > at
To log in, open http://127.0.0.1:28473/device
and enter the code ZNBP-NMXM
(or open http://127.0.0.1:28473/device?user_code=ZNBP-NMXM)
$ tr -d '\n' < at | wc -c
     625
```

トークンは人とその IdP を名指しし、グループは含みません。

```
$ cut -d. -f2 at | tr "_-" "/+" | jq -R "@base64d | fromjson"
{
  "aud": "ssh",
  "client_id": "oidc-agent",
  "exp": 1793017858,
  "iat": 1793014258,
  "idp": "https://idp.univ-example.example/idp/shibboleth",
  "iss": "http://127.0.0.1:28473",
  "jti": "T1qu1-IjIqirgQedQ6hkQCUfeM0OFANOESdXKc3yrJA",
  "preferred_username": "alice@univ-example.example",
  "scope": "openid eduperson groups",
  "sub": "UmCstEtvM1rTavlxDxNPVw-jCNFAZhdRXU405Uz985o"
}
```

`/userinfo` は引き続きそれらを `groups` (スコープ `groups`) と `eduperson_entitlement`
(スコープ `eduperson`) として提供します。

```
$ { printf 'Authorization: Bearer '; cat at; } > auth.hdr
$ curl -s -H @auth.hdr http://127.0.0.1:28473/userinfo | jq .
{
  "eduperson_entitlement": [
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example",
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example"
  ],
  "eduperson_principal_name": "alice@univ-example.example",
  "entitlements": [
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example",
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example"
  ],
  "groups": [
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example"
  ],
  "sub": "UmCstEtvM1rTavlxDxNPVw-jCNFAZhdRXU405Uz985o",
  "voperson_id": "a1b2c3@univ-example.example"
}
```

**既定値は `true` のままです。** go-fileshare のように、トークンだけで判断するリソースサーバーには、
トークンにグループが必要です。`/userinfo` を読むサーバーにトークンが渡るクライアントについて
だけ、省いてください。

**証明書とは併用不可。** SSH と X.509 の証明書は、その人のグループをアクセストークンから取るので、
`access_token_groups = false` と `ssh_certificates` または `x509_certificates` を併せ持つクライアントは
グループを持たない証明書を発行してしまい、グループで認可するサーバーは、理由をどこにも示さずに
その人を拒否します。`check` は、起動時のサーバーと同様に、この組み合わせを拒否します。

```hcl
client "oidc-agent" {
  device              = true
  audience            = ["ssh"]
  access_token_groups = false
  ssh_certificates    = true
}
```

```
$ authn-bridge check --config etc/bridge.hcl
authn-bridge: client "oidc-agent": access_token_groups = false with ssh_certificates or x509_certificates: the certificates take the groups from the access token, and would carry none -- use one client for the certificates and another for tokens pasted into ssh
$ echo $?
1
```

証明書用に一つのクライアントを、ssh に貼り付けるトークン用に別のクライアントを用意してください。

プロバイダー自身のスコープ (`ssh`、`nfs`、`app_password`、`wireguard`、`wireguard_peers`) を
持つトークンは**プロバイダーのみ**宛てです。その `aud` は発行者で、それらのエンドポイントは
他のものを拒否します。リソースサーバーが受け取ったトークンは、ここでリプレイできません。

```
$ curl -s -X POST http://127.0.0.1:28473/ssh/certificate -d x -D - -o -
HTTP/1.1 401 Unauthorized
Content-Type: text/plain; charset=utf-8
Www-Authenticate: Bearer error="invalid_token"
X-Content-Type-Options: nosniff
Date: Mon, 26 Oct 2026 11:36:20 GMT
Content-Length: 23

the token is not valid
```

すでに渡されたアクセストークンは、リソースサーバーが単独で検証する署名付きの表明です。
[`RevokePerson`]({{< relref "/authn-bridge/admin.md" >}})が終了させるのは、それとともにここへ
戻ってくるすべてで、リソースサーバーは
[Shared Signals]({{< relref "/authn-bridge/revocation.md#shared-signals" >}})から知ります。

## ブラウザーなしで: デバイスグラント {#without-a-browser-the-device-grant}

WebDAV クライアント、スクリプト、ターミナルには、大学へ送り出すブラウザーがありません。
`device = true` のクライアントはコードを求め (RFC 8628)、人は別のデバイスでログインします。

```hcl
client "rclone" {
  device           = true
  audience         = ["fileshare"]
  refresh_lifetime = "720h"     # refresh tokens, off unless set
  name             = "rclone (WebDAV)"
}
```

`authn-bridge token --issuer https://login.example.org --client rclone` はアクセストークンを
出力します。初回はログインし、それ以降は更新します。これは golang.org/x/oauth2 のデバイス
クライアントであり、ここで書いたものではありません。

| | |
|---|---|
| ユーザーコード | `BCDFGHJKLMNPQRSTVWXZ` からの八文字 (母音も数字もなし)、有効期間十分。その間にホストごと (IPv4 アドレス、IPv6 は /64) に**間違った**コード十回まで。その周囲の /24 または /48 には十倍まで |
| ポーリング | 五秒ごと。それより速いポーリングは `slow_down` を受ける |
| 待機中のデバイス | 最大 20,000。それを超えると、全員を拒否せず、最も古いものが押し出される |
| リフレッシュトークン | 使用のたびにローテーションされる。ファミリーの終了は `refresh_lifetime` によってログイン時に固定される。廃止されたものが再度使われると、ファミリーとそれが得たアクセストークンが失効する |

## アプリケーションパスワード {#application-passwords}

NTLMv2 と SigV4 は、サーバーがすでに保持していなければならないシークレットを証明するので、SMB や
S3 ではトークンでは足りません。`app_passwords = true` のクライアントは、`app_password` スコープの
トークンで、一度だけ生成して表示されるパスワードを設定できるようにします。
`authn-bridge app-password --issuer ... --client files` (`--remove` で削除)。

```hcl
app_passwords {
  driver   = "sqlite"          # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/apppw.dsn"
  store    = ["nt_hash"]       # the default, SMB only; add "password" for S3
  lifetime = "2160h"           # the default, 90 days
  # table  = "app_passwords"   # the default
}
```

テーブルはなければ作成されます: `login, password, nt_hash, expires, idp`。プロトコルが必要とする
ものだけが保存されます。SMB 用の NT ハッシュと、`store` が求める場合に限りパスワード自体です。
go-fileshare は `users "sql"` ブロックでそれを読みます。クエリでは列名を指定し、`*` は決して
使わないでください。

人を無効化するとそのパスワードが削除され、機関を無効化するとその機関の人々のものが削除されます。
削除されたパスワードは、go-fileshare が次にディレクトリを読み込むときに使えなくなります。

## WireGuard 鍵 {#wireguard-keys}

WireGuard はピアを公開鍵だけで認証します。証明書も、有効期限も、失効もありません。そのため
プロバイダーは、*この鍵は誰のもので、まだ接続してよいか*への答えを保持します。デバイスの VPN
クライアントが公開鍵をリースとして登録し、秘密鍵はデバイスから決して出ず、ゲートウェイは有効な
鍵を、そのゲートウェイだけに宛てて署名されたリストとして読みます。

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"   # keys are recorded beside the certificates

wireguard {
  lifetime = "24h"              # the default: how long a key is listed; registering again renews it
  max_keys = 10                 # the default: devices per person
}

client "vpn" {                  # what people log in with
  device         = true
  wireguard_keys = true
}

client "vpn-gw" {               # the gateway's own client
  secret_file     = "/etc/authn-bridge/vpn-gw.secret"
  wireguard_peers = ["vpn"]     # the clients whose keys it reads
  ssf_receiver    = true        # optional: told at once when somebody is disabled
}
```

| | |
|---|---|
| `POST /wireguard/key` | `{"public_key": "...", "device": "laptop"}`。`wireguard` スコープのトークンを伴う。リースの終了時刻を返す |
| `DELETE /wireguard/key` | `{"public_key": "..."}`: 所有者が鍵を取り下げる |
| `GET /wireguard/peers` | ゲートウェイ自身の `client_credentials` トークン、スコープ `wireguard_peers` 用: そのゲートウェイ宛ての `wireguard-peers+jwt` 型の署名付き JWT。有効期間五分 |

他の誰かが保持している鍵、取り下げられた鍵、そして上限を超える鍵は `409` で拒否されます。
ゲートウェイのクライアントは機密クライアントでなければならず、`wireguard_keys` を持つクライアントを
指名しなければなりません。リストの形式とゲートウェイ側は go-authn/wireguard のものです。

## OpenPubkey と opkssh {#openpubkey-and-opkssh}

opkssh は ID トークンを、CA なしで SSH ログインに変えます。そして作られるトークン (PK Token) は、
内包する ID トークンより長生きします。プロバイダーは、コードフローとデバイスフローで `nonce` を
そのまま返し、RS256 で署名し、廃止された鍵を `retired_signing_key_files` が指名する限り**公開**
し続けるので、ローテーション前に署名された PK Token も検証できます。

```hcl
retired_signing_key_files = ["/var/lib/authn-bridge/oidc-2026-03.key"]
```

opkssh には `id_token_claims = true` の専用クライアントを与えてください。opkssh は PK Token の
クレームで人を照合し、その ID トークンはログインするすべてのサーバーに渡るからです。
