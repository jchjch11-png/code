# 개발 재개 지점

## 실행 범위

- 사용자가 2026-11-24 한국시간에 즉시 개발 시작을 지시했다.
- 2026-11-25 02:30, 07:00 Asia/Seoul에 일회성 재개 예약을 만들었다. 예약은 한도를 초기화하거나 실제 실행 환경 접근을 보장하지 않는다.
- 같은 작업이 실행 중이면 중복 구현하지 않는다. Git 변경과 실행 중인 프로세스·에이전트를 확인하고 진행 중인 파일을 보존한다.
- 작업 폴더 `/workspace/hydration-app`, 저장소 `https://github.com/jchjch11-png/code`, 기본 브랜치 `main`.

## 우선순위

1. Flutter 개발 도구를 사용자 쓰기 가능 경로에 준비하고 Android/iOS 프로젝트를 생성한다.
2. 하루 목표 직접 입력, 200/100mL 기록, 날짜별 합계·보상 경계·기기 내 저장을 구현한다.
3. Android 알림의 예약·액션·멱등 기록 시제품을 구현하고 가능한 환경에서 검증한다.
4. en/zh-Hans/zh-Hant/ja/ko/hi 언어 선택·저장과 화면 문구 초안을 연결한다.
5. 분석·테스트·빌드 결과, 기기 검증 공백, 실행 방법을 기록하고 커밋·푸시한다.

## 현재 체크포인트

- S0 문서 12개와 Git 연결 완료. 시작 커밋 `40a9799`.
- Flutter 3.50.1 / Dart 3.14.0과 Android SDK 36 설치, 최초 앱·SQLite·6개 언어·알림 코드 작성, 자동 검사 17개 통과.
- Linux 시스템 Java는 JRE이며 컴파일러가 없어 Android 빌드가 실패했다. 전체 JDK를 사용자 경로에 설치해야 한다.
- 알림 플러그인 23.0.4는 compileSdk 37을 요구하지만 현재 SDK 제공 목록에 37이 없다. 제공되는 SDK 36과 호환되는 안정 버전을 선택하고 다시 분석·검사·빌드한다.
- 설치 캐시 때문에 디스크가 부족해져 이번 작업에서 받은 Gradle 문서·소스·압축본만 제거했다. 코드·의존성 바이너리는 보존했다.
- macOS/Xcode와 실기기 접근은 확보되지 않았으므로 iOS 빌드·실기기 검증을 완료로 표시하지 않는다.
- 초기 앱은 직접 목표 설정을 사용한다. 의료 근거를 확인하기 전 권장량 공식을 임의로 추가하지 않는다.

## 지금 이어갈 작업

1. JDK와 알림 플러그인/compileSdk 호환성을 맞춰 Android arm64 디버그 APK 빌드.
2. `flutter analyze`, `flutter test` 최종 결과와 실제 APK 경로·해시를 STATUS에 남긴다.
3. Git 상태를 확인하고 검사한 변경을 커밋·푸시한다. 설치 가능한 APK가 나오면 로컬 결과 파일로 전달한다.
4. 네 기기 실물, iOS macOS/Xcode, 번역 검수는 확보하지 않았으므로 완료로 표시하지 않는다.

## 실행 환경

- `PATH`에 `/workspace/toolchains/flutter/bin`을 추가하고 `PUB_CACHE=/workspace/toolchains/pub-cache`, `XDG_CONFIG_HOME=/workspace/toolchains/config`, `ANDROID_HOME=/workspace/toolchains/android-sdk`, `ANDROID_USER_HOME=/workspace/toolchains/android-user`, `GRADLE_USER_HOME=/workspace/toolchains/gradle`을 사용했다.
- Dart 분석 캐시는 `/home/agent/.dartServer`, `/home/agent/.dart-tool`에 쓰기 권한이 필요했다. HOME을 다른 경로로 바꾸지 않는다.
- 이 환경의 Java 네트워크 클라이언트는 기존 HTTPS 프록시 설정을 JVM 속성으로 전달해야 했다. 비밀값은 저장소에 넣지 않는다.

## 작업 규칙

- 메인 + Sol 1명 중심. 독립적인 근거가 필요한 설계·알림 검토에만 Astra를 짧게 투입한다.
- 의미 있는 완료 단위마다 검증·커밋·푸시하고 이 파일과 STATUS.md를 갱신한다.
- 남은 작업이 없으면 이미 완료한 작업을 재생성하거나 사용량 소진을 위해 범위를 넓히지 않는다.
