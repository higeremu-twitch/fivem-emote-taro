# Stream Deck 機種別 ボタン配置リファレンス

調査日 2026-08-30 / 対象 Stream Deck デスクトップアプリ **7.5.1.22901**（この PC 実機）

プロファイル生成に必要なのは**キー数ではなくグリッド（列×行）**です。
公式の製品ページはキー数しか書かないので、別の一次情報から取っています。

---

## 1. 物理デバイス（グリッド確定）

出所: [python-elgato-streamdeck](https://github.com/abcminiuser/python-elgato-streamdeck)
の各デバイスクラス（`KEY_COLS` / `KEY_ROWS` / `DIAL_COUNT` を実読、最終更新 2026-08-24）。
キー数は [Elgato 公式比較ページ](https://www.elgato.com/us/en/explorer/products/stream-deck/stream-deck-device-comparison/) と一致を確認済み。

| 製品 | 列 | 行 | キー | ダイヤル | タッチ | 備考 |
|---|---:|---:|---:|---:|---:|---|
| Stream Deck Mini | 3 | 2 | 6 | — | — | |
| Stream Deck Neo | 4 | 2 | 8 | — | 2 | タッチ2個はページ送り用（キーとは別枠） |
| Stream Deck / MK.2 | 5 | 3 | 15 | — | — | Original と V2 で同一グリッド |
| Stream Deck + | 4 | 2 | 8 | 4 | あり | タッチストリップ |
| Stream Deck + XL | 9 | 4 | 36 | 6 | あり | |
| Stream Deck XL | 8 | 4 | 32 | — | — | |
| Stream Deck Studio | 16 | 2 | 32 | 2 | — | 1U ラック型 |
| Stream Deck Pedal | 3 | 1 | 3 | — | — | フットスイッチ |
| GALLEON 100 SD | 3 | 4 | 12 | 2 | — | キーボード一体型。※下記注記 |

**GALLEON 100 SD の注記:** python 側に定義が無いため、アプリ同梱の初期プロファイル
`Galleon100SD_winDefault.streamDeckProfile` から実測（9ページすべて Keypad 3×4 で一貫）。
公式のキー数12・ダイヤル2と一致するので確度は高いが、**列×行の向きは未確認**。
なおエンコーダが `2×2` として記録されており、公式の「ダイヤル2」と食い違う。理由は不明。

---

## 2. バーチャルデバイス（カスタム可）

### Virtual Stream Deck（画面上に出るデック）

内部名 `UI Stream Deck` / `UIProfiles`。アプリ内の設定UIを実バイナリから確認。

| 項目 | 値 | 出所 |
|---|---|---|
| 形状 | **グリッド** と **リング** の2種 | exe内 `gridConfiguration` / `ringConfiguration` |
| デバイス種別 | **Fixed** / **Dynamic** | exe内 `wg_deviceType` の選択肢 |
| グリッド | **Rows × Columns を自分で指定**。最大 **8×8 = 64キー**（1パネルあたり） | UIラベル "Label of the slider to adjust number of key rows on Virtual Stream Deck device with grid layout" ／ [公式](https://www.elgato.com/us/en/explorer/products/stream-deck/virtual-stream-deck-beta-overview/) "up to an 8×8 grid, that's 64 virtual keys per panel" |
| リング | **Key count** を指定（`sb_keyCount`） | exe内 `ringConfiguration` |
| **最小値** | **未確認** | 公式は最大しか書いていない。設定UIを開けば分かるが、そのために機能を有効化するのは未実施 |
| その他設定 | 未使用キーを隠す / カーソルが離れたら隠す / 実行後に隠す / ロック / キーサイズ / 不透明度 / 枠色 | exe内 `sw_hideEmptyKeys` `cb_hideOnLeave` `cb_hideOnExecute` `locked` `sl_keySize` `sl_opacity` `pb_colorSelector` |
| 動作要件 | Stream Deck 7.0 以降 / Windows 11 64bit 以降 / macOS 13 以降 | 公式 |

**このPCでは現在無効**です（ログ `ESDUiStreamDeck::init  Virtual Stream Deck in not enabled`）。

### Stream Deck Mobile（スマホ・タブレット）

内部名 `VSD2/WiFi`。デスクトップ側は Bonjour でポート 28198 を広告。

| 項目 | 値 | 出所 |
|---|---|---|
| 無料版 | **6キー**（永久） | [公式](https://www.elgato.com/us/en/s/stream-deck-mobile) "Get 6 keys for free — forever!" |
| Pro版 | **最大 64キー** | 公式 "Unlock up to 64 keys" |
| カスタム形状 | 縦長 / 横長 / 正方形。**「全64キー」から「大きな1ボタン」まで** | 公式 "Vertical, horizontal, or square. All 64 keys or one big button." |
| **最小値** | **1キー**（＝"one big button"） | 同上 |
| レイアウト変更 | **Pro サブスクリプション必須**。プリセット＋Custom | [公式ヘルプ](https://help.elgato.com/hc/en-us/articles/16549072466445-Elgato-Stream-Deck-Mobile-2-0-How-to-change-Keypad-Layout) |
| 縮小時の挙動 | キーは消えず、**左上から順に使われる** | 同上 |
| ページ | 追加 **10ページ**まで | 公式 |
| 同時起動 | 複数キーパッドを同時に動かせる（台数は端末と設定次第） | 公式 |
| 必要環境 | Stream Deck 6.3以降 / Mobile 2.0以降 / iOS 15以降 / Android 9以降 | 公式ヘルプ |

**おじさんの端末は現在 5×3（15キー）** で使用中（`ProfilesV3` の全ページが 5×3 で一貫）。

**重要:** VSD2 のプロトコル（exe内 protobuf スキーマ `messages.proto`）を読んだところ、
`KeypadConfig` にはアイコン寸法（`iconSize` `pressedIconSize` `highDPI` `layoutCrop`）しかなく、
**行・列のフィールドが存在しません**。つまり**グリッドはクライアント（スマホ）側が決めて**います。
`UIntRange{min,max}` という型は定義されていますが、**このスキーマ内で使用しているフィールドは見つかりませんでした**。

---

## 3. 型番と機種の対応（判明分）

アプリのバイナリに型番17個が埋まっています。同梱の初期プロファイルから対応が取れたのは以下。

| 型番 | 機種 | 根拠 |
|---|---|---|
| `20GAA9902` | Stream Deck（15キー） | `StreamDeck_winDefault` が宣言 |
| `20GAI9901` | Stream Deck Mini（6キー） | `StreamDeckMini_winDefault` / Discord版も同型番 |
| `20GAT9902` | Stream Deck XL（32キー） | `StreamDeckXL_winDefault` |
| `20GBD9901` | Stream Deck +（8キー＋ダイヤル4） | `StreamDeckPlus_winDefault` ／ USB PID `0x0084` = Plus |
| `20GBJ9901` | Stream Deck Neo（8キー） | `StreamDeckNeo_winDefault` |
| `20GBX9901` | Stream Deck + XL（36キー＋ダイヤル6） | `StreamDeckPlusXL_winDefault` |
| `GRETSCH` | GALLEON 100 SD | `Galleon100SD_winDefault` |
| `UI Stream Deck` | Virtual Stream Deck | 内部名 |
| `VSD2/WiFi` | Stream Deck Mobile | 内部名 |

**未特定の型番（9個）:** `20GAA9901` `20GAI9902` `20GAT9901` `20GBA9901` `20GBF9901`
`20GBL9901` `20GBM9901` `20GBN9901` `20GBO9901` `20GBQ9901` `20GBW9901` および `20GBD9901LL`。
世代違い・地域違い・未発売品が混ざっていると思われますが、**推測はしません**。

Corsair 製品も同じアプリが扱います（`Corsair Voyager` `Corsair G-Keys` `Corsair Scimitar Elite`
`CORSAIR_NORD_KBD` `CORSAIR_NUMARK_KBD` `CORSAIR_NOVATION_KBD` `CORSAIR_ROLAND_KBD`）。

---

## 4. 使えなかった手法（記録）

**同梱の初期プロファイルからグリッドを測るのは不正確です。** 1つのファイルの中に
複数の形が混在します（Stream Deck + の初期プロファイルは 4×2 が2ページ、4×3 が2ページ、
5×3 が1ページ、5×2 が1ページ）。Stream Deck は範囲外の座標を削除せず保持するためです。
最頻値を見れば参考にはなりますが、単純な最大値は必ず過大になります。

再現用: `tools\probe-devices.ps1`（一覧）、`tools\probe-devices-detail.ps1 -Name <機種>`（ページ別）
