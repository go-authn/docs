---
title: "scim — 신원 공급자로부터 사람과 그룹 프로비저닝하기"
linkTitle: "scim"
weight: 140
description: "go-authn/scim은 SCIM 2.0 서비스 공급자(RFC 7643, RFC 7644)입니다: 직접 작성하는 Backend 위의 Users와 Groups, Entra ID와 Okta 페이로드로 테스트됨. 표준 라이브러리만 사용."
tags: [라이브러리, scim, 프로비저닝]
---

**신원 공급자가 방금 누구를 생성, 변경, 삭제했는가?** 신원 공급자(Entra ID, Okta,
Keycloak, …)는 HTTP로 애플리케이션의 사람과 그룹을 생성, 갱신, 삭제합니다. 이 패키지가
Users와 Groups(RFC 7643, RFC 7644)를 위한 그 HTTP 엔드포인트이며, 직접 작성하는
`Backend` 위에 있습니다. 순수 Go, `CGO_ENABLED=0`, 표준 라이브러리만 사용합니다.

```sh
go get github.com/go-authn/scim@v0.1.0
```

## 예제 {#example}

```go
srv := &scim.Server{
	Backend: scim.NewMemory(),                     // or your database
	BaseURL: "https://app.example.org/scim/v2",    // for meta.location
}
mux.Handle("/scim/v2/", http.StripPrefix("/scim/v2", scim.BearerAuth(token, srv)))
```

Server는 id, 타임스탬프, 버전을 부여하고, 입력을 검증하고, PATCH를 적용합니다.
`Backend`는 받은 것을 보관하고 자신만 볼 수 있는 것을 강제합니다. 이미 사용 중인
`userName`에는 `ErrConflict`(409 `uniqueness`), 존재하지 않는 구성원에는
`InvalidValue`(400 `invalidValue`), 저장된 버전이 읽은 버전이 아닐 때는
`ErrPrecondition`. `NewMemory()`는 참조 구현입니다.

`/Users`와 `/Groups`(`filter`, `startIndex`, `count`, `attributes`,
`excludedAttributes`가 있는 목록, 생성, `ETag`와 `If-Match`가 있는 id별 조회, `PUT`,
`PATCH`, `DELETE`), `/Users/.search`와 `/Groups/.search`, 그리고 디스커버리
엔드포인트 `/ServiceProviderConfig`, `/ResourceTypes`, `/Schemas`를 제공합니다.
필터는 RFC 7644 §3.4.2.2의 문법 전체를 다루며, PATCH는 원자적입니다. 실패한 작업은
리소스를 그대로 둡니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

여기의 모든 것은 외부에서 오므로 한계가 API의 일부입니다.

| | |
|---|---|
| `MaxBodyBytes`(1 MiB)를 넘는 본문, `MaxOperations`(100)를 넘는 PATCH, 또는 리소스를 본문 한계 이상으로 키우는 PATCH | 413 |
| `MaxMembers`(10 000)를 넘는 그룹 | 400 `invalidValue` |
| 4 KiB를 넘거나, 32보다 깊게 중첩되었거나, 알 수 없는 연산자가 있거나, 불리언에 `gt`를 쓴 필터 | 400 `invalidFilter` |
| `id`, `meta`, `schemas`, 또는 사용자의 `groups`에 쓰기 | 400 `mutability` |
| 핵심 스키마가 없는 리소스, 비어 있거나 256바이트를 넘거나 제어 문자를 가진 `userName`, 기본 이메일 두 개 | 400 |
| 없거나 잘못된 베어러 토큰 (`BearerAuth`, 상수 시간. 빈 토큰은 아무도 들이지 않음) | 401 |
| 센티널이 아닌 모든 Backend 오류 | 아무것도 알려 주지 않는 본문과 함께 500. 오류는 `ErrorLog`로 감 |

**지원하지 않음**: 벌크 작업, 정렬, 비밀번호 변경, `/Me`(`/ServiceProviderConfig`에
그렇게 공지됨).

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

**신원 공급자가 실제로 보내는 것**을 그들의 페이로드로 테스트합니다. Entra ID의
`"Replace"`, 문자열 불리언(`"active": "False"`), 값 목록에 의한 구성원 제거, 이메일을
생성하는 필터링된 추가. Okta의 `id`를 반복하는 경로 없는 replace. 필터, PATCH, 핸들러
전체를 퍼징하며(`FuzzFilter`, `FuzzPatch`, `FuzzServer`), 커버리지 레인의 하한은 92%입니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.1.0](https://pkg.go.dev/github.com/go-authn/scim@v0.1.0)
