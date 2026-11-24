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
- 앱 코드 체크포인트 `d5238da8dd2736281516dc9ed9e55ebb78772d4d`를 GitHub `main`에 푸시했다. 호환성 수정·실제 빌드 결과는 후속 커밋으로 저장한다.
- Flutter 3.50.1 / Dart 3.14.0, JDK 21과 Android SDK 36으로 최초 앱·SQLite·6개 언어·알림 코드를 준비했다. 정적 분석 오류 0건, 자동 검사 17개 통과.
- 알림 플러그인은 compileSdk 37을 요구하는 23.0.4 대신 SDK 36과 호환되는 22.3.3을 사용한다. 의존성 변경 뒤 분석·검사를 다시 통과했다.
- Android arm64 APK 빌드 성공. `build/app/outputs/flutter-apk/app-release.apk`, 18,120,195 bytes. 무결성·서명 확인 결과와 SHA-256은 `VALIDATION.md`에 있다.
- 약 8GB 공간 제약으로 재생성 가능한 도구 캐시를 정리했다. 앱 코드·검사·빌드에 사용한 컴파일러는 보존했다. 큰 도구 추가 설치 전 `df -h /workspace`를 확인한다.
- macOS/Xcode와 실기기 접근은 확보되지 않았으므로 iOS 빌드·실기기 검증을 완료로 표시하지 않는다.
- 초기 앱은 직접 목표 설정을 사용한다. 의료 근거를 확인하기 전 권장량 공식을 임의로 추가하지 않는다.

## 다음 개발을 시작할 때

최초 시제품의 코드·자동 검사·Android 빌드 목표는 충족했다. 예약 작업이 다시 실행되더라도 아래 후속 범위를 임의로 확장하지 않고 현재 결과를 먼저 보고한다.

1. Android 실기기를 사용할 수 있으면 `VALIDATION.md`의 절차로 APK 설치, 앱 재시작 후 저장, 알림 전체/절반·중복 응답을 확인한다. 기기·OS·언어·권한·앱 상태별 관찰 결과를 기록한다.
2. macOS/Xcode와 iPhone·iPad 접근이 확보되면 iOS 빌드 및 알림 실기기 검증을 진행한다. 현재 결과는 미검증이다.
3. 후속 제품 개발 범위를 정할 때 하루 전체 알림 일정·미루기, 스티커 자산·배치, 접근성·태블릿 화면을 우선순위로 검토한다.
4. 건강 권장량의 근거와 원어민 번역 검수는 별도 검토 자원이 필요하다. 스토어 계정·서명·제출·공개는 이번 과업에 포함하지 않는다.

## 실행 환경

- `PATH`에 `/workspace/toolchains/flutter/bin`을 추가하고 `PUB_CACHE=/workspace/toolchains/pub-cache`, `XDG_CONFIG_HOME=/workspace/toolchains/config`, `ANDROID_HOME=/workspace/toolchains/android-sdk`, `ANDROID_USER_HOME=/workspace/toolchains/android-user`, `GRADLE_USER_HOME=/workspace/toolchains/gradle`, `JAVA_HOME=/workspace/toolchains/jdk21`을 사용했다. 시스템 Java는 컴파일러 없는 JRE이므로 빌드에 사용하지 않는다.
- Dart 분석 캐시는 `/home/agent/.dartServer`, `/home/agent/.dart-tool`에 쓰기 권한이 필요했다. HOME을 다른 경로로 바꾸지 않는다.
- 이 환경의 Java 네트워크 클라이언트는 기존 HTTPS 프록시 설정을 JVM 속성으로 전달해야 했다. 비밀값은 저장소에 넣지 않는다.
- Flutter SDK는 `bin`, `packages`의 sparse checkout이며 실행 바이너리 캐시를 유지한다. Gradle 배포 문서·소스·압축본과 Android CLI 다운로드 캐시는 정리했으며 SDK 관리 명령은 필요 시 캐시를 다시 다운로드한다.
- 사용하지 않은 NDK 성능 측정 도구 `simpleperf`는 제거했다. 네이티브 디버거 라이브러리는 `/workspace/toolchains/optional/ndk-liblldb.so.gz`로 보관했다. NDK 디버깅·성능 측정이 필요하면 공간을 확보한 뒤 원본 NDK를 복원하거나 재설치한다. 빌드에 필요한 도구는 유지했고 실제 APK 생성으로 확인했다.
- 상세 명령 출력은 현재 환경의 `/tmp/hydration_analyze.log`, `/tmp/hydration_tests.log`, `/tmp/hydration_android_build_verified.log`에 있다. 임시 로그가 사라져도 저장소의 `VALIDATION.md`에서 관찰 결과를 확인할 수 있다.

## 작업 규칙

- 메인 + Sol 1명 중심. 독립적인 근거가 필요한 설계·알림 검토에만 Astra를 짧게 투입한다.
- 의미 있는 완료 단위마다 검증·커밋·푸시하고 이 파일과 STATUS.md를 갱신한다.
- 남은 작업이 없으면 이미 완료한 작업을 재생성하거나 사용량 소진을 위해 범위를 넓히지 않는다.
