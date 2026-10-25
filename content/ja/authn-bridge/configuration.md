---
title: "設定"
linkTitle: "設定"
weight: 20
description: "authn-bridge の HCL 設定の構成、check が出力するもの、そして誰かがログインできるようになる前に拒否されるもの。"
tags: [authn-bridge, 設定]
---

一つの HCL ファイル、またはそのディレクトリ: `--config /etc/authn-bridge` はそこにあるすべての
`*.hcl` を名前順に読み込んでマージし、`--config` は複数回指定できます。設定は起動時に読み込まれ、
その後は二度と読まれません。

```hcl
issuer            = "https://login.example.org"       # https; compared whole by every relying party
listen            = "127.0.0.1:8080"                  # the default: plain HTTP behind a TLS proxy
signing_key_file  = "/var/lib/authn-bridge/oidc.key"  # authn-bridge keygen --key
subject_salt_file = "/var/lib/authn-bridge/salt"      # authn-bridge keygen --salt; never change it
disabled_file     = "/var/lib/authn-bridge/disabled.json"
certificates_file = "/var/lib/authn-bridge/certificates.json"

saml {
  key_file             = "/var/lib/authn-bridge/saml.key"
  cert_file            = "/var/lib/authn-bridge/saml.crt"
  metadata_url         = "https://pub.federation.renater.fr/metadata/fer/idps.xml"
  metadata_cert_file   = "/etc/authn-bridge/metadata-signature-2026.pem"
  metadata_fingerprint = "68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0"
}

state {
  driver   = "sqlite"                                 # or postgres, mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}

client "my-app" {
  secret_file   = "/etc/authn-bridge/my-app.secret"   # absent: a public client
  redirect_uris = ["https://app.example.org/callback"]
}
```

必須なのは、`issuer`、`signing_key_file`、`subject_salt_file`、上記の五つのキーを持つ `saml`
ブロック、そして少なくとも一つの `client` です。それ以外はすべて既定値があるか、オフです。

## 再起動前の `check` {#check-before-a-restart}

`check` はサーバーと同じ方法で設定を読み、指名されたすべての鍵を読み込み、
**フェデレーションのメタデータを取得**し、何が提供されるかを述べます。

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-10-18T09:46:24Z
client        sftp (public, public subject, audience [sftp])
client        efp (public, public subject, audience [efp])
client        nfs (public, public subject, audience [nfs])
```

*Usable here* は、`saml { idps }` に列挙されていない IdP と、[管理 API]({{< relref "/authn-bridge/admin.md" >}})
で無効化された IdP を除きます。上の機関を無効化すると、同じコマンドは
`federation    1 IdPs, 0 usable here` と出力します。フェデレーションが列挙していない `idps` の
エントリは、サーバーならそれでも起動するのに、ここでは拒否されます。

```
federation    1 IdPs, 0 usable here, valid until 2026-10-18T09:46:24Z
authn-bridge: idps names "https://idp.nowhere.example/idp", which the federation does not list
```

`authn-bridge metadata` は、フェデレーションに登録する SAML メタデータを出力します。
[フェデレーション側]({{< relref "/authn-bridge/federation.md" >}})を参照してください。

## トップレベル {#the-top-level}

| キー | 既定値 | |
|---|---|---|
| `issuer` | | プロバイダーの名前と、すべての URL のベース。`https`、またはテスト用のループバックホストでの `http`。クエリもフラグメントもなし。末尾の `/` は除去される |
| `listen` | `127.0.0.1:8080` | 公開リスナー |
| `cert_file`、`key_file` | | これらのファイルから TLS を提供する。変更されると再読み込みされる。両方指定するか、どちらも指定しない |
| `acme` | | 代わりに ACME CA の証明書で TLS を提供する (後述)。`cert_file` とは併用不可 |
| `signing_key_file` | | RSA。ID トークンに署名する (RS256)。ここに P-256 鍵を置くと拒否される |
| `access_token_key_file` | 署名鍵 | アクセストークンに ES256 で署名する P-256 鍵。署名鍵と同じものは拒否される |
| `retired_signing_key_files` | | 以前に署名した鍵。`/jwks` では引き続き公開されるが、署名には決して使われない |
| `subject_salt_file` | | 32 バイト以上 |
| `code_lifetime` | `1m` | 最大十分 (RFC 6749 4.1.2) |
| `token_lifetime` | `1h` | アクセストークン |
| `id_token_lifetime` | `5m` | ID トークン |
| `trusted_proxies` | | `X-Forwarded-For` が信頼されるアドレスまたはプレフィックス |
| `requests_per_minute` | `120` | 一つのアドレスが一分間に開始できるログイン、デバイスグラント、ACS の POST の数。`0` で制限なし |
| `disabled_file` | | 無効化された人と機関が保持される場所。なければ無効化は拒否される |
| `certificates_file` | | 発行されたすべての証明書と WireGuard 鍵。`ssh_ca`、`x509_ca`、`wireguard` では必須 |

ブロック:

| ブロック | ページ |
|---|---|
| `saml`、`claims` | [フェデレーション側]({{< relref "/authn-bridge/federation.md" >}}) |
| `client` | 後述、および[トークン]({{< relref "/authn-bridge/tokens.md" >}}) |
| `state` | 後述 |
| `ssh_ca`、`x509_ca` | [証明書]({{< relref "/authn-bridge/certificates.md" >}}) |
| `app_passwords`、`wireguard` | [トークン]({{< relref "/authn-bridge/tokens.md" >}}) |
| `ssf` | [失効]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |
| `admin`、`metrics` | [管理 API]({{< relref "/authn-bridge/admin.md" >}}) |
| `acme` | 後述 |

## クライアント {#a-client}

| キー | 既定値 | |
|---|---|---|
| `secret_file` | | クライアントシークレット。16 文字以上。なければ**パブリック**クライアント |
| `redirect_uris` | | 完全一致で比較される。ただしループバック URI はポートが変わってもよい (RFC 8252)。`http` はループバックのみ |
| `audience` | クライアント ID | そのアクセストークンの宛先。複数ある場合、そのうち一つ宛てのトークンを要求できる ([RFC 8707]({{< relref "/authn-bridge/resources.md" >}})) |
| `subject` | `public` | または `pairwise`: このクライアント専用の別の `sub` (OIDC Core 8.1) |
| `name` | クライアント ID | デバイス確認ページに表示される |
| `device` | `false` | デバイスグラント (RFC 8628)。このクライアントにリダイレクト URI は不要 |
| `refresh_lifetime` | オフ | リフレッシュトークンと、**ログイン**からどれだけ後に終了するか |
| `pkce` | `required` | または `or_nonce`。機密クライアントのみ: PKCE の代わりに `nonce` を使う |
| `id_token_claims` | `false` | 公開されたクレームを ID トークンにもコピーする (opkssh が必要とする) |
| `access_token_groups` | `true` | `false` にすると、ssh に貼り付けるトークン向けに、その人のグループをアクセストークンから除く ([トークン]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}}))。`ssh_certificates` や `x509_certificates` とは併用不可 |
| `ssh_certificates`、`ssh_*` | | [SSH 証明書]({{< relref "/authn-bridge/certificates.md#ssh-certificates" >}}) |
| `x509_certificates` | | [NFS クライアント証明書]({{< relref "/authn-bridge/certificates.md#x509-client-certificates-for-nfs-over-tls" >}}) |
| `app_passwords` | | その人の[アプリケーションパスワード]({{< relref "/authn-bridge/tokens.md#application-passwords" >}})を設定できる |
| `wireguard_keys`、`wireguard_peers` | | [WireGuard]({{< relref "/authn-bridge/tokens.md#wireguard-keys" >}}) |
| `ssf_receiver`、`ssf_subject_format` | | [Shared Signals レシーバー]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |

リダイレクト URI のないクライアントは、デバイスクライアント、SSF レシーバー、または WireGuard
ゲートウェイでなければなりません。そうでなければ、何もできないからです。

## `state`: 再起動で忘れてはならないもの {#state-what-a-restart-must-not-forget}

```hcl
state {
  driver   = "postgres"                  # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}
```

リフレッシュトークンファミリー、リフレッシュトークンと廃止されたもの、`/userinfo` と証明書のために
承認されたアクセストークン、すでに受け入れられた SAML アサーション、すでに応答されたログイン、
SSF ストリームとその未配信のイベントは、一つのテーブル `bridge_state` (なければ作成されます) に
書き込みと同時に保存され、起動時に読み込まれます。リフレッシュトークンは SHA-256 として保持され、
そのものとして保持されることはありません。ブロックがなければ、これらはメモリ上にあり、再起動で
全員がログアウトされます。

進行中のログインはこれに含まれません。それは専用のクッキーで運ばれ、サブジェクトのソルトから
導出した鍵の AES-256-GCM で封印されるので、ブラウザーはそれを読むことも変更することもできません。

## `acme` {#acme}

```hcl
acme {
  accept_terms_of_service = true                     # the operator's agreement; no default
  cache_dir               = "/var/lib/authn-bridge/acme"
  email                   = "noc@example.org"
  # directory_url         = "..."                    # Let's Encrypt by default
  # eab_key_id            = "..."                    # External Account Binding (GÉANT TCS / HARICA)
  # eab_hmac_key_file     = "/etc/authn-bridge/harica-eab.key"
  # http_listen           = ":80"                    # http-01, and a redirect to https
  # directory_ca_file     = "..."                    # a private ACME CA's own TLS
}
```

証明書は発行者のホスト用です。`cache_dir` は秘密鍵を保持し、他のユーザーが到達できる、または
付け替えられるディレクトリでは、プロバイダーは起動を拒否します。

## 起動時に拒否されるもの {#what-is-refused-at-startup}

以下はいずれも、それを求めた設定に対する `authn-bridge check` の出力です。サーバーも同じ設定を
拒否します。それぞれ、設定とそれが指名するファイルから読み取られるものです。`check` が追加する
唯一の拒否は、フェデレーションが列挙していない `idps` のエントリで、
[前述のとおり](#check-before-a-restart)です。サーバーは同じメタデータを待ち受けの前に取得
しますが、`idps` をそれに照らして検証しません。

**漏えいする発行者、リダイレクト、シークレット:**

```
authn-bridge: issuer "http://login.example.org": an issuer is https (http only on loopback, for testing)
authn-bridge: client "web": redirect URI "http://app.example.org/callback": a code sent over cleartext http is a code anybody on the path has
authn-bridge: client "web": a secret of 5 characters is a password somebody can guess
authn-bridge: code_lifetime = 15m0s: an authorization code lives ten minutes at most
```

**どの機関でも名乗れてしまう名前:**

```
authn-bridge: claims: username = "uid" is not held to an IdP's scopes, so any IdP of the federation could name anybody: it needs saml { idps } to list exactly one IdP; with more, use eppn or subject_id
authn-bridge: claims: groups = "affiliation" carries no institution, so any IdP of the federation could grant any of its values: it needs saml { idps } to list exactly one IdP; with more, use scoped_affiliation
```

**発行したら取り戻せなくなるもの:**

```
authn-bridge: ssh_ca: certificates_file is required with ssh_ca or x509_ca: a certificate that is not recorded can never be revoked
authn-bridge: ssh_ca: validity = 200h0m0s: more than a week, and a certificate lives that long on every server its revocation has not reached
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```

**到達できてはならないリスナー:**

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
authn-bridge: metrics: listen is the public listener; metrics have one of their own
```

**同じことを二度述べる設定:**

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
authn-bridge: client "sftp" is declared twice
```

SSH プロファイル固有の拒否は[証明書]({{< relref "/authn-bridge/certificates.md#what-the-profile-refuses" >}})に、
フェデレーションの拒否は[フェデレーション側]({{< relref "/authn-bridge/federation.md#what-is-refused" >}})にあります。
