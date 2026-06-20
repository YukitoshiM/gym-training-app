# iOS開発環境セットアップ

## 必要なもの

- macOS
- Xcode
- Homebrew
- XcodeGen
- GitHub CLI

## 現在のリポジトリ構成

```text
.
├── GymTrainingApp/
│   ├── App/
│   ├── Assets.xcassets/
│   └── Features/
├── docs/
├── project.yml
└── README.md
```

## セットアップ手順

### 1. Xcodeをインストール

App StoreまたはApple DeveloperサイトからXcodeをインストールする。

App Storeを開く:

```sh
open 'macappstore://apps.apple.com/app/id497799835'
```

インストール後、以下を実行する。

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -version
```

現在の開発者ディレクトリを確認する:

```sh
xcode-select -p
```

`/Library/Developer/CommandLineTools` が表示される場合、iOS SimulatorビルドにはXcode本体への切り替えが必要。

### 2. XcodeGenを確認

```sh
xcodegen --version
```

未インストールの場合:

```sh
brew install xcodegen
```

### 3. Xcodeプロジェクトを生成

```sh
xcodegen generate
```

生成後、以下を開く。

```sh
open GymTrainingApp.xcodeproj
```

### 4. Team設定

Xcodeで `GymTrainingApp` ターゲットを選び、Signing & Capabilities の Team を設定する。

個人端末で実機確認する場合は、Apple IDのPersonal Teamでもよい。

### 5. Simulatorで起動確認

Xcode上でiPhone Simulatorを選択し、Runする。

CLIで確認する場合:

```sh
xcodebuild -scheme GymTrainingApp -destination 'platform=iOS Simulator,name=iPhone 16' build
```

利用できるSimulator名を確認する:

```sh
xcrun simctl list devices available
```

## 注意

このリポジトリでは `.xcodeproj` はXcodeGenで生成するためGit管理しない。設定変更は `project.yml` に反映する。
