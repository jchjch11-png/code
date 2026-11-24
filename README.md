# 글로벌 물 마시기 앱 — 팀 업무 문서

알림에서 물 섭취를 기록하고, 달성률별 캐릭터 스티커를 앱 달력에 붙이는 iOS/iPadOS·Android 앱의 개발 계획이다.

**현재 상태: 팀 구성 및 업무지침서 작성·검토 완료(S0), Git 저장소 준비. 앱 코드 구현·실기기 테스트·스토어 배포는 아직 시작하지 않았다.**

코드와 문서의 저장소는 [jchjch11-png/code](https://github.com/jchjch11-png/code)다. 기본 브랜치는 `main`, 로컬 원격 이름은 `origin`으로 관리한다.

## 먼저 볼 문서

| 문서 | 내용 |
|---|---|
| [팀 구성](docs/TEAM.md) | 메인 오케스트레이터와 Astra 3명·Sol 3명의 책임, 소유 파일, 협업 방식 |
| [개발·배포 단계](docs/ROADMAP.md) | 코드 작성부터 실기기 검증, 시험 배포, 스토어 공개까지의 업무와 완료 기준 |
| [공통 업무 규칙](AGENTS.md) | 에이전트가 따라야 할 범위, 파일 소유권, 검증·보고 규칙 |
| [제품 요구사항](docs/PRODUCT.md) | 기능, 보상 구간, 글로벌 언어팩, 초기 가정과 미정 사항 |
| [진행 현황](docs/STATUS.md) | 실제 완료된 작업과 앞으로 할 작업, 필요한 자원 |

## 담당별 업무지침

| 담당 | 문서 |
|---|---|
| Astra · 아키텍처 | [ARCHITECTURE.md](docs/workstreams/ARCHITECTURE.md) |
| Astra · 네이티브 알림 | [NOTIFICATIONS.md](docs/workstreams/NOTIFICATIONS.md) |
| Sol · 도메인·데이터 | [DOMAIN_DATA.md](docs/workstreams/DOMAIN_DATA.md) |
| Sol · UX·스티커 | [UX_REWARDS.md](docs/workstreams/UX_REWARDS.md) |
| Sol · 현지화 | [LOCALIZATION.md](docs/workstreams/LOCALIZATION.md) |
| Astra · 품질·출시 | [QUALITY_RELEASE.md](docs/workstreams/QUALITY_RELEASE.md) |

## 첫 버전 방향

- 대상 기기: 아이폰, 아이패드, 안드로이드 휴대폰, 갤럭시탭.
- 기술안: Flutter 공통 코드와 OS별 알림 연동. 확정 버전·패키지는 알림 시제품 검증 후 기록한다.
- 언어팩: 영어, 중국어 간체·번체, 일본어, 한국어, 힌디어. 앱 안에서 시스템 언어 또는 직접 선택을 지원한다.
- 인도 첫 언어는 힌디어와 영어로 가정한다. 인도의 다른 언어는 같은 구조로 추가한다.
- 초기 저장 방식은 로그인 없는 기기 내 저장이다. 다기기 지원과 기기 간 동기화는 구분한다.

문서는 실행 순서와 책임을 정한 계획서다. 패키지·화면·번역·스티커 자산·스토어 계정이 이미 준비되었다는 뜻은 아니다.
