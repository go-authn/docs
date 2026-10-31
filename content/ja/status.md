---
title: "ステータス"
weight: 60
description: "これらのページが説明するリリース、各リリースで追加されたもの、そしてまだ実装されていないもの。"
tags: [ステータス, リリース]
---

これらのページはドキュメントバージョン **0.6** で、次のものを説明しています。

| プログラム | リリース | モジュール |
|---|---|---|
| authnd | **v0.14.1** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.4** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.6** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

ライブラリのバージョンは[専用ページ]({{< relref "/libraries/_index.md" >}})にあります。
ldap は **v0.11.3** で、DIT コンテンツルール、ネームフォーム、DIT 構造ルールの読み込み、適用、公開、
ビルドできないスキーマのための型付きの `BuildError`、
HCL2 のスキーマと `ldapschema` コンバーターを備えています。
directory は **v0.16.0** で、宣言されたオブジェクトクラスを備えています。
authnd v0.14.1 は ldap v0.11.3 と directory v0.16.0 を組み込んでいます。
上記のいずれかのプログラムのマイナーバージョンが新しくなると、新しいドキュメントバージョンになります。
そのため、`/docs/0.6/` 以下のページは、読者がインストールしたものを説明し続け、
以前のリリースのページは `/docs/0.1/`、`/docs/0.2/`、`/docs/0.3/`、`/docs/0.4/`、`/docs/0.5/` 以下に残ります。

{{< callout type="warning" >}}
**セキュリティ: authnd は v0.11.1 ではなく v0.12.0 を使ってください**

authnd は証明書を検証します (`x509.Certificate.Verify`。`govulncheck` によれば `main` から
到達可能)。そして Go 1.27.2 の crypto/x509 は、GO-2026-6809 が挙げる侵害された中間証明書を
信頼から外していませんでした。**v0.11.1 のリリースバイナリは Go 1.27.2 でビルドされており、
影響を受けます。** v0.12.0 は Go 1.27.3 でビルドされ、その `go` ディレクティブは 1.27.3 なので、
`go install` は修正済みのツールチェーンへ自動的に切り替わります。Go 1.27.3 での
`govulncheck` は脆弱性なしと報告します。そのリリースバイナリは `go version -m` で
`go1.27.3` と報告します。[アップグレードの注記]({{< relref "/authnd/_index.md" >}})を参照してください。
{{< /callout >}}

{{< callout type="warning" >}}
**セキュリティ: authn-bridge v0.23.3 と authn-revokd v0.6.5 を使ってください**

Go 1.27.2 では、`govulncheck` が両方のプログラムで GO-2026-6809 を報告します。`crypto/x509` の `Certificate.Verify` が、既知の侵害された中間証明書を拒否していませんでした。Go 1.26.10 と 1.27.3 で修正されています。**より古い Go でビルドしたリリースバイナリは影響を受けます。** v0.23.3 と v0.6.5 は Go 1.27.3 でビルドされ、`go` ディレクティブも 1.27.3 なので、`go install` は自動的に修正済みのツールチェーンに切り替わります。両方のリリースバイナリは `go version -m` で `go1.27.3` と表示されます。sshcert は影響を受けず、新しいリリースもありません。
{{< /callout >}}

## 各リリースで追加されたもの {#what-each-release-added}

各行は、そのリリースが切られた理由となった変更です。依存関係を更新しただけのリリースは、
このドキュメントバージョンが説明しているものを除いて省いています。

### authnd {#authnd}

| | |
|---|---|
| v0.1.0 | 別の場所にいる人々のための LDAP サーバー: ファイル、SQL データベース、別のディレクトリ |
| v0.2.0 | フィールドが一つしかないプロトコルでの第二要素 |
| v0.5.0 | ちょうど一つの ID だけに触れるパスワード変更。競合のないリロード。KDC が変更を認識する |
| v0.6.0 | oidc、directory、ldap、totp、mfa のセキュリティ修正 |
| v0.7.0 | パスワードの変更には古いパスワードが必須。シークレットは固定長のダイジェストとして比較する |
| v0.8.2 | コードは正しいパスワードに続く場合にのみ有効。リーダーは設定された DN をキーとする |
| v0.9.0 | `stable` ではなく Go 1.27.1 に固定してビルドとテストを実施 |
| v0.9.2 | すべてのタグにリリースバイナリ、`SHA256SUMS`、ビルドの来歴を付与 |
| v0.9.3 | チェックアウトの外でバイナリをビルド。各バイナリはタグを正確に報告しなければならない |
| v0.9.4 | `SIGHUP` で authnd が終了しなくなった: ログに記録され、何もリロードされない |
| v0.9.5 | リリース時に一つではなく**すべての**バイナリのビルド情報を確認 |
| v0.9.6 | `check` が、各人にチケットを発行できない理由を示す |
| v0.10.0 | `check` がサーバーと同じように証明書とキータブを開く。パスワードでバインドできない人と、トークンならまだ通る人を示す。待ち受けの行はレルムが開いた後に出る |
| v0.10.1 | go-authn/kdc v0.4.2: `till` が 19700101000000Z の場合、1970 年に期限切れのチケットではなく最長のチケットを得る |
| v0.10.2 | go-authn/directory v0.12.0: 空のグループは `memberUid` のない `posixGroup` として公開される |
| v0.11.0 | [標準スキーマのエントリ]({{< relref "/authnd/entries.md" >}})。各エントリは `cn=Subschema` で公開されるスキーマに適合しなければならない。`attributes`、`users_attributes`、`groups_attributes`。`(uidNumber>=1000)` は整数として比較する。⛔ `publish_nt_hash` には [`samba` ブロック]({{< relref "/authnd/tls.md#the-samba-block" >}})が必要で、`posixAccount` や `posixGroup` で絞り込むコンシューマーに見えるエントリが減る |
| v0.11.1 | 起動時の行は、誰かが提供を受けているソースだけを示す: `user` ブロックがなければ設定ファイルを示さなくなった |
| v0.12.0 | [サイトスキーマ]({{< relref "/authnd/schemas.md" >}}): `schema_files` (公開されているとおりの OpenLDAP `.schema` と cn=config LDIF。再定義は、slapd と同様に、同一であっても拒否される) と `schema { }` ブロック。ソースごとに `object_classes` で宣言する補助クラスは、起動時に検証され、スーパークラスとともに公開される。`check` はファイル、宣言、MUST が足りないために人から外されたクラス、二つのソースの意見が食い違うグループを報告する。⛔ Go 1.27.3 でビルド: v0.11.1 のバイナリ (Go 1.27.2) は GO-2026-6809 の影響を受ける |
| v0.12.1 | ビルドできないスキーマファイルまたはブロックは、go-authn/ldap v0.10.0 の `BuildError` が持つ位置で、列付きで拒否される (`site.schema:6:` は `site.schema:6:1:` になる)。メッセージは拒否の種類で終わり、重複は最初の定義の場所を示す |
| v0.12.2 | リリースバイナリは `-s -w` ではなく `-ldflags="-w"` でリンクされる。シンボルテーブルが残るので、`govulncheck -mode binary` はリンクされていないコードの脆弱性を報告せず、正確になる。約 9 % 大きくなる (darwin/arm64 で 18.8 MB から 20.5 MB) |
| v0.12.3 | go-authn/ldap v0.10.1: `schema_files` を線形時間で読む。⛔ v0.12.2 までは、短い継続行から成る大きなスキーマファイル (4 MiB で約 3 分) が起動を止めた。管理できないファイルによるサービス拒否 |
| v0.12.4 | go-authn/ldap v0.10.2: `cn=Subschema` の RFC 2307 の 13 個の定義(`uidNumber`、`gidNumber`、`ipHostNumber`、`ipNetworkNumber`、`ipNetmaskNumber`、`macAddress` と、クラス `ipService`、`ipProtocol`、`oncRpc`、`ipHost`、`ipNetwork`、`ieee802Device`、`bootableDevice`)の DESC の値に、RFC のページ組みのインデントが含まれなくなりました。`... in an         administrative domain'` ではなく `DESC 'An integer uniquely identifying a user in an administrative domain'` です |
| v0.13.0 | [DIT コンテンツルール、ネームフォーム、DIT 構造ルール]({{< relref "/authnd/schemas.md#rules" >}}) (go-authn/ldap v0.11.0): `schema_files` と `schema { }` ブロックは三種類を受け付け、authnd はそれらを適用する。コンテンツルールは各エントリの形を定める。`AUX` が挙げていない補助クラスは (それだけが許していた属性とともに) 外され、`NOT` の属性は破棄され、`MUST` を欠くエントリは公開されない。いずれもログに出て `check` が報告する。有効な構造ルールがあれば、木 (サフィックス、`ou=people`、`ou=groups`、`uid` または `cn` の RDN) が起動時と `check` で検査され、違反があれば**起動を拒否し**、拒否はすべて一度に示され、シークレットは決して出力されない。どのルールも配置しないエントリは外される。⛔ 有効な UTF-8 でない `schema { }` の文字列は拒否されるようになった。10,000 人の公開は、ルールありでエントリごとに 416 回の割り当て、なしで 265 回 (時間は負荷時に計測したので信頼できない) |
| v0.13.1 | 性能のみ、go-authn/ldap v0.11.1 を組み込む。10,000 人の公開 (`BenchmarkPublish10k`、`-cpu 1`) は、ルールありでエントリごとに 364 回の割り当て、なしで 239 回 (v0.13.0 は 416 回と 265 回)、1 回の実行でルールありは 102.5 MiB (v0.13.0 は 147.5 MiB)。時間は負荷 10〜16 で計測したので信頼できない |
| v0.13.2 | 性能のみ、go-authn/ldap v0.11.2 を組み込む。10 属性のエントリで `Validate` の割り当ては 76 回から 12 回に減った。10,000 人の公開 (`BenchmarkPublish10k`、`-cpu 1`) は、ルールありでエントリごとに 128 回の割り当て、なしで 85 回 (v0.13.1 は 364 回と 239 回)、1 回の実行でルールありは 54.8 MiB (v0.13.1 は 102.5 MiB)。時間 (負荷 8〜11): ルールありで約 158 ms から約 90 ms |
| v0.13.3 | 性能のみ、go-authn/ldap v0.11.3 を組み込む。`unmet` が検証したばかりのエントリは、変わっていなければ `validated` で再び検証されない。10,000 人の公開 (`BenchmarkPublish10k`、`-cpu 1`) は、ルールありでエントリごとに 97 回の割り当て、なしで 69 回 (v0.13.2 は 128 回と 85 回で、-24 % と -19 %)。時間はルールありで約 66 ms、なしで約 36 ms (負荷 4.8) |
| v0.13.4 | カオス試験。グループは人と同じく起動時に 1 回だけ読み込まれます。SQLite で 500 人・50 人ずつ 200 グループに対する検索は 4.13 秒かかり (検索のたびにグループを再問い合わせしていた)、今は 1.2 ミリ秒です。また、検索中に失敗したグループクエリが、Success を返す応答からグループを黙って落とすことはなくなりました。起動時に読み込めないソース (実行できないグループクエリ、複数のデータベースのうち 1 つの停止) は起動と `check` を拒否します。約 3 MiB を超えるエントリ (10 MB の属性値が 1 つ) は公開されません。公開内容は人の集合ごとに 1 回だけ構築されます。テストで確認済み: 全バイト位置で切ったスキーマファイル、削除または破損したデータベース、悪意のある行、放置された接続、過大な BER 長、20,000 段の入れ子フィルタ |
| v0.14.0 | 変更: v0.13.4 ではグループの変更に再起動が必要で、データベースから外したメンバーが、誰かが authnd を再起動するまでアクセス権を持ち続けていました。v0.14.0 で適時の失効を取り戻しました。`refresh` (既定 60 秒、`0` で無効) が、人とグループのすべてのソースを、応答経路の外で組み立てた新しいスナップショットに読み直し、丸ごと入れ替えます。失敗した更新は最後に正常だったスナップショットを保ち、失敗が続く間に 1 回だけ、ソース名を添えてログに記録されます。`max_age` (既定は未設定) を設定すると、提供中のデータがそれより古くなった時点で、検索・人の bind・パスワード変更が `unavailable` を返します。authnd 経由で書かれたパスワードも同じ入れ替えを通ります。計測: SQLite で 500 人・50 人ずつ 200 グループの更新は 1 コアで約 2 秒、検索は 0.5 ミリ秒 (更新コストは v0.14.1 で修正) |
| v0.14.1 | 性能のみ。更新のコストが、グループ数 × メンバーシップ行数に比例して増えなくなりました。directory v0.16.0 が各ソースを一括で 1 回だけ読み込みます。SQLite で 500 人・50 人ずつ 200 グループの更新は 1.87 秒から 0.155 秒に、10,000 人・2,000 グループの更新は 391 秒 (更新周期の 6.5 回分) から 1.6 秒 (60 秒周期の 2.7 %) になりました。アロケーションは 39,959,235 から 3,095,482 に、6,373,736,235 から 31,198,460 に減りました。時間は負荷 17〜67 の下で計測した目安で、アロケーション数は正確です |

### authn-bridge {#authn-bridge}

| | |
|---|---|
| v0.1.0 | SAML フェデレーションの手前に置く OpenID Connect プロバイダー |
| v0.2.0 | デバイスグラント、SSH 証明書、アプリケーションパスワード、OpenPubkey |
| v0.3.0 | 管理 API (`bridge.admin.v1`) と、`/healthz`、`/readyz`、`/metrics` |
| v0.4.0 | ES256 アクセストークン |
| v0.5.0 | go-authn/servercert による TLS。go-fileshare と共有 |
| v0.6.0 | 失効できる証明書: SSH KRL と、CRL を用いた NFS 向け X.509 |
| v0.7.0 | 再起動後も残る状態: リフレッシュトークンと承認済みアクセストークン |
| v0.8.0 | Shared Signals トランスミッター: CAEP `session-revoked` |
| v0.9.0 | v0.8.1 に対する敵対的レビューでの修正 |
| v0.10.0 | どこでも検証できる失効リスト: 署名付き KRL、有効期限、内容の ETag |
| v0.10.2 | 発行ごとの CRL 番号。直前より前の日付の発行は決して行わない |
| v0.11.0 | グループはその ID プロバイダーに従う。ID による無効化。bridge 専用のオーディエンス |
| v0.12.0 | 進行中のログインはメモリではなく、封印されたクッキーに保持される |
| v0.13.0 | 機密クライアントはコードをノンスで保護できる (RFC 9700 2.1.1) |
| v0.16.0 | `max_age` は、最後の認証が古すぎる場合にのみ新たな認証を求める |
| v0.16.3 | 二度目のレビュー: あらゆる表記を失効、`sub` による無効化、再起動をまたぐリプレイの防止 |
| v0.17.0 | WireGuard 鍵。利用者が登録し、ゲートウェイ向けに一覧化される |
| v0.18.0 | 本人のクレームを含まない ID トークン。go-authn/saml v0.4.0 |
| v0.19.0 | EuroHPC SSH CA プロファイル。クライアントごとにオプトイン |
| v0.19.3 | すべてのタグにリリースバイナリ、`SHA256SUMS`、ビルドの来歴を付与 |
| v0.20.0 | コマンド名は `authn-bridge`。堅牢化した systemd ユニットとインストールガイド |
| v0.20.1 | もはや正しくなかったコメントと拒否メッセージ。README に `RevokePerson` が失効させるものをすべて記載 |
| v0.21.0 | [RFC 8707 リソースインジケーター]({{< relref "/authn-bridge/resources.md" >}}): `audience` が複数のリソースサーバーを指すクライアントは、そのうち一つ宛てのトークンを要求できる。v0.20.1 の一時間前にタグ付けされたため、v0.20.1 にも含まれるが、v0.20.1 の修正は含まない |
| v0.21.1 | HTTP/2 の勧告に対応する golang.org/x/net v0.60.0 と Go 1.27.2。v0.20.1 の修正を再度反映。プレースホルダードメインを RFC 2606 の名前に変更 |
| v0.22.0 | アクセストークンが `auth_time` と `acr` を含まなくなった (ID トークンには含まれる)。これにより、ES256 トークンが RENATER のスコープの 99 パーセンタイルまで OpenSSH の 1023 文字に収まる |
| v0.22.1 | 複数のサーバーに限定したグラントのため、認可エンドポイントで `resource` を繰り返せる。`device_authorization` では無視せず拒否する ([リソースインジケーター]({{< relref "/authn-bridge/resources.md" >}})) |
| v0.23.0 | `access_token_groups = false`: トークンを ssh に貼り付けるクライアントはグループを含まない ([トークン]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}})) |
| v0.23.1 | 依存関係のみ: go-jose/v4 v4.1.6、golang.org/x/crypto v0.58.0、golang.org/x/net v0.61.0。go-authn/directory v0.12.0、revocation v0.6.3、saml v0.4.1、servercert v0.5.1、sshcert v0.1.6 |
| v0.23.2 | セキュリティ: go-authn/oidc v0.4.2。int64 の範囲外の `nbf`（まだ有効でないトークンが受理されていた）と `e = 0` の RSA 鍵（解析されていた）を拒否する。go-authn/wireguard v0.1.2 |
| v0.23.3 | Go 1.27.3 でビルド。GO-2026-6809 への対応（`crypto/x509`: `Certificate.Verify` が既知の侵害された中間証明書を拒否していなかった）。`go` ディレクティブは 1.27.3。動作の変更なし |
| v0.23.4 | リリースバイナリは `-s -w` ではなく `-w` でリンクされ、正確な `govulncheck -mode binary` のためにシンボルテーブルが残る。動作の変更なし |

### authn-revokd {#authn-revokd}

| | |
|---|---|
| v0.1.0 | 署名付きで期限のある失効リスト: プロトコル、ライブラリ、revokd (エージェントとミラー) |
| v0.2.0 | 敵対的レビューでの修正 |
| v0.2.1 | 各 CA のリストをその CA 自身の鍵失効とマージ。CRL は解析する前に署名を確認する |
| v0.3.0 | スコープ付きの鍵失効。CA ごとのフェイルクローズ。状態ディレクトリの所有者の確認 |
| v0.5.0 | すべてのタグにリリースバイナリ、`SHA256SUMS`、ビルドの来歴を付与 |
| v0.6.0 | コマンド名は `authn-revokd`。systemd ユニットとインストールガイド。`SIGHUP` で即座に同期 |
| v0.6.1 | `-version` は標準出力に表示する |
| v0.6.2 | `-once` は取得の失敗と期限切れのリストを区別する。別の鍵で署名されたリストを競合と呼ばなくなった。`-help` は 0 で終了する |
| v0.6.3 | サンプルとドキュメントのプレースホルダードメインを RFC 2606 の名前に変更。動作に変更なし |
| v0.6.4 | 依存関係のみ: golang.org/x/crypto v0.58.0 |
| v0.6.5 | Go 1.27.3 でビルド。GO-2026-6809 への対応（`crypto/x509`: `Certificate.Verify` が既知の侵害された中間証明書を拒否していなかった）。`go` ディレクティブは 1.27.3。動作の変更なし |
| v0.6.6 | リリースバイナリは `-s -w` ではなく `-w` でリンクされ、正確な `govulncheck -mode binary` のためにシンボルテーブルが残る。動作の変更なし |

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | ドメイン許可の拡張と、フェイルクローズの `sshcert-authorize` |
| v0.1.2 | すべてのタグにリリースバイナリ、`SHA256SUMS`、ビルドの来歴を付与 |
| v0.1.4 | リリース時にすべてのバイナリのビルド情報を確認 |
| v0.1.5 | `-version` は `go install` ビルドのモジュールバージョンを表示する (`dev` ではない) |
| v0.1.6 | ドキュメントのプレースホルダードメインを RFC 2606 の名前に変更。動作に変更なし |
| v0.1.7 | 依存関係のみ: golang.org/x/crypto v0.58.0 |
| v0.1.8 | リリースバイナリは `-s -w` ではなく `-w` でリンクされ、正確な `govulncheck -mode binary` のためにシンボルテーブルが残る。動作の変更なし |
| v0.1.9 | Go 1.27.3 でビルド。動作の変更なし |

### ライブラリ {#the-libraries}

このドキュメントバージョンのために作られたライブラリのリリースです。以前のリリースでの変更は、
各ライブラリのページに記載されています。

| | |
|---|---|
| directory v0.13.0 | [属性]({{< relref "/libraries/directory.md#attributes" >}}): 認証情報を除き、誰かを説明するだけで何も証明しないもの。属性にはなり得ない名前も定められている。`user` と `group` ブロックの `attributes`、`users_attributes` と `groups_attributes` クエリ、ldapdir の `attributes` と `group_attributes` |
| directory v0.14.0 | ⛔ ldapdir の[既定値]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})が `account` と `uidObject` の人々と `groupOfNames` のグループを読むようになり、組織のディレクトリが提供する範囲が広がる。`member` DN は、ソースがインポートした人にのみ対応付けられる |
| directory v0.15.0 | [オブジェクトクラス]({{< relref "/libraries/directory.md#object-classes" >}})。宣言されるもので推論されない: `users` ブロックの `object_classes` と `group_object_classes`、`user` と `group` ブロックの `object_classes`、sqldir の `WithObjectClasses`、ldapdir の `Config.ObjectClasses`。グループのクラスを最初に宣言したソースが決める。`sqldir.ClosesDB` |
| kdc v0.4.3 | 依存関係のみ: 最小バージョンとして go-authn/directory v0.12.0 |
| keyfactor v0.4.2 | 依存関係のみ: 最小バージョンとして go-authn/fido v0.6.2 と golang.org/x/crypto v0.58.0 |
| krb5 v0.3.1 | Go 1.27.2 でテスト。コードも `go.mod` も変更なし |
| krl v0.6.1 | 依存関係のみ: golang.org/x/crypto v0.58.0。Go 1.27.2 でテスト |
| ldap v0.8.0 | [パッケージ `schema`]({{< relref "/libraries/ldap.md#the-schema" >}}) と `Server.Schema`: `cn=Subschema` (RFC 4512 §4.2)、`Validate`、RFC 4517 のマッチングルール。`uidNumber` と `gidNumber` は整数として順序付けされる。ページング検索は要求された属性にとどまる |
| ldap v0.9.0 | [HCL2 のスキーマ]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}): パッケージ `schema/hclschema` と、OpenLDAP の `.schema`、cn=config LDIF、HCL2 の間を変換する `ldapschema` コマンド (`to-hcl`、`to-schema`、`check`)。リーダーは slapd と同じようにファイルを読む。DIT コンテンツルールと構造ルール、ネームフォーム、`include`、`X-SUBST` はサポートしない (v0.11.0 はルールをサポートする) |
| ldap v0.10.0 | `Build` が拒否する定義のための[型付きの `*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}})。`errors.As` で照合する: `Kind`、`Element`、`OID`、`Name`、`Field`、`Pos` (定義の始まる file:line:column。折り返された LDIF や base64 の LDIF、HCL でも同様)、もう一方の定義のための `Ref`、`RefOID`、`RefPos`。読み込まれたすべての定義が `Pos` を持つ。メッセージ中の "object classes" |
| ldap v0.10.1 | [`schema.Read`]({{< relref "/libraries/ldap.md#reading-large-files" >}}) は継続行の数に対して線形になった (以前は二乗時間で、4 MiB のファイルに約 3 分かかった)。最初の行を読むためにファイル全体をコピーして分割することもなくなった。`schema.Format` は 2000 バイトを超える行 (slapd と `Read` は拒否する) を折り返す。厳格なパーサーは約 2.6 倍速い (`cosine.schema` で割り当て 498 回が 147 回、負荷時に計測) |
| ldap v0.10.2 | 組み込みスキーマ(`schema.Standard()`)の RFC 2307 の 13 個の定義の DESC を 1 行にしました。RFC のページ組みのインデントを含んでおり、リーダーは slapd と同様に引用符の中でそれを保持するため、サーバーが公開するサブスキーマに連続した空白が入っていました。テストが、組み込みの各 DESC をこの点で検査し、同じ OID が定義されている場合は OpenLDAP の `core`、`cosine`、`inetorgperson`、`nis` スキーマと比較します |
| ldap v0.11.0 | [DIT コンテンツルール、ネームフォーム、DIT 構造ルール]({{< relref "/libraries/ldap.md#rules" >}}) (RFC 4512 §4.1.6、§4.1.7)。`.schema` と LDIF から読み、`Format` が書き、HCL (`dit_content_rule`、`name_form`、`dit_structure_rule`) と `ldapschema` を通り、`Build` が検査し、`Validate` が適用し (コンテンツルール: AUX、MUST、MAY、NOT。ネームフォーム: RDN。構造ルール: `GoverningStructureRule`)、あるときに限って `cn=Subschema` で公開される。`ValidateOptions{StrictAuxiliary}` は RFC 4512 §2.4.3 を与える。⛔ slapd が実装するのはコンテンツルールだけなので、`Format` は slapd が拒否する `nameform` と `ditstructurerule` のキーワードを書く。`OBSOLETE` のルールは無効で、slapd はそのエントリを拒否する。libldap は構造ルールの `SUP` を読めない。`hclschema.Decode` は UTF-8 でない文字列を拒否する |
| ldap v0.11.1 | 性能のみで、結果は変わらない。印字可能な ASCII の文字列は、文字列照合ルール (RFC 4518) のために多くても 1 回の割り当てで準備され、何も変わらないときは割り当てなしで済む。4 つの RDN をもつ DN では DN パーサーの割り当ては 11 回から 6 回に減る。結果は v0.11.0 と同じで、0x80 未満の 1 バイトまたは 2 バイトのすべての文字列について v0.11.0 のコードと照合し、差分ファザーでも確かめた |
| ldap v0.11.2 | 性能のみで、結果は変わらない。10 属性のエントリで `Validate` の割り当ては 76 回から 12 回に減る (小文字コピーなしの検索、分割して結合し直さない description、map の代わりにその場に置く集合)。結果は v0.11.1 と同じで、標準スキーマとルール付きスキーマの下でランダムなエントリについて v0.11.1 の `Validate` のコピーと照合し、差分ファザーでも確かめた |
| ldap v0.11.3 | 性能のみで、結果は変わらない。`GoverningStructureRule` の割り当ては、アカウントで 12 回から 5 回に減る (RDN の型だけを読む)。DN パーサーは 4 つの RDN をもつ DN で 6 回から 3 回に減る。結果は v0.11.2 と同じで、ランダムなエントリとすべての上位ルールについて v0.11.2 の `GoverningStructureRule` のコピーと照合し、差分ファザーでも確かめた |
| oidc v0.4.1 | Go 1.27.2 でテスト。コードも `go.mod` も変更なし |
| servercert v0.5.2 | Go 1.27.2 でテスト。コードも `go.mod` も変更なし |
| totp v0.4.2 | Go 1.27.2 でテスト。コードも `go.mod` も変更なし |
| wireguard v0.1.1 | Go 1.27.2 でテスト。コードも `go.mod` も変更なし |

## まだ実装されていないもの {#not-implemented-yet}

- **LDAP 経由の書き込み**。本人が自分のパスワードを変更する場合を除きます。authnd は
  自分自身の `userPassword` の modify と RFC 3062 のパスワード変更操作 (`ldappasswd` が
  送るもの) に応答しますが、どちらも現在のパスワードがある場合に限られ、それ以外には
  応答しません。add、delete、modifyDN は go-authn/ldap に存在しますが、意図的に接続して
  いません (`server.go`)。ライブラリは modify を順序付きのリストとして保持し (RFC 4511 4.6)、
  エントリ読み取りコントロール (RFC 4527) にも応答するので、土台はあります。欠けているのは、
  誰が何を書いてよいかというポリシーです。
- **Kerberos 内での第二要素**: FAST (RFC 6113) 内の OTP 事前認証 (RFC 6560)。これが
  実現するまでは、`kerberos` ブロックと `mfa` ブロックを両方設定することはできません。
- **RC4-HMAC**: レルムは aes256-cts-hmac-sha1-96 だけを発行するため、NT ハッシュしか
  知られていない人にはチケットを発行できません。これは (RC4 は RFC 8429 で非推奨)
  選択であり、埋められるのを待つ欠落ではありません。
