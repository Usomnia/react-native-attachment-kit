# ⚠️ RNAttachmentKit-Dist — 빌드 산출물입니다. 여기서 코드를 고치지 마세요.

이 폴더는 `RNAttachmentKit`(형제 폴더, 진짜 소스) 코드를 숨기기 위해 컴파일한 **배포판**이며, npm 패키지 `react-native-attachment-kit` 로 배포됩니다.

- Android: `android/src/main/libs/rnattachmentkit-release.aar` (컴파일된 바이너리) + `android/src/{newarch,oldarch}/java/com/rnattachmentkit/*.kt` (RN 브릿지 소스, 소비 앱이 컴파일)
- iOS: `ios/RNAttachmentKit.xcframework` (컴파일된 바이너리) + `ios/RNAttachmentKit.swift|m` (RN 브릿지 소스) + `ios/RNAttachmentKitAssets/` (리소스 번들)
- JS: `src/*.ts`

앱(예: `ZemTalk.ReactNative`)이 `node_modules/react-native-attachment-kit` 로 이 폴더를 링크하거나 npm 버전을 설치해 사용합니다. **kt/swift/ts 는 `../RNAttachmentKit/deploy.rb` 가 통째로 덮어쓰므로, 여기서 직접 수정한 내용은 다음 빌드 때 사라집니다.** 손으로 맞추는 것은 설정 파일(`package.json`, `react-native-attachment-kit.podspec`, `react-native.config.js`, `README.md`)만입니다.

## 여기서 버그를 발견했다면

1. 실제 수정은 `../RNAttachmentKit/`(소스 프로젝트)에서 하세요. 그 폴더의 `CLAUDE.md`를 먼저 읽으세요.
2. 수정 후 `cd ../RNAttachmentKit && ruby deploy.rb` 를 실행해서 이 폴더를 다시 동기화하세요.
3. 상세 배포 절차는 `../.agents/rules/deployment_process.md` 참조.

> 2026-10-02: `react-native-turbo-image-picker` 2.0.8 에서 이름 변경 → `react-native-attachment-kit` 1.0.0. API 동일 (`../RNAttachmentKit/CHANGELOG.md`).
