---
title: "인증서"
linkTitle: "인증서"
weight: 50
description: "authn-bridge가 서명하는 SSH 사용자 인증서, 그 EuroHPC Federation Platform 프로필, 그리고 NFS over TLS용으로 발급하는 X.509 클라이언트 인증서."
tags: [authn-bridge, ssh, x509, eurohpc]
---

로그인한 사람은 몇 시간 동안 SSH 공개 키를 인증받거나 X.509 클라이언트 인증서를
발급받을 수 있습니다. 공급자의 CA를 신뢰하는 서버는 그곳에서 편집할 계정 파일 없이
그들을 들여보냅니다. 모든 인증서는 **전달되기 전에 `certificates_file`에 기록됩니다.**
기록할 수 없는 인증서는 폐기할 수 없으므로 발급되지 않으며, 폐기된 인증서는
[KRL과 CRL]({{< relref "/authn-bridge/revocation.md" >}})에 게시됩니다.

## SSH 인증서 {#ssh-certificates}

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

ssh_ca {
  key_file = "/var/lib/authn-bridge/ssh-ca"   # authn-bridge keygen --ssh-ca; Ed25519
  validity = "12h"                            # the default; a week at most
}

client "sftp" {
  device           = true
  ssh_certificates = true
}
```

`authn-bridge ssh-cert --issuer https://login.example.org --client sftp`는 코드로
로그인하고, `ssh` 스코프의 토큰과 함께 `~/.ssh/id_ed25519.pub`(또는 `--key`)를
`/ssh/certificate`에 보내며, `ssh`와 `sftp`가 찾을 수 있는 그 옆에
`<key>-cert.pub`을 기록합니다.

CA 키는 Ed25519여야 합니다. RSA CA 키는 별도 지시가 없으면 SHA-1로 서명하는데,
OpenSSH는 8.8부터 기본적으로 이를 거부합니다.

**인증서가 말하는 것.**

- **정확히 하나의 principal**: 클라이언트의 프로필이 다른 클레임을 지정하지 않는 한
  그 사람의 `preferred_username`입니다. principal이 없는 인증서는 *모든* 사용자에게
  유효하므로(PROTOCOL.certkeys), 사용자 이름이 없는 사람은 인증서를 받지 못합니다.
  쉼표, 공백, 따옴표, 백슬래시 또는 제어 문자를 포함한 이름은 거부됩니다(`403`).
  `sshd`가 `principals="a,b"`와 `AuthorizedPrincipalsFile` 항목을 목록으로 읽으므로
  그런 이름 하나가 둘이 되기 때문입니다.
- **Key ID** `<principal> sub=<sub> jti=<token id>`: `sshd`가 기록하는 것입니다.
- 기본적으로 **`permit-*` 확장 없음**. SFTP에는 필요하지 않으며, pty도 포워딩도 rc
  파일도 허용하지 않는 인증서는 파일 접근만 허용합니다.
- 토큰이 그룹을 담고 있으면 `groups@go-authn.org` 확장에 **그 사람의 그룹**이 한
  줄에 하나씩 들어갑니다. OpenSSH는 이를 무시합니다. 이는 서명되어 있으므로 그룹으로
  권한을 부여하는 서버는 이를 믿을 수 있습니다.
- **유효 기간**은 5분 전부터(시계가 맞지 않는 경우를 위해) 지금부터 `validity`까지,
  또는 IdP의 세션이 그보다 먼저 끝나면 그때까지입니다.
- **키**는 Ed25519, ECDSA P-256/384/521, 보안 키(`sk-`), 또는 2048비트 이상의 RSA여야
  합니다. 인증서를 키로 제시하면 거부됩니다.

## EuroHPC SSH CA 프로필 {#the-eurohpc-ssh-ca-profile}

EuroHPC Federation Platform의 SSH CA(GÉANT / MyAccessID)는 한 시간 동안 유효한
Ed25519 인증서를 발급하며, 페더레이션 전체에서 그 사람을 지명하는 principal 하나와,
GÉANT의 `ssh-domain-grant@core.aai.geant.org` 확장에 인증서가 대상으로 하는 호스트를
담습니다. 클라이언트는 그 형태로 인증서를 발급받을 수 있습니다. 모든 키는 클라이언트별
선택 사항이며, 아무것도 설정하지 않은 클라이언트는 위의 인증서를 받습니다.

```hcl
client "efp" {
  device              = true
  ssh_certificates    = true
  ssh_principal_claim = "voperson_id"               # the default is preferred_username
  ssh_validity        = "1h"                        # never longer than ssh_ca's, nor the IdP's session
  ssh_extensions      = ["permit-pty"]              # none by default
  ssh_domain_grants   = ["login.hpc.example.org"]   # the hosting entity's hosts
  # ssh_source_address = ["192.0.2.0/24"]           # the source-address critical option
}
```

| 키 | |
|---|---|
| `ssh_principal_claim` | `preferred_username`, `sub`, `voperson_id` 또는 `eduperson_principal_name`. 마지막 둘은 `eduperson` 스코프가 내주며 토큰이 이를 가지고 있어야 합니다(`authn-bridge ssh-cert --scope eduperson`). 그렇지 않거나 IdP가 그런 속성을 내주지 않으면 어느 쪽인지 알려 주는 `403`이 응답됩니다 |
| `ssh_extensions` | `permit-pty`, `permit-user-rc`, `permit-port-forwarding`, `permit-agent-forwarding`, `permit-X11-forwarding` 중에서 |
| `ssh_source_address` | 주소 또는 CIDR 접두사, `source-address`에 표준 형식으로 기록됨 |
| `ssh_validity` | 이 클라이언트에 대해 `ssh_ca`의 `validity`보다 길지 않음(같은 값은 허용) |
| `ssh_domain_grants` | 도메인 패턴으로, [go-authn/sshcert]({{< relref "/sshcert/_index.md" >}})의 `ValidatePattern`으로 검사하고 `EncodeDomainGrant`로 인코딩함 |

### 프로필이 거부하는 것 {#what-the-profile-refuses}

각각 시작할 때 `authn-bridge check`가 출력합니다.

```
authn-bridge: client "efp": ssh_validity = 24h0m0s: longer than the ssh_ca validity, 12h0m0s
authn-bridge: client "efp": ssh_extensions: "no-touch-required" is not one of permit-X11-forwarding, permit-agent-forwarding, permit-port-forwarding, permit-pty, permit-user-rc
authn-bridge: client "src": ssh_source_address: "192.0.2.1/24" has bits set under its mask: 192.0.2.0/24?
authn-bridge: client "x": ssh_principal_claim, ssh_extensions, ssh_source_address, ssh_validity and ssh_domain_grants shape SSH certificates: they need ssh_certificates = true
```

`no-touch-required`는 제공되지 않습니다. 이는 그 사람 **자신의** 보안 키에 대한
사용자 존재 확인을 면제하는 것이며, 클라이언트의 모든 사람을 위해 공급자가 내줄 수
있는 것이 아닙니다.

도메인 권한 부여는 먼저 사양의 문법에, 그다음 이 공급자 자신의 정책에 맞아야
합니다. 소문자, 레이블 두 개 이상, 그리고 등록 가능한 도메인 아래에서만 와일드카드.
마지막 와일드카드 오른쪽에 고정된 부분은 공개 접미사(Public Suffix List)여서는 안
됩니다. `*.ac.uk`는 그 아래의 모든 기관에 권한을 부여하게 됩니다.

```
authn-bridge: client "efp": ssh_domain_grants: "*.ac.uk": a wildcard over the public suffix "ac.uk" grants every domain under it
authn-bridge: client "efp": ssh_domain_grants: "Login.hpc.example.org": written in lower case, as hosting entities' domains are compared
authn-bridge: client "efp": ssh_domain_grants: "login.hpc.*": sshcert: invalid domain pattern: pattern "login.hpc.*" has a wildcard in its rightmost label
```

### 사이트에서 신뢰하기 {#trusting-it-from-a-site}

`GET /ssh/config`는 EFP가 자신의 것을 게시하는 형태로 CA 키를 게시하므로, 사이트는
이 공급자의 URL로 EFP의 신뢰 지침을 따르면 됩니다.

```
$ curl -s http://127.0.0.1:28473/ssh/config
{"PublicKey":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNOYvUrAPdRTB+38aml+twPN+2k1shD3l62v8NxrIje"}
```

```sh
curl -s https://login.example.org/ssh/config | jq -r '.PublicKey' > /etc/ssh/bridge-ssh-ca.pub
echo "TrustedUserCAKeys /etc/ssh/bridge-ssh-ca.pub" >> /etc/ssh/sshd_config
```

sshd는 도메인 권한 부여를 무시합니다. 사이트는 `AuthorizedPrincipalsCommand`로
이를 기준으로 걸러 냅니다.
[sshcert-authorize]({{< relref "/sshcert/authorize.md" >}})는 권한 부여가 호스트를
지정하지 않는 인증서와 권한 부여가 아예 없는 인증서를 거부합니다. CA는 OpenID
디스커버리 문서에 없습니다. 어떤 OpenID Connect 메타데이터도 SSH CA를 지정하지
않습니다.

EFP 자체 CA와 여전히 다른 점: 위에서처럼 `ssh_principal_claim = "voperson_id"`이면
principal은 사람의 기관이 내준 `subject-id`를 소문자로 한 것이며 MyAccessID
식별자가 아닙니다. 토큰이 그룹을 담고 있으면 그룹 확장이 있습니다. 그리고 **KRL이
있습니다.** `GET /ssh/krl`이 여기서 비활성화된 사람들의 인증서를 나열합니다.

## NFS over TLS용 X.509 클라이언트 인증서 {#x509-client-certificates-for-nfs-over-tls}

NFS over TLS(RFC 9289)는 클라이언트를 인증서로 지명할 수 있습니다.

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

x509_ca {
  key_file  = "/var/lib/authn-bridge/nfs-ca/ca.key"   # authn-bridge keygen --x509-ca /var/lib/authn-bridge/nfs-ca
  cert_file = "/var/lib/authn-bridge/nfs-ca/ca.crt"   # what go-fileshare trusts
  validity  = "12h"                                   # the default; a week at most
}

client "nfs" {
  device            = true
  x509_certificates = true
}
```

`authn-bridge nfs-cert --issuer ... --client nfs`는 그 사람의 머신에서 P-256 키를
만들고, `nfs` 스코프의 토큰과 함께 인증서 요청을 `/x509/cert`에 보내며, 인증서와
키를 기록합니다. CA 키는 P-256이어야 하고, 그 인증서는 인증서와 CRL에 서명하는
CA여야 합니다.

**인증서가 말하는 것.** 요청의 subject와 확장은 무시됩니다. 인증되는 것은 그 사람이
요청한 것이 아니라 토큰의 사람입니다.

- 사람, `user@domain`은 UTF8String을 담은 **하나의** subjectAltName `otherName`
  `1.3.6.1.4.1.2238.1.1.1`로 들어가며, FreeBSD의 `rpc.tlsservd -u`가 이를 읽는
  곳입니다. `@`가 없거나 3바이트 미만인 사용자 이름은 거부됩니다.
- 각 그룹은 그 옆에 URI 이름으로:
  `tag:go-authn.github.io,2026:group:<the group, percent-encoded>`.
- CN은 사용자 이름이며, 64자를 넘으면 subject는 비고 subjectAltName은 critical이
  됩니다(RFC 5280).
- 클라이언트 인증 전용이며 CRL 배포 지점은 `<issuer>/x509/crl`입니다.
- 5분 전부터 `validity`, IdP의 세션, CA 자체의 인증서 중 먼저 끝나는 때까지
  유효합니다.
- P-256 또는 RSA(2048비트 이상) 키와 그 키로 서명한 요청.

{{< callout type="warning" >}}
**인증서는 머신을 지명하며, 그것을 쓰는 사용자를 지명하지 않습니다**

RFC 9289: 서버는 "cannot utilize the remote TLS peer identity to authenticate RPC
users". Linux는 마운트별로 클라이언트 인증서를 설정하므로, 그 마운트를 쓰는 모두가
인증서가 지명하는 그 사람입니다. 이는 한 사람이 쓰는 머신을 위한 것이며
`authn-bridge nfs-cert`가 그렇게 알려 줍니다.
{{< /callout >}}

## 비활성화 중에도 열려 있는 인증서 요청 {#a-certificate-request-held-open-across-a-disabling}

토큰은 요청이 시작될 때 검사되고, 본문은 클라이언트가 보내는 속도로 그 뒤에
읽힙니다. 그래서 인증서를 먼저 기록한 다음 토큰과 사람을 다시 검사합니다. 그 사이에
사람이 비활성화되었거나 토큰이 폐기되었다면, 방금 기록한 인증서는 폐기되고 응답은
`401`입니다. 폐기가 인증서를 보았거나, 인증서가 폐기를 보게 됩니다.
