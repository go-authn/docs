---
title: "人员更改自己的密码"
linkTitle: "更改密码"
weight: 50
description: "authnd 接受的唯一一种写操作：人员自己的密码，通过 RFC 3062 或 RFC 4511 modify，始终需要旧密码，并写回声明该人员的文件。"
tags: [authnd, 密码, ldappasswd]
---

人员可以通过 RFC 3062 密码修改操作（`ldappasswd` 所发送的）或 RFC 4511
modify 更改**自己的**密码，而不能更改任何其他人的。在两种方式中，**都必须随新密码一起发送
当前密码，无论连接是以什么方式绑定的**。否则，以
[OAUTHBEARER 令牌]({{< relref "/authnd/tokens.md" >}})绑定的会话——生命周期很短，
而且可能只有一个因素——就能把它变成一个同样适用于 `kinit` 的
永久密码。

这是 OpenLDAP 的 ppolicy 在设置 `pwdSafeModify` 时的行为，
所用结果代码与其 `ppolicy.c` 返回的相同。RFC 3062 §3 允许这样做：“If oldPasswd is
not present, the server MAY use other policy to determine whether or not to
change the password.”

## 使用 `ldappasswd` {#with-ldappasswd}

`-t` 是保存旧密码的文件，`-T` 是保存新密码的文件；`-A` 和
`-S` 则改为提示输入。

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -T alice.new
Result: Insufficient access (50)
Additional info: a password change must send the old password with the new one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t wrong.pwin -T alice.new
Result: Server is unwilling to perform (53)
Additional info: the old password sent is not the current one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.new
dn:uid=alice,ou=people,dc=example,dc=org
```

旧密码立即失效，对绑定如此，对 `kinit` 也是如此——只要有
[域]({{< relref "/authnd/kerberos.md#a-password-changed-over-ldap" >}})。
服务器会在其输出中说明：

```
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password
```

authnd 不会生成密码：没有新密码的请求会被拒绝，
返回 `unwillingToPerform`（*this server does not generate passwords: send the
one you want*）。它自己生成的密码必须通过
连接发回，而它必然最终出现的地方就是终端的
滚动缓冲区。

## 使用 `ldapmodify` {#with-ldapmodify}

更改是**在一个请求中先删除旧值，再添加新值**。
RFC 4511 §4.6 按顺序且原子地应用 modify 的更改，因此除非
所删除的值就是当前持有的值，否则删除——连同整个请求——都会失败：

```
dn: uid=alice,ou=people,dc=example,dc=org
changetype: modify
delete: userPassword
userPassword: alice-test-pw
-
add: userPassword
userPassword: alice-new-pw
-
```

单纯的 `replace` 什么也证明不了，而 `userPassword` 之外的任何内容
此服务器都不会更改：

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f replace.ldif
ldap_modify: Insufficient access (50)
	additional info: a password change must send the old password with the new one
modifying entry "uid=alice,ou=people,dc=example,dc=org"

$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f other.ldif
ldap_modify: Server is unwilling to perform (53)
	additional info: this server changes userPassword and nothing else, not cn
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

要求更改密码**并且**更改其他内容的 modify 会被整体拒绝：
modify 是原子的，只满足其中一半就会为
无人要求的事情报告成功。

## 谁可以更改什么 {#who-can-change-what}

| 请求 | 答复 |
|---|---|
| 没有旧密码，或单纯的 `replace: userPassword` | `insufficientAccessRights` |
| 不是当前密码的旧密码 | `unwillingToPerform` |
| 别人的条目 | `insufficientAccessRights`，*a password may be changed only by the person it belongs to* |
| 匿名连接 | `insufficientAccessRights`，*an anonymous connection has not said who it is* |
| 完全没有密码的人——他们只可能通过令牌绑定 | `unwillingToPerform`：持有者令牌不是密码，也不能设置第一个密码。由管理员在配置中设置 |
| 由 `users` 块提供服务的人 | `unwillingToPerform`：authnd 读取这些来源，但不写入它们 |
| 文件无法写入 | `other`（80），*the password could not be written*；原因在服务器的输出中 |

倒数第二项，取自发布的二进制文件，针对来自
SQLite 数据库的 dora：

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=dora,ou=people,dc=example,dc=org -y dora.pwin -t dora.pwin -T dora.new
Result: Server is unwilling to perform (53)
Additional info: dora is served from a sqlite database, which this server reads and does not write
```

人员是**按身份匹配的，而不是按 DN**：会话自己的名称必须
与目标逐字节完全一致，因此以 `uid=Backup` 绑定的会话
不能更改 `backup` 的密码，即使这两个 DN 比较时相等。这一点与
[拒绝仅大小写不同的名称]({{< relref "/authnd/people.md#order-and-the-one-exception" >}})
是两项互不依赖的控制。

## 新密码写在哪里 {#where-the-new-password-is-written}

写回**声明该人员的文件**，不写到其他任何地方：

- 带有 `password_file` 的 `user` 块会重写**该文件**，在进程可以做到的范围内保留
  其所有者和组，并把权限收窄到
  至多 0600——绝不放宽；
- 内联写有 `password` 的 `user` 块会重写配置文件，
  写入新值，保留其注释、顺序和权限；
- 只有 `nt_hash` 的 `user` 块不会获得密码：那会
  改变能够证明其身份的内容，而这是对配置的更改。

每次写入都先写到**同一目录中**的临时文件，然后
重命名——因此磁盘已满或崩溃时留下的是旧密码，而不是空
文件。这需要对该目录的写权限。在打包提供的单元下，
`ProtectSystem=strict` 会取消它，更改会像这样被拒绝：

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f safe.ldif
ldap_modify: Other (e.g., implementation specific) error (80)
	additional info: the password could not be written
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

原因在服务器的输出中：

```
changing the password for alice: etc/authnd/passwords/alice.pw: open etc/authnd/passwords/.hcldir-1822988247: permission denied
```

因此请把密码保存在单独的目录中，使服务可以写入，
而配置对它保持只读——即
[`ReadWritePaths=` drop-in]({{< relref "/authnd/install.md#the-configuration-directory" >}})。
密码内联写入的人员需要 `/etc/authnd` 本身
可写，而这也会让服务能够重写自己的配置。

写入成功之后，**仅针对 `user` 块**重新读取配置文件：
磁盘上等待生效的无关修改不会因为有人
更改了密码而中途生效。其他一切仍然等待
重启。不过这些文件仍然会被整体读取，因此如果其中一个
无法再加载，密码已经写入，客户端会被告知 *the password
was written but this server did not reload it*——运行中的服务器在重启之前
仍保留旧密码。
