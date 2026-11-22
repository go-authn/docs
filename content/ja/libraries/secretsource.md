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
go get github.com/go-authn/secretsource@v0.7.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| 参照 | 読み取るもの |
|---|---|
| `file:PATH` | 所有者だけが読める通常ファイル (Unix: モード 0600 以下。Windows (v0.7.0 以降): 所有者、SYSTEM、Administrators グループ以外に読み取りや書き込みの権利を与えないアクセスリスト)。末尾の改行 1 つは取り除かれます。空のファイル、または行末だけを含むファイルは `ErrEmpty` で拒否され (v0.6.0 以降)、FIFO は通常ファイルではないとして拒否されます |
| `keychain:SERVICE/ACCOUNT` | macOS キーチェーンの汎用パスワード項目 |
| `secretservice:SERVICE/ACCOUNT` | 属性 `service=SERVICE`、`account=ACCOUNT` を持つ freedesktop Secret Service の項目 (GNOME Keyring、KWallet、KeePassXC の Secret Service 連携) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | それらすべての属性を持つ唯一の Secret Service 項目。複数一致は拒否されます |
| `keepassxc:URL` | **URL フィールド**がその URL である KeePassXC のエントリ (`https://NAME.invalid/...` は、名前解決されることのない良い選択です)。同じ URL のエントリが 2 つあると曖昧として拒否されます |

`keepassxc:by-uuid/...` と `keepassxc:by-path/...` は**拒否されます**:
KeePassXC 2.8.0 は、検索が URL のないエントリを見つけるとクラッシュします。

**コマンドを実行するスキームはありません**: フラグがプロセスを起動できては
ならないからです。スキームのない参照は、パスと推測されずに拒否されます
(パスは `file:` で書きます)。4096 バイトを超えるシークレットや、マネージャーから
または `file:` からの空のシークレットは拒否され (`ErrEmpty`)、呼び出しはそのコンテキスト (期限がなければ
2 分) で終わり、マネージャーがロック解除を待っていても同じです。

## KeePassXC {#keepassxc}

KeePassXC には、そのブラウザー連携プロトコルで接続します (macOS と Linux。
Windows は未実装です)。v0.6.0 以降、Unix では、ソケットがシンボリックリンクである場合、またはその
ディレクトリが別のユーザーの所有であるか、グループまたはその他に書き込み可能な場合にソケットは拒否され、
接続したピアの uid がダイヤルの後に確認されます。従来の
`$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer` シンボリックリンクはもう辿られません
(`app/org.keepassxc.KeePassXC/` 配下の実際のソケットは辿られます)。

v0.6.1 以降、関連付けファイル (macOS のキーチェーンも Secret Service もないときに使うフォールバックの
保存先) は、同じディレクトリ内の新しい一時ファイルに書き込まれてから最終的な名前の上へ rename されます。
そのため、その名前に残されたシンボリックリンクは、辿られるのではなく置き換えられ、モードが緩いファイルは
0600 になります。Unix ではまずディレクトリが、ソケットのものと同様に検査されます: このユーザーの所有で、
グループにもその他にも書き込み不可で、シンボリックリンクでないこと。そうでなければ何も書き込まれません。

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

## シークレットを保存する: `secretsource store` {#store}

エントリを手で作る必要はありません。`secretsource store REF [--group G]
[--login L] [--replace] [--generate N]` は、`keychain:`、
`secretservice:SERVICE/ACCOUNT`、`secretservice:KEY=VALUE`、`keepassxc:URL` に
シークレットを書き込みます:

```sh
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c'
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c' --generate 24
printf '%s' "$PIN" | secretsource store keychain:fido/yubikey-5c
```

シークレットはエコーなしで 2 回入力するか、標準入力がターミナルでなければそこから
読み取ります。引数や環境変数からは決して取りません。`--generate N` は N 文字の
英数字を生成し、秘密の内容は何も表示しません。既存のエントリは `--replace` が
ない限り拒否されます (KeePassXC では、URL で見つけたそのエントリを更新します)。
`file:` は拒否されます。

`keepassxc:` ではブラウザープロトコルの `set-login` を使うため、エントリは常に
それを再び見つけるための URL を持ち、重複は URL で調べます。ログインの既定は
URL のホスト (`--login`)、グループは、ルート直下の名前を `--group` で指定しない限り
`KeePassXC-Browser Passwords` で、`--title` は KeePassXC 2.8.0 が無視するため
拒否されます。KeePassXC は独自のダイアログを表示します。

## リファレンス {#reference}

このページの根拠は
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) の
README です。
