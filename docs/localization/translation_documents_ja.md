# BodyMode 翻訳対象ドキュメント

更新日: 2026-08-21

## 翻訳する正本

| 区分 | 日本語正本 | 用途 |
|---|---|---|
| App Store | `docs/app_store_connect/app_store_metadata_ja.md` | 名前、サブタイトル、説明、キーワード、プロモーション文 |
| TestFlight | `docs/app_store_connect/testflight_metadata_ja.md` | ベータ説明、テスト項目、更新内容 |
| プライバシー | `docs/legal/privacy-policy-ja.md` | 公開Web、アプリ内表示 |
| 利用規約 | `docs/legal/terms-of-use-ja.md` | 公開Web、アプリ内表示 |
| サポート | `docs/legal/support-ja.md` | 公開Web、アプリ内表示 |

`docs/app_store_connect/app_privacy_answers_ja.md`と`app_declarations_ja.md`は運営用回答表であり、全文翻訳しない。各国向けに追加説明が必要な項目だけ別途作成する。

## 英語公開物

英語圏向けの第一段階は完成している。

| 区分 | ファイルまたはURL | 状態 |
|---|---|---|
| App Store | `docs/app_store_connect/app_store_metadata_en-US.md` | 文字数制限確認済み |
| App Review | `docs/app_store_connect/app_review_notes_en-US.md` | 完成 |
| プライバシー | `https://yukitoshim.github.io/gym-training-app/en/privacy/` | 公開・HTTP 200確認済み |
| 利用規約 | `https://yukitoshim.github.io/gym-training-app/en/terms/` | 公開・HTTP 200確認済み |
| サポート | `https://yukitoshim.github.io/gym-training-app/en/support/` | 公開・HTTP 200確認済み |
| iPhone画像 | `docs/app-store/screenshots-en/` | 8画面、1320 x 2868、アルファなし |

他言語のストア・法務本文は、健康・免責・広告表現を対象言語話者または専門家が確認するまで公開確定扱いにしない。

## アプリ内文字列

`translation_packs/index.json`を索引とし、同じディレクトリのJSONLを1ファイルずつ翻訳する。各行は独立したJSONで、`id`、日本語原文、プレースホルダー、コード上の参照位置を持つ。

次は翻訳対象外とする。

- AI内部プロンプトとコンテキスト構築文
- 診断ログ
- テストコード
- SF Symbols名、APIパス、永続化キー
- コーチの人物名と`BodyMode`ブランド名

法務文はコード中の断片ではなく上記Markdownを翻訳し、実装時にローカライズ済みリソースとして読み込ませる。

## 翻訳単位

- App Storeメタデータは`translation_strategy`が`deferred`ではない44ロケールを個別に作る。
- アプリ本体は日本語を含む41ローカリゼーションで構成する。英語4地域は英語ベースを共有し、ストア文だけ地域別確認する。
- フランス語とフランス語（カナダ）は共通原稿から地域差を確認する。
- 中国語、ポルトガル語、スペイン語は記載された地域・文字体系ごとに別翻訳とする。
- アラビア語とヘブライ語は右から左の画面検査を必須とする。ウルドゥー語は今回の公開対象外とする。
