---
title: "sdcreds — 无需 systemd 的 systemd 凭据"
linkTitle: "sdcreds"
weight: 37
description: "go-authn/sdcreds 可在 Go 中读写 systemd 凭据格式（systemd-creds encrypt 和 decrypt），并提供命令行和一个 s6 辅助工具，为受监管的服务提供其 $CREDENTIALS_DIRECTORY。"
tags: [libraries, sdcreds, secrets, s6]
---

**如果服务需要 systemd 单元通过 `LoadCredentialEncrypted=` 获得的凭据，而系统上没有 systemd，该怎么办？** `sdcreds` 可在 Go 中读写
[systemd 凭据](https://systemd.io/CREDENTIALS/)格式
（`systemd-creds encrypt` / `decrypt`），并提供命令行和一个辅助工具，为由 s6
监管的服务提供同样的 `$CREDENTIALS_DIRECTORY`。

支持的密钥：**null**、**host**（`/var/lib/systemd/credential.secret`）和
**host-scoped**（`--uid` / `--user`）。TPM2 和公钥凭据会被识别并以
`*UnsupportedModeError` 拒绝；不做任何猜测。

## 安装 {#install}

```sh
go install github.com/go-authn/sdcreds/cmd/sdcreds@latest
```

这些页面所描述的版本是 v0.1.0。

## 命令行 {#cli}

```sh
sdcreds setup                                  # create the host secret if missing
sdcreds encrypt --name=db-password plain.txt db-password.cred
sdcreds decrypt db-password.cred -             # the name must match the file name
```

在 Go 中的相同操作：

```go
host := sdcreds.HostKeyFile{} // $SYSTEMD_CREDENTIAL_SECRET or the default path
blob, err := sdcreds.Encrypt(secret, sdcreds.EncryptOptions{Key: sdcreds.IDHost, HostKey: host, Name: "db-password"})
text := sdcreds.Armor(blob, sdcreds.ArmorWidth) // what systemd-creds prints
raw, _ := sdcreds.Unarmor([]byte(text))
plain, md, err := sdcreds.Decrypt(raw, sdcreds.DecryptOptions{HostKey: host, Name: &name})
```

## s6 {#s6}

```sh
sdcreds s6-run --service=web --user=svc --source=/etc/creds -- /usr/bin/web
```

`s6-run` 会在挂载任何东西**之前**解密 `--source` 中的每个文件，挂载一个每个服务独立的
`tmpfs`（`nodev,noexec,nosuid,nosymfollow,noswap`，权限 0700，大小和 inode 数量均有上限；
若内核没有这些选项则使用 `ramfs`），以 0400 权限、属主为服务用户写入明文，将其重新以只读方式挂载，
设置 `CREDENTIALS_DIRECTORY`，然后在一个会放弃特权（`no_new_privs`、空的能力集）的子进程中
启动服务并等待它结束。

- `s6-run` 仍然是 s6 所监管的进程：它把 `TERM`、`INT`、`HUP`、`QUIT`、`USR1`、
  `USR2`、`ALRM` 和 `CONT` 转发给服务，以服务的状态退出（若被信号终止，则为 128 加信号编号），
  传递它收到的文件描述符，并且在 `s6-run` 死亡时服务会被终止。
- 凭据会在服务结束时被清除，若程序无法执行，则在 `s6-run` 失败之前清除。
- 挂载默认位于私有命名空间中（`--unshare=false` 可将其关闭），因此会随服务一同消失。
- 用 null 密钥封存的凭据会被拒绝，除非给出 `--allow-null`；不带名称的凭据则始终被拒绝。
- `sdcreds s6-finish --service=web` 会延迟卸载并删除该目录；它是幂等的。使用 `--unshare=false`
  时，对 `s6-run` 发送 `SIGKILL` 会使挂载一直保留到 `s6-finish` 运行：请把它放进服务的 finish 脚本。
- 每个服务最多 1024 个凭据和 16 MiB。仅限 Linux；在其他系统上，这些命令报告 `ErrUnsupported`。

由 `--secret` 和 `--machine-id-file` 指定的密钥文件必须属于 root，且组和其他用户不可写，
从它们向上直到 `/` 的每一级目录同样如此。密钥文件只打开一次，不跟随末尾的链接，
并且密钥会在 `s6-run` 处理完凭据后从其内存中擦除。只有子进程会采用服务的身份；
`s6-run` 及其所有线程仍然保持 root。

## 互操作性 {#interop}

两个方向都针对真实的 `systemd-creds` **262.2** 进行了测试，它由 `v262.2` 标签构建
（不使用发行版软件包）。

- `testdata/systemd-v262.2` 包含由 systemd-creds 写入的 44 个凭据（null、host 和 host-scoped；
  有名称和无名称；无 not-after、过去和未来的 not-after；0 B、1 B 和 64 KiB 的负载；
  五个被篡改的变体），`manifest.json` 记录了 systemd-creds 自己对 272 次解密尝试
  （正确和错误的名称、not-after 之前和之后、带和不带 `--uid`）的每一次所给出的回答。
  对于每一次，该库都给出相同的回答，并且错误类别也相同。
- 在固定 IV 的情况下，`Encrypt` 能精确复现 systemd 的字节。
- 在容器中，`systemd-creds decrypt` 能打开 `Encrypt` 写出的内容，命令行在两个方向上
  也都通过了同样的往返测试。

```sh
docker build -t sdcreds-interop docker
docker run --rm --privileged -e SDCREDS_REQUIRE_SYSTEMD=1 -e SDCREDS_S6_INTEGRATION=1 \
  -v "$PWD":/src/sdcreds -w /src/sdcreds sdcreds-interop \
  sh -c 'echo 0123456789abcdef0123456789abcdef > /etc/machine-id && go test -count=1 ./...'
```

未设置 `SDCREDS_REQUIRE_SYSTEMD=1` 时，需要该二进制文件的测试会被跳过；CI 会设置它，
因此在 CI 中缺少该二进制文件即为失败。1 MiB 的边界仅由库测试覆盖，而不是由互操作向量覆盖。

## 与 systemd 的差异 {#deviations}

- 机器 ID 不匹配的主机密钥会被**拒绝**（`ErrHostKeyMachine`）；systemd 则会将其删除。
- `--with-key=auto` 表示 `host`：这里没有 TPM2。
- 用 null 密钥封存的凭据没有保密性：除非给出 `--allow-null`，`sdcreds decrypt` 在任何机器上
  都会拒绝它（systemd 则会查询 TPM2 和 SecureBoot 的状态；该库策略 `SystemNullPolicy`
  不被 CLI 使用）。
- `SDCREDS_MACHINE_ID_FILE`（`encrypt`、`decrypt`、`setup`）指向另一个机器 ID 文件。
  `s6-run` 会忽略它以及 `SYSTEMD_CREDENTIAL_SECRET`：其密钥来自默认文件，或来自
  `--secret` 和 `--machine-id-file`。
- 读取时接受可变的 IV 大小，与 systemd 一致；该库写入时始终为 12 字节。
- 打开密钥时不跟随末尾的符号链接，并且它必须是只有一个链接、权限为 `0400` 的常规文件，
  这与 systemd 的要求相同。

## 安全 {#safety}

每个长度在使用之前、在分配任何内存之前都会被检查，并且在其边界的两侧都会检查；凭据被限制为
1 MiB（与 systemd 相同），主机密钥被限制为 16 MiB。解析器在 CI 中进行模糊测试，语料库已提交，
并且 `govulncheck` 在 CI 中运行。README 目前还没有性能表：测量被推迟，是一个未决事项，而不是结果。

## 参考 {#reference}

[github.com/go-authn/sdcreds](https://github.com/go-authn/sdcreds) 的 README 是本页面的权威来源。
请参见该模块的 `LICENSE`。
