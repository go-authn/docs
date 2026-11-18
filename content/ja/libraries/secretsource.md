---
title: "secretsource — 参照からシークレットを取得する"
linkTitle: "secretsource"
weight: 35
description: "go-authn/secretsource は、PIN・パスワード・リカバリーコードを参照 (ファイル、macOS キーチェーン、Secret Service、KeePassXC) から取得し、平文のファイルをディスクに残さずに済ませます。"
tags: [ライブラリ, secretsource, シークレット]
---

**ファイルに置きたくない PIN は、どこから取得するのか。** **参照**はシークレットの
所在を示し、`secretsource.Open` がそれを取得します。参照自体はシークレットを
含まないので、フラグ、スクリプト、シェルの履歴に書いても構いません。

```sh
go get github.com/go-authn/secretsource@v0.3.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| 参照 | 読み取るもの |
|---|---|
| `file:PATH` | 所有者だけが読める通常ファイル (モード 0600 以下)。末尾の改行 1 つは取り除かれます |
| `keychain:SERVICE/ACCOUNT` | macOS キーチェーンの汎用パスワード項目 |
| `secretservice:SERVICE/ACCOUNT` | 属性 `service=SERVICE`、`account=ACCOUNT` を持つ freedesktop Secret Service の項目 (GNOME Keyring、KWallet、KeePassXC の Secret Service 連携) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | それらすべての属性を持つ唯一の Secret Service 項目。複数一致は拒否されます |
| `keepassxc:URL` | **URL フィールド**がその URL である KeePassXC のエントリ (`https://NAME.invalid/...` は、名前解決されることのない良い選択です)。同じ URL のエントリが 2 つあると曖昧として拒否されます |

`keepassxc:by-uuid/...` と `keepassxc:by-path/...` は**拒否されます**:
KeePassXC 2.8.0 は、検索が URL のないエントリを見つけるとクラッシュします。

**コマンドを実行するスキームはありません**: フラグがプロセスを起動できては
ならないからです。スキームのない参照は、パスと推測されずに拒否されます
(パスは `file:` で書きます)。4096 バイトを超えるシークレットや、マネージャーから
の空のシークレットは拒否されます。呼び出しはそのコンテキスト (期限がなければ
2 分) で終わり、マネージャーがロック解除を待っていても同じです。

## KeePassXC {#keepassxc}

KeePassXC には、そのブラウザー連携プロトコルで接続します (macOS と Linux。
Windows は未実装です)。

1. KeePassXC で *Settings > Browser Integration* を有効にします。
2. データベースごとに 1 回、このマシンを関連付け、KeePassXC で承認します:
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. エントリを作成し、その **URL フィールド**に `https://fido.invalid/yubikey-5c`
   を入力します (他のエントリが使っていない任意の URL。参照はその URL です)。
   シークレットを表示せずに参照を確認します:
   ```sh
   secretsource check 'keepassxc:https://fido.invalid/yubikey-5c'
   ```

エントリの最初の読み取りで、KeePassXC のアクセス確認ダイアログが表示されます。

`fido --pin-from` ([fido]({{< relref "/libraries/fido.md" >}}) を参照) と、
`theca --pin-from`、`--password-from`、`--recovery-from` が使用します。

## リファレンス {#reference}

このページの根拠は
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) の
README です。
