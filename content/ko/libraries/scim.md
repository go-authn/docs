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
go get github.com/go-authn/scim@v0.2.1
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

## v0.2.0에서 바뀐 것 {#v020}

감사, 퍼징과 카오스, 성능 개선을 거쳐. 호출자에게 보이는 것:

- **`Server.ReadTimeout`**(신규, 기본 30초): 도착하는 데 더 오래 걸리는 요청 본문은 400으로 잘립니다. 그 요청에 대해
  `http.Server` 자체의 `ReadTimeout`을 대체합니다. 음수 값이면 `http.Server`의 것이 그대로 쓰입니다.
- **`ConditionalDeleter`**: `Backend`가 구현할 수 있는 새 선택 인터페이스(`DeleteUserIf`, `DeleteGroupIf`)이며
  `Memory`가 구현합니다. `If-Match`가 있는 `DELETE`는 버전을 확인한 뒤 두 단계로 삭제했으므로, 그 사이에 들어온
  쓰기가 보이지 않은 채 삭제되었습니다.
- **진 경합은 다시 수행됩니다.** `If-Match` 없는 `PATCH`나 `PUT`이 다른 쓰기와의 경합에서 지면, 클라이언트가
  전제 조건을 요구하지 않았는데도 412로 응답했습니다. 이제 더 새로운 버전에서 최대 32번 다시 수행됩니다.
  `If-Match`가 있으면 응답은 여전히 412입니다. `If-Match` 없는 동시 PATCH 24개 중 이전에는 9개가 412로 실패했고
  지금은 0개입니다.
- 아무것도 일치하지 않는 필터로 멤버(또는 임의의 요소)를 제거하면 성공합니다. 이전에는 400 `noTarget`이었습니다
  (RFC 7644 §3.5.2.2).
- 경로 없는 PATCH는 키를 정렬된 순서로 적용합니다. 이전에는 맵 순서여서, 한 객체의 `name`과 `name.givenName`이 실행마다
  다른 리소스를 만들었습니다.
- `BearerAuth`는 스킴 이름을 대소문자 구분 없이 받아들입니다(`bearer <token>`, RFC 7235 §2.1).
- `startIndex`와 `count`는 `int`의 크기와 상관없이 상한으로 잘립니다. 이전에는 32비트 대상에서는 400, 64비트에서는
  잘린 페이지였습니다.
- `Filter.Equality()`는 `Backend`에 디코딩된 문자열을 넘깁니다. 이것은 데이터입니다. 데이터베이스에 매개변수로
  넘기고, 쿼리에 끼워 넣지 마십시오.

대량 작업, 정렬, 비밀번호 변경은 계속 지원되지 않습니다.

`Memory`에서 사용자 10,000명과 그룹 200개에 대한 목록 요청 한 번의 **할당**. `go test -bench`의 정확한 값,
Apple M4 Max:

| 목록 요청 | 이전 | 이후 |
|---|---|---|
| 100개 페이지 | 789,417회, 47.7 MB | 14,952회, 6.0 MB |
| `userName eq` | 797,979회, 47.7 MB | 90회, 12.6 KB |
| 모든 사용자를 훑는 필터(`name.givenName eq`와 `emails[...]`) | 818,847회, 48 MB | 361,098회, 29.7 MB |

실제 시간은 측정하지 않았습니다. 부하가 65였고 규칙은 9 미만입니다. 잡음이 많은 단발 실행(훑는 필터에서 약 1.7초 대
0.06초)은 결과가 아닙니다. `FuzzPatchPath`, `FuzzPatchThenDecode`, `FuzzFilter`, `FuzzServer`를 각각 45초, 워커 16개로
실행했으며 130만에서 240만 회 실행에서 실패를 찾지 못했습니다.

## v0.2.1에서 바뀐 것 {#v021}

- **`If-None-Match`는 RFC 7232 §3.2를 따릅니다.** 엔티티 태그 목록(여러 헤더 줄도
  포함)을 가진 `GET`은 그중 하나라도 약한 비교로 일치하면(`"x"`는 `W/"x"`와
  일치) 304로 응답합니다. `*`는 존재하는 모든 리소스에 대해 304로 응답합니다.
  유효한 `If-None-Match`가 아닌 헤더는 무시됩니다. 304는 `ETag`를 담으며(RFC 7232
  §4.1), 이전에는 담지 않았습니다. `FuzzIfNoneMatch`로 퍼징했습니다.
- **`Memory`는 `userName`의 색인을 유지합니다.** 고유성은 모든 사용자를 훑어
  확인했으므로 사용자 N명을 불러오는 데 `EqualFold` 호출이 O(N^2)번 필요했습니다.
  이제 O(N)이며, 사용자 10,000명에 대한 1억 번의 호출이 사라졌습니다. 키는 각 룬의
  `unicode.SimpleFold` 궤도 최솟값으로, `strings.EqualFold`의 동치 관계와 정확히
  같습니다(예전의 훑기와 대조해 테스트했고 `FuzzFoldKey`로 퍼징했습니다). 생성,
  교체(PUT과 PATCH), 삭제가 이를 일관되게 유지합니다. `BenchmarkMemoryLoad10k`(사용자
  10,000명을 생성하고 교체)는 한 번 실행에 할당 119,030회가 들며, 이전에는
  98,959회였습니다. 색인은 생성마다, 이름 변경마다 키 하나입니다.
- **어떤 색인도 답할 수 없는 필터가 있는 목록은 필터가 지명하는 최상위 속성만 담은
  맵에서 일치를 검사하며**, 전체 객체는 페이지에 대해서만 만듭니다.
  `BenchmarkListFilterCo10k`(사용자 10,000명): 요청당 할당이 이전 361,095회, 지금
  162,695회이며, 사용자당 36.1회에서 16.3회입니다. 동치성은 필터 50개와 무작위
  필터로 테스트합니다(`FuzzFilterOnSelectedMap`).

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

**신원 공급자가 실제로 보내는 것**을 그들의 페이로드로 테스트합니다. Entra ID의
`"Replace"`, 문자열 불리언(`"active": "False"`), 값 목록에 의한 구성원 제거, 이메일을
생성하는 필터링된 추가. Okta의 `id`를 반복하는 경로 없는 replace. 필터, PATCH, 핸들러
전체를 퍼징하며(`FuzzFilter`, `FuzzPatch`, `FuzzServer`), 커버리지 레인의 하한은 92%입니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.2.1](https://pkg.go.dev/github.com/go-authn/scim@v0.2.1)
