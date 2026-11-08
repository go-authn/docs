---
title: "ステータス"
weight: 60
description: "これらのページが説明するリリース、各リリースで追加されたもの、そしてまだ実装されていないもの。"
tags: [ステータス, リリース]
---

これらのページはドキュメントバージョン **0.11** で、次のものを説明しています。

| プログラム | リリース | モジュール |
|---|---|---|
| authnd | **v0.18.6** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.12** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.7.0** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

ライブラリのバージョンは[専用ページ]({{< relref "/libraries/_index.md" >}})にあります。
ldap は **v0.12.3** で、DIT コンテンツルール、ネームフォーム、DIT 構造ルールの読み込み、適用、公開、
ビルドできないスキーマのための型付きの `BuildError`、
HCL2 のスキーマと `ldapschema` コンバーターを備えています。
directory は **v0.21.0** で、宣言されたオブジェクトクラス、すべての SQL クエリの期限、
そして失敗したソースを報告する `GroupNames` を備えています。
authnd v0.18.6 は ldap v0.12.3 と directory v0.20.0 を組み込んでいます。
上記のいずれかのプログラムのマイナーバージョンが新しくなると、新しいドキュメントバージョンになります。
そのため、`/docs/0.11/` 以下のページは、読者がインストールしたものを説明し続け、
以前のリリースのページは `/docs/0.1/`、`/docs/0.2/`、`/docs/0.3/`、`/docs/0.4/`、`/docs/0.5/`、`/docs/0.6/`、`/docs/0.7/`、`/docs/0.8/`、`/docs/0.9/`、`/docs/0.10/` 以下に残ります。

{{< callout type="warning" >}}
**authnd を v0.16.x からアップグレードする: `max_age` のデフォルトは 10 分です**

提供されるデータにはこれまで年齢の上限がなく、ソースから削除された人が、そのソースが読めなくなった後も障害が続く限り bind できていました。v0.17.0 から `max_age` は 10 分 (`refresh` の周期の 10 回分以上。`refresh = "0"` ではデフォルトなし) で、それを過ぎると検索、人の bind、パスワード変更は `unavailable` (52) を返します。`max_age` を許容できる値に設定するか、無制限なら `"0"` にしてください。[アップグレードの注意]({{< relref "/authnd/_index.md" >}})と[古いデータの拒否]({{< relref "/authnd/operations.md#it-reads-everything-once" >}})を参照してください。
{{< /callout >}}

{{< callout type="warning" >}}
**authnd を v0.15.x からアップグレードする: `oidc { domains }` が必須になります**

`oidc` ブロックのある設定は `domains` がないと起動せず、トークンの名前は許可されたドメインのちょうど 1 つの
`local@scope` でなければなりません。連合プロキシの背後では、どの機関の alice もローカルの alice としてバインドできました。
`domains` を追加し、`username_claim = "eduperson_principal_name"` を設定し、ディレクトリの名前がローカル部分だけの場合は
`local_domain` を追加してください。[アップグレードの注記]({{< relref "/authnd/_index.md" >}})と
[名前にはスコープが必要]({{< relref "/authnd/tokens.md#scoped-name" >}})を参照してください。
{{< /callout >}}

{{< callout type="warning" >}}
**authnd を v0.14.x からアップグレードする: 既定値が二つ変わります**

`max_connections` は `4096` (以前は無制限)、`operation_timeout` は `30s` (以前はなし) です。上流のディレクトリが
落ちているときは `unavailable` (52) が返り、`invalidCredentials` (49) ではなくなります。
`max_connections = 0` と `operation_timeout = "0"` で以前の動作になります。
[制限と期限]({{< relref "/authnd/operations.md#limits" >}})を参照してください。
{{< /callout >}}

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
| v0.15.0 | 可用性とセキュリティ。go-authn/ldap v0.12.0 と go-authn/directory v0.17.0 を使用。⛔ **既定値が二つ変わります**: `max_connections` は `4096` (以前は無制限)、`operation_timeout` は `30s` (以前はなし)。新規で省略可能: `max_connections_per_ip` と `startup_timeout` (`60s`)。[`check` は制限を表示します]({{< relref "/authnd/operations.md#limits" >}})。上限を超えた接続には `busy` が送られて閉じられ、期限を過ぎた操作は、ハンドラーがブロックしていても `timeLimitExceeded` で答えられます。バインド中の上流の障害 (単純バインド、パスワード変更、`mfa` のパスワード要素) は `unavailable` (52) で、`invalidCredentials` (49) にはなりません。間違ったパスワードは今も 49 です。遅いソースに対する起動は `startup_timeout` の後に失敗し、段階とソースを名指しします。[TLS 証明書は読み直されます]({{< relref "/authnd/tls.md#renewal" >}}) (`cert_file` や `key_file` が変わったとき。5 秒後の最初のハンドシェイクと `SIGHUP`)。読み込めない組は提供中の証明書を保ち、一度だけログに記録されます。アロケーション数は下のライブラリにあります。実時間は未測定 (開始時の負荷は 21) |
| v0.15.1 | Kerberos。go-authn/kdc v0.5.0 を使用: バイト単位で同一の再送には以前の応答を返し (MIT の lookaside)、ディレクトリの障害は正しいパスワードでも `KDC_ERR_SVC_UNAVAILABLE` で、`KDC_ERR_PREAUTH_FAILED` にはならないため、ロックアウトに数えられません。golang.org/x/net v0.62.0。設定の変更なし |
| v0.16.0 | ⛔ セキュリティ。go-authn/oidc v0.6.1 と go-authn/directory v0.18.0 を使用。**`oidc` ブロックのあるデプロイには互換性のない変更**: [`domains` が必須]({{< relref "/authnd/tokens.md#scoped-name" >}})で、これがないとサーバーは起動しません。トークンの名前は許可されたドメインのちょうど 1 つの `local@scope` でなければならず（スコープのない名前、別の機関の名前、`@` が 2 つある名前は拒否）、任意の `local_domain`（`domains` のいずれか）はそのスコープの人をローカル部分だけのディレクトリ名に対応付け、他のスコープは `local@scope` の全体で検索されます。連合プロキシの背後では、どの機関の alice もローカルの alice としてバインドできました。1 つのソースの 2 つのエントリが同じ uid を持つ場合は、黙って 1 つを選ぶのではなく、起動時とリフレッシュ時のエラーになります。[アップグレードの注記]({{< relref "/authnd/_index.md" >}}) |
| v0.16.1 | `kerberos { listen = "host:0" }` は UDP と TCP に一つのポートを得ます (以前は二つで、`krb5.conf` は一つしか名指せません)。起動時の行はそのポートを示します。テストはポートを選んで解放してから名指すことをやめました。これはランナー上で `address already in use` で失敗していました |
| v0.16.2 | ⛔ セキュリティ。[レルムはスナップショットを読みます]({{< relref "/authnd/kerberos.md#where-the-realm-reads-people" >}})。ソースは読みません: すべての AS-REQ と TGS-REQ (UDP 上の認証なしの AS-REQ を含む) が、各 SQL ソースの人々のクエリ全体と各 `ldap` 上流のサブツリー検索を実行していました。`max_age` は Kerberos にも適用されます (超えると `KDC_ERR_SVC_UNAVAILABLE`)。データベースから削除された人は、LDAP バインドと同様に `refresh` の一周期以内にチケットを得られなくなります。go-authn/kdc v0.6.0 を使用 |
| v0.17.0 | ⛔ セキュリティ、2 回目の見直し。go-authn/ldap v0.12.1 を使用。**破壊的変更: [`max_age` にデフォルト値が付きました]({{< relref "/authnd/operations.md#it-reads-everything-once" >}})**。10 分 (`refresh` の周期の 10 回分以上。`refresh = "0"` ではデフォルトなし) で、以前は無制限でした。ソースから削除された人が、そのソースが読めなくなった後も障害が続く限り bind できていました。これを過ぎると、検索、人の bind、パスワード変更は `unavailable` (52) を返します。`max_age = "0"` は受け付けられ、意図的な無制限を意味します。[トークンの名前は ASCII の大文字小文字の畳み込みのみで比較されます]({{< relref "/authnd/tokens.md#scoped-name" >}}): ケルビン記号 (U+212A) を使った `Kate@univ-a.example` は `kate` として bind されなくなりました。上流に対する[ソースごとの未完了のチェックは最大 64 件]({{< relref "/authnd/operations.md#outage" >}})で、65 件目は直ちに `unavailable` で応答されます (応答しない上流に対する 400 件の bind で保持される goroutine は 1620 から 257 になりました)。[アップグレードの注意]({{< relref "/authnd/_index.md" >}}) |
| v0.18.0 | [上流に対するパスワードチェックは、制限されるだけでなく取り消される]({{< relref "/authnd/operations.md#outage" >}}): bind とパスワード要素は `Identity.VerifyContext` (go-authn/directory v0.19.0) を使い、bind の予算が尽きると上流への接続を閉じるので、何も動き続けません。応答しない上流に対する 400 件の bind で保持される goroutine: 1620 (v0.16.2)、257 (v0.17.0、上限)、4 (v0.18.0)。ソースごとに最大 64 件という上限は、取り消せないソースのために残ります。名前の畳み込みは go-authn/oidc v0.7.0 のものです。設定の変更はありません |
| v0.18.1 | [起動のタイムアウトが、開こうとしていた SQL ソースを示す]({{< relref "/authnd/operations.md#limits" >}}): `opening sql pgx (dsn_file …) did not answer`。以前はどの SQL ブロックも `opening sql` でした。ドライバーと DSN を保持するファイルを示し、DSN は決して示しません。テスト: 使い捨てクラスター上の本物の PostgreSQL に対するカオステスト (リフレッシュ中のサーバー停止、クエリの途中での接続リセット、決して応答しないリスナー、障害中の Kerberos レルム)。サーバーのバイナリがなければスキップされ、`AUTHND_REQUIRE_PG=1` を指定した場合は失敗になります。設定の変更はありません |
| v0.18.2 | [ハングした SQL の読み取りがリフレッシュを止めなくなった]({{< relref "/authnd/people.md" >}}): 接続を受け付けて応答しなくなったデータベースがあると、リフレッシュがクエリの中でブロックされ、以降のティックはすべてスキップされ、`max_age` を過ぎると再起動まですべてが `unavailable` を返しました。`users "sql"` ブロックに `query_timeout` が加わり、既定は `refresh` の 4 分の 3 です (go-authn/directory v0.20.0)。**動作の変更:** 期限より遅い単一のクエリは失敗します。より遅いクエリには `query_timeout` を設定してください |
| v0.18.3 | [戻ったときは停止している]({{< relref "/authnd/operations.md" >}}): シャットダウンが戻った時点で、LDAP リスナーと Kerberos の 2 つのソケットは閉じられ、サーバーは終了しているため、再起動はすぐにバインドできます。サーバーが Kerberos ライブラリに達する前にシャットダウンが届くと、以前はレルムの UDP と TCP のソケットが開いたまま戻っていました。設定の変更はありません |
| v0.18.4 | LDAP アップストリームに対するリフレッシュのアロケーションが以前の 4 分の 1 になりました (go-authn/ldap v0.12.2)。公開エントリのスキーマ検査が `member` 値のすべての組を比較し、そのたびに両方の DN を解析していました。10,000 人と 50 個の DN を持つ 2,000 グループのリフレッシュを同一プロセス内の LDAP アップストリームに対して実行すると (`BenchmarkRefreshLDAP10k2k`、正確なカウント)、以前は 3,760 万アロケーションと 2.43 GB、今は 995 万と 651 MB です。設定の変更はありません |
| v0.18.5 | 応答しないアップストリームに対する bind は、負荷の高いホストでも `timeLimitExceeded` (3) ではなく `unavailable` (52) で応答されます。bind の予算は、ライブラリの `operation_timeout` の期限より、その 10 分の 1 (最小 250 ms、最大でその半分) だけ早く終わります。以前は 10 分の 1 だけ (`"300ms"` で 30 ms) で、負荷の高いホストはそれを使い切っていました。設定の変更はありません |
| v0.18.6 | go-authn/ldap v0.12.3: 同じリフレッシュは 835 万アロケーションと 573 MB になりました (v0.18.4 では 995 万と 651 MB)。残りは主にクライアント側の LDAP ワイヤライブラリと、同一プロセス内のテストサーバーです。設定の変更はありません |

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
| v0.23.6 | 監査、ファジング、カオスの実施。go-authn/saml v0.5.1 を使用。設定キーの追加・変更はありません。[メタデータは間に合うように更新されます]({{< relref "/authn-bridge/federation.md#refreshing-it" >}}): `validUntil` の残りの半分を超えて予定されることはなく、有効なメタデータがなければ一分後に再試行して間隔を倍にしながら最大一時間まで延ばすので、期限近くの更新の失敗でプロバイダーが最大十二時間 IdP を失うことはなくなりました。アサーションのリプレイキーは SHA-256 として保存されます。長い IdP の `entityID` で PostgreSQL と MySQL が書き込みを拒否し、状態データベースが詰まっていました。時計は IdP と三分までずれてよく、一時間は 400 ページで拒否されます。[テストされているもの]({{< relref "/authn-bridge/federation.md#tested" >}}): XML 署名ラッピング XSW1 から XSW8、CVE-2017-11427、DOCTYPE、他のオーディエンス・受信者・リクエスト・宛先、五つのファザー。ログイン一回あたりの SHA-256 は、アロケーションが 0 から 2 回増えます (`BenchmarkReplayUse`: 0 回・183 B から 2 回・326 B)。実時間は未測定、負荷 53 から 75 |
| v0.23.7 | セキュリティ: `saml { idps }` から外された IdP 由来のリフレッシュトークン、アプリケーションパスワード、SSH 証明書の要求は、`DisableIdP` と同じく、次に使われたときに `institution not configured` で拒否されます（[管理 API]({{< relref "/authn-bridge/admin.md" >}})）。IdP を戻せば再び動作します |
| v0.23.8 | セキュリティ: [人は、その人自身として無効化されます]({{< relref "/authn-bridge/admin.md" >}})。ユーザー名 (無効化リスト、証明書のプリンシパル、subject-id) は go-authn/oidc v0.7.0 の `ASCIILower` で ASCII 文字だけを畳み込むので、`kate` とケルビン記号 (U+212A) を使った綴りは別の 2 人であり、無効化エントリも証明書のプリンシパルも 2 つになります |
| v0.23.9 | セキュリティ。go-authn/saml v0.6.0 とともに: [`schac_home_organization` が発行される]({{< relref "/authn-bridge/tokens.md" >}}) のは、トークンと userinfo で、表明する IdP の `shibmd:Scope` の値のいずれか (完全一致、大文字小文字を区別) である場合のみです。ある機関の IdP が別の機関のものを述べられ、このクレームで絞り込むサービス (ゲートウェイの `accept`) がその機関として受け入れていました。**アップグレード:** メタデータがそのドメインの Scope を公開していない IdP では、クレームは発行されなくなります |
| v0.23.10 | セキュリティ。[現在時刻に 3 分のクロックスキューを加えたものより後の `AuthnInstant`]({{< relref "/authn-bridge/federation.md" >}}) が、`max_age` の下で新しい認証として数えられていました (経過時間が負の値になっていました)。今は経過時間が不明として扱われ (OIDC Core 3.1.2.1)、古いものと同じく、その人は `ForceAuthn` 付きで IdP に送り返されます。スキューの範囲内では何も変わりません |
| v0.23.11 | [データベースが恒久的に拒否する状態の行が一つあっても、以降のフラッシュがすべて止まることはなくなりました]({{< relref "/authn-bridge/configuration.md#state-what-a-restart-must-not-forget" >}})。失効も含みます。削除は常に流れ、恒久的に拒否された行 (PostgreSQL SQLSTATE クラス 22 と 23、MySQL 1048、1062、1264、1265、1292、1366、1406、1452、SQLite の constraint、mismatch、too big) は一度だけログに記録され、新しい `bridge_state_rows_rejected_total{kind}` に数えられ、断念されます。メモリ上では動作し、再起動を越えて残りません |
| v0.23.12 | 分類器が知らないエラーで拒否された状態の行は、その行が失敗し続ける間にデータベースがほかのものを受け付けた、少なくとも 30 秒にわたる 5 回のフラッシュの後に断念されます。何も成功しないフラッシュ、つまりデータベースが不在の場合はどの行にも数えられないので、**障害は何も断念させません**。動作はドライバーのエラークラスの一覧に依存しなくなりました |

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
| v0.6.7 | 監査、ファジング、カオス、性能の実施 ([一回の同期で行うこと]({{< relref "/authn-revokd/configuration.md#sync" >}}))。失効するリストは次の更新ではなく失効した時点で拒否されます。ソースは並列で取得されます (最大 16、それぞれ二分)。`on_change` は一分後に強制終了されて再試行されます。エージェントの知らないところで変更された出力ファイルは次の同期で書き直されます。`file://` ソースは通常ファイルでなければなりません。エラーはパスワード、クエリ、フラグメントなしの URL を示します。`0..2^159` の範囲外の CRL 番号は拒否されます。ミラーには読み取り、書き込み、アイドルの期限があります。古い一時ファイルは起動時に削除されます。100,000 エントリの CRL を再度取得: 一回あたり 300,138 回のアロケーションと 96,956,946 B が、37 回と 4,776,864 B に (正確。時間は未測定、負荷 53 から 65)。govulncheck は今も GO-2026-5932 (`golang.org/x/crypto/openpgp`) を報告しますが、修正版はなく、呼び出されていません |
| v0.6.8 | セキュリティ。[検証できない状態のコピーは、順序の下限としてその位置を保ちます]({{< relref "/authn-revokd/verification.md#across-restarts-too" >}})。破損した、または別の CA 鍵で書かれた状態ファイルはコピーなしとして扱われていたので、再生された古いリストで、署名されていて期限も切れていないものが受け入れられ、新しいリストが失効させたものを元に戻していました。そのバージョンと発行時刻は、今は未検証のまま下限として保持され、下限を下回るリストは、検証に通り、かつそれに続くリストが保持されるまでロールバックとして拒否され、その内容が使われることは決してありません。CA が置き換えられ、そのリストがより低いバージョンから再開する場合、ログは削除すべきファイル `<source>.state` を示します |
| v0.7.0 | **コマンドは cobra になりました**。フリートのほかのコマンドと同じです。`--config`/`-c`、`--once`/`-o`、`--version`/`-v`、`--help`/`-h`、`--config=PATH`。`--help` は標準出力に出力します。[以前のリリースのシングルダッシュの綴り]({{< relref "/authn-revokd/_index.md" >}}) (`-config`、`-once`、`-version`、`-help`) は引き続き受け付けられ、フラグごとに標準エラー出力へ非推奨の行が一行出力され、後のリリースで削除されます。終了ステータスは変わりません。`packaging/` のユニットとインストールガイドは新しい綴りを使います。デプロイ済みのユニットは変更不要です。**アップグレード:** 古い綴りがなくなる前に、ユニットとスクリプトを `--config` と `--once` に移してください |

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
| directory v0.16.0 | [各グループを一度だけ読む]({{< relref "/libraries/directory.md" >}}): `GroupReader` と `Set.Frozen`。更新がグループ数とメンバーシップ行の積で増えなくなります |
| directory v0.17.0 | [`ErrUnavailable`]({{< relref "/libraries/directory.md#unavailable" >}})、`AsUnavailable` と `TransportFailure` を伴う: ldapdir は busy (51)、unavailable (52)、other (80)、timeLimitExceeded (3)、切れたり拒否された接続、接続や TLS の失敗に対して、`Verify` とすべての読み取りでこれを返します。`ErrWrongPassword` と同時に真になることはなく、`invalidCredentials` (49) は後者のままです。`ldaptest.Server.FailBindsWith(code)`。メンバーの DN は走査ではなく一回の検索で人に対応づけられ、結果は同じです。10,000 人と 50 DN ずつの 2,000 グループでの `ReadGroups` は、50.6 MB・2.20 M オブジェクトの代わりに 13.1 MB・0.38 M を確保し、DN の検索は 0 回、更新全体は 9.72 M の代わりに 7.17 M 回 (正確。時間は未測定、負荷 65 から 105) |
| directory v0.18.0 | [1 つのソースの 2 つのエントリが持つ同じ名前は `ErrAmbiguous`]({{< relref "/libraries/directory.md" >}}): ldapdir は uid を大文字小文字を区別せずに比較して両方の DN を示し、`Set.Identities` は 1 つのソースが 2 回挙げる名前を拒否します。ソースをまたぐ場合は最初のソースが名前を所有し続けます。`ldaptest.Person.UID`。このような重複のあるディレクトリは、直すまで読み込めません |
| directory v0.19.0 | [パスワードチェックを取り消せます]({{< relref "/libraries/directory.md" >}}): `directory.WithContextVerifier` と `Identity.VerifyContext(ctx, password)`。`ldapdir` の identity では、context が終了すると上流への接続が閉じられ、応答は `ErrUnavailable` になります (go-ldap には context も既定のタイムアウトもなく、受け付けても応答しない上流への bind は永久に待っていました)。チェックの接続確立も context の期限で終了します。`Verify` と `WithVerifier` は変わりません。**アップグレード:** チェックに上限を設けるサーバーは `VerifyContext` を呼ぶべきです |
| directory v0.20.0 | [すべてのクエリに期限がある]({{< relref "/libraries/directory.md" >}}): `sqldir.WithQueryTimeout(d)`。既定は `sqldir.DefaultQueryTimeout` (30 秒)、`0` は制限なし。行の読み取りも対象で、期限にドライバーが接続を切ります (以前は、応答しなくなったデータベースが読み取りを永久にブロックしました)。`hcldir.Block.QueryTimeout` (`sql` ブロックの `query_timeout`) がこれに届き、ネットワークなしで検査され、`ldap` ブロックでは拒否されます。`Source` インターフェースは変わりません。**アップグレード:** 30 秒を超えるクエリは失敗するようになります。より遅いクエリには `WithQueryTimeout` を指定してください |
| directory v0.21.0 | [`Set.GroupNames` は失敗したソースを報告します]({{< relref "/libraries/directory.md" >}}): 応答したソースの名前と、失敗した各ソースについての `"<describe>: <err>"` の `errors.Join` を返します (`errors.Is` は今も `ErrUnavailable` に一致)。以前は、ほかのソースが応答するとエラーは捨てられていました。**動作の変更:** `err != nil` だけを調べていた呼び出し側は、部分的な一覧を見ていたところでエラーを見ることになり、名前もそれとともに返ります。名前を使い、エラーをログに記録してください |
| fido v0.6.4 | [権限付きの `PINToken`]({{< relref "/libraries/fido.md" >}}) は、CTAP 2.1 (§6.5.5) の番号付けどおり、`permissions` をキー 0x09 で、`rpId` を 0x0A で送ります。以前は 0x07 と 0x08 を使っており、YubiKey 5 は `CTAP2_ERR_MISSING_PARAMETER` (0x14) を返しました |
| kdc v0.4.3 | 依存関係のみ: 最小バージョンとして go-authn/directory v0.12.0 |
| kdc v0.4.5 | セキュリティ監査、ファジング、カオスの実施 ([拒否するもの]({{< relref "/libraries/kdc.md" >}})): 別のレルム向けのリクエストは `KDC_ERR_WRONG_REALM`、読み取れないディレクトリは `KDC_ERR_SVC_UNAVAILABLE` で答えられ (以前は `KDC_ERR_C_PRINCIPAL_UNKNOWN`)、開始が `MaxSkew` 以内の未来にある TGT は受け入れられ、デコーダーのパニックはプロセスをクラッシュさせずリクエスト一つを破棄します (不正な AS-REQ または TGS-REQ 一つでクラッシュし得ました)。プリンシパル名はログで引用符で囲まれます。golang.org/x/net v0.62.0、go-authn/directory v0.16.1 |
| kdc v0.5.0 | MIT の KDC の [lookaside]({{< relref "/libraries/kdc.md" >}}): バイト単位で既に見たリクエストには以前の応答を返す (2 分間、合計 10 MiB 未満)。`KRB-ERROR` は保存しない。MIT が TGS で無効にしているオーセンティケータのリプレイキャッシュは意図的に持たない。テストは、読めないディレクトリが AS (正しいパスワードで) と TGS で `KDC_ERR_SVC_UNAVAILABLE` になることを固定する。リクエストあたりアロケーション 2 回増 |
| kdc v0.6.0 | [`Finder`]({{< relref "/libraries/kdc.md#finder" >}}): 名前による索引を持つソースには、走査せずに問い合わせる。10,000 人では走査が AS-REQ の CPU の半分だった。`Finder` があれば検索はプロファイルのしきい値を下回る。プリンシパルと名前が異なる応答は未知のプリンシパルとする (プリンシパルは大文字と小文字を区別する) |
| keyfactor v0.4.2 | 依存関係のみ: 最小バージョンとして go-authn/fido v0.6.2 と golang.org/x/crypto v0.58.0 |
| krb5 v0.3.1 | Go 1.27.2 でテスト。コードも `go.mod` も変更なし |
| krb5 v0.3.3 | 依存関係のみ: golang.org/x/net v0.62.0、golang.org/x/crypto v0.58.0、go-uuid v1.0.4 により、必要としていても呼び出していないモジュールでの `govulncheck` の 46 件中 45 件が解消されます。GO-2026-5932 (`x/crypto/openpgp`) には修正がなく、どの go-authn モジュールもインポートしていません。API の変更はありません |
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
| ldap v0.12.0 | [サーバーのリソース上限]({{< relref "/libraries/ldap.md" >}}): `Server.MaxConnections` と `Server.MaxConnectionsPerIP` (既定 0、無制限。上限を超えた接続には `busy` (51) の切断通知、RFC 4511 4.4.1 が送られて閉じられます)。`Server.Timeout` はサーバーが強制し、ハンドラーがブロックしてコンテキストを無視していても、期限にどの操作にも `timeLimitExceeded` (3) を返します (遅れた結果は捨てられ、ゴルーチンは戻るまで `MaxPending` と `MaxPendingAuth` に数えられます)。クライアントの検索 `timeLimit` はハンドラーのコンテキストに適用されます。ハンドラーの `DeadlineExceeded` は、その操作自身のコンテキストが期限切れのときだけコード 3 になります。操作あたりのアロケーション (正確): `Timeout` なしでは以前も以後も 3、ありでは以前 10、今 16 |
| ldap v0.12.1 | [bind は進行中のページング検索を中止します]({{< relref "/libraries/ldap.md" >}}) (RFC 4511 4.2.1)。ある人が始めた検索は、接続が匿名や別人のものになった後は結果を返し続けません |
| ldap v0.12.2 | `Validate` の重複値の検査は、すべての組を比較する代わりにキーで等しい値を見つけます。50 個の `member` DN を持つ `groupOfNames` は、14,907 アロケーションと 959 KB ではなく 1,065 と 68 KB です (正確)。結果は、ランダムなリストで比較した総当たりの検査と同じです |
| ldap v0.12.3 | 単純な DN (`type=value` の RDN、印字可能な ASCII、エスケープなし) は、そのバイトから 17 回ではなく 1 回のアロケーションでキーを得ます。それ以外の DN は完全な解析を通ります。50 個のグループあたり 265 アロケーション。キーは完全な解析のものと同じで、差分テストとファザー (3,900 万回の実行) で保証しています |
| oidc v0.4.1 | Go 1.27.2 でテスト。コードも `go.mod` も変更なし |
| oidc v0.6.1 | [`ScopedName`]({{< relref "/libraries/oidc.md#scoped-names" >}}) は `@` が 2 つ以上ある名前を拒否します（`ErrBadName`） |
| oidc v0.7.0 | [`ASCIILower` と `EqualASCIIFold`]({{< relref "/libraries/oidc.md#scoped-names" >}}): 名前のための ASCII だけの唯一の畳み込み。`strings.ToLower` と `strings.EqualFold` は Unicode を畳み込み、ケルビン記号 U+212A を "k" と同一視するためです |
| saml v0.6.0 | [`schacHomeOrganization` は IdP の `shibmd:Scope` の値に限られ]({{< relref "/libraries/saml.md" >}}) (完全一致、大文字小文字を区別)、そうでなければ破棄されます。`eduPersonPrincipalName`、`subject-id`、`pairwise-id`、スコープ付き所属がすでにそうだったのと同じです (SWITCH と SAFIRE の属性ページが依拠者に求めています)。**アップグレード:** メタデータがそのドメインの Scope を公開していない IdP の属性は、読まれなくなります |
| saml v0.6.1 | [四つのファズターゲットと悪意ある入力のテスト]({{< relref "/libraries/saml.md#fuzzing" >}}): `FuzzAccept`、`FuzzParseMetadata`、`FuzzDecrypt`、`FuzzLimits`。コーパスはコミットされ `go test` で再生され、それぞれ 110 万から 510 万回の実行でクラッシュ、ハング、性質の違反はありません。billion-laughs 爆弾、外部エンティティ、80,000 と 1,048,576 段の入れ子、60,000 個の兄弟要素、サイズ超過の `CipherValue` と応答は拒否され、割り当ては多くても 4 から 8 MiB です。CI の `fuzz` ジョブが各ターゲットを 30 秒実行します。動作の変更なし |
| scim v0.2.0 | [監査、ファジング、カオス、性能の実施]({{< relref "/libraries/scim.md#v020" >}}): `Server.ReadTimeout` (30 秒)、省略可能な `ConditionalDeleter`、`If-Match` なしの PATCH または PUT は競合に負けても 412 ではなく最大 32 回やり直し、何にも一致しないフィルターでの削除は成功し、パスなしの PATCH のキーはソート順に適用され、`BearerAuth` はスキームを大文字小文字を問わず受け入れ、`startIndex` と `count` はワード幅にかかわらず丸められます。10,000 ユーザーに対するリスト要求: 100 件のページは 789,417 回から 14,952 回、`userName eq` は 797,979 回から 90 回、全走査は 818,847 回から 361,098 回 (正確。時間は未測定、負荷 65) |
| scim v0.2.1 | [RFC 7232 §3.2 に従う `If-None-Match`]({{< relref "/libraries/scim.md#v021" >}}): エンティティタグの一覧、`*`、弱い比較、304 は `ETag` を伴います。`Memory` は索引で `userName` の一意性を確認します (N 人の読み込みが O(N^2) 回ではなく O(N) 回の `EqualFold` 呼び出し)。どの索引も答えられないリストのフィルターは、それが名指しするトップレベルの属性で照合されます。10,000 ユーザーで一回のリクエストあたり 361,095 回から 162,695 回のアロケーション、ユーザーあたり 36.1 から 16.3 (正確) |
| servercert v0.5.2 | Go 1.27.2 でテスト。コードも `go.mod` も変更なし |
| servercert v0.6.0 | [TLS の `KeyFile` と ACME の `EABHMACKeyFile` は拒否されます]({{< relref "/libraries/servercert.md" >}})。グループまたはその他のユーザーが読み書きできる場合で、`New` 時とリロードのたびに確認されます (読み取り可能な差し替え鍵は `OnError` に報告されて採用されず、現在の証明書が提供され続けます)。Windows では確認しません。**アップグレード:** 両方のファイルを `chmod 600` |
| totp v0.4.2 | Go 1.27.2 でテスト。コードも `go.mod` も変更なし |
| wireguard v0.1.1 | Go 1.27.2 でテスト。コードも `go.mod` も変更なし |
| wireguard v0.1.4 | ソースのトークン要求とリスト要求は Basic のシークレットまたは Bearer トークンを運ぶため、リダイレクトに従わなくなりました。リダイレクトはエラーです（[拒否するもの]({{< relref "/libraries/wireguard.md" >}})） |

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
