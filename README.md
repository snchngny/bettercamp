# BetterCamp — MacBook Pro 2012 / Windows 11

MacBook Pro 2012に**インストール済みのWindows 11**から、PowerShellの1行または`Start-BetterCamp.cmd`でBoot Campドライバーのセットアップを開始する版です。Pythonのインストールは不要です。

[vinaypundith/bettercamp](https://github.com/vinaypundith/bettercamp) の2026-07-04時点の最新 `main`（`b2bd633675116ef489f8cd76ae82ba0fb22f8d16`）を基に改修しています。確認日: 2026-09-29。

## 起動方法

Windows 11でPowerShellを開き、次の1行を貼り付けてEnterを押します。リポジトリのZIP保存・展開は不要です。

```powershell
irm https://raw.githubusercontent.com/snchngny/bettercamp/bea78ad008343870b5381a124296eea18b562ca1/run.ps1 | iex
```

管理者権限を求めるWindowsの画面で「はい」を選び、Appleのインストーラーに従います。完了後にWindowsを再起動してください。

ブラウザーからファイルを手動ダウンロードしたくない、という意味での「ダウンロード不要」です。起動用ファイルは一時フォルダーへ自動取得して終了時に削除します。Boot Campドライバーが未導入なら、約925MBのApple公式パックの通信取得は必要です。インターネット通信も一切使えない場合は、後述のオフライン手順を使ってください。

PowerShellへ貼り付ける方式を使いたくない場合だけ、[ZIPをダウンロード](https://github.com/snchngny/bettercamp/archive/refs/heads/main.zip)して展開し、`Start-BetterCamp.cmd`をダブルクリックします。

ドライバーがなければ、Apple公式サイトから約925MBの対応パックを取得・展開します。インターネット接続と、ダウンロード・展開用に数GBの空き容量が必要です。Wi-Fiがまだ使えない場合は有線接続か、次のオフライン手順を使ってください。

このツールはWindows自体をインストールするものではありません。macOSからは実行できません。AppleはこのMacでのWindows 11を公式サポートしていません。**新ランチャーの機械検証は実施済みですが、MacBook Pro実機でのドライバー導入・音声・再起動は未検証です。**

## 対象機種

| 機種ID | 主なモデル |
| --- | --- |
| MacBookPro9,1 | 15インチ Mid 2012 |
| MacBookPro9,2 | 13インチ Mid 2012 |
| MacBookPro10,1 | Retina 15インチ Mid 2012系 |
| MacBookPro10,2 | Retina 13インチ Late 2012系 |

64-bit Windows 11（build 22000以上）を確認してから起動します。10,1/10,2はEarly 2013でも使われる識別子のため、年式までは区別しません。ほかのMacや一般のPCではインストーラーを起動しません。

## 手元のドライバー・最新版を使う

**Boot Campドライバーの最新版と、このリポジトリの最新版は別です。** Appleは最新のWindowsサポートソフトウェアの取得にBoot Campアシスタントを案内しています。

そのMacのmacOSでBoot Campアシスタント → メニューバー「アクション」→「Windowsサポートソフトウェアをダウンロード」を選び、取得した `BootCamp` フォルダーを以下の位置へコピーしてください。コピーしたものを自動取得より優先します。

```text
bettercamp-main/
  Start-BetterCamp.cmd
  bettercamp.ps1
  scripts/
  BootCamp/
    BootCamp.xml
    setup.exe
    Drivers/
```

任意の場所やUSB上に置く場合は、PowerShellで次のように指定できます。

```powershell
.\Start-BetterCamp.cmd -BootCampPath "D:\WindowsSupport\BootCamp"
```

手元にない場合の自動取得は、2012年モデルを対象に含む **Boot Camp 5.1.5621** です。これはAppleのアーカイブ版であり、最新ドライバーと称するものではありません。5.1より古いパックは受け付けません。ダウンロード先は `%LOCALAPPDATA%\BetterCamp\downloads` です。取得ごとに別フォルダーを使うため、再利用時は表示されたパスを `-BootCampPath` に渡してください。

オフラインの場合は、別PCで[Apple公式の配布ページ](https://support.apple.com/en-us/106412)からZIPを取得・展開し、上記の `BootCamp` フォルダーをUSB経由で渡せます。古い証明書の検証に失敗した場合は、Windowsの時計とインターネット接続を確認してください。

## 診断・ダウンロードのみ

インストールせず機種・Windowsビルド・GPU・起動方式を確認:

```powershell
.\Start-BetterCamp.cmd -Diagnose
```

対応MacBook上で取得・署名検証だけ実行:

```powershell
.\Start-BetterCamp.cmd -DownloadOnly
```

ログは `%LOCALAPPDATA%\BetterCamp\logs` に保存します。診断はログファイルを作成しません。失敗時は画面のエラーとログを確認し、成功と表示されるまで再起動後の動作確認を完了扱いにしないでください。

## UEFI音声パッチ

`MacBookPro9,2`をUEFI起動している場合、通常の1行起動で次も自動実行します。

1. 同梱`asl.exe`と`dsdt_2012.aml`のSHA-256を検証
2. `bcdedit`でWindowsのテスト署名モードを有効化
3. Microsoft ASLの`/loadtable`で音声修正済みDSDTを登録
4. Apple Boot Campドライバーを導入

変更は再起動後に有効になります。テスト署名モードではデスクトップに「テスト モード」の表示が出ます。MicrosoftはACPIテーブル上書きを開発・テスト用とし、起動不能になる可能性を警告しています。実行前にWindows回復環境またはmacOSからWindowsボリュームへアクセスできる状態を用意してください。Secure Bootが有効な場合は適用を停止します。

すでにBoot Campドライバーを導入済みで、音声パッチだけ適用する場合:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/snchngny/bettercamp/bea78ad008343870b5381a124296eea18b562ca1/run.ps1))) -AudioPatchOnly
```

元へ戻す場合。登録したDSDTを削除し、BetterCampが今回有効にした場合だけテスト署名モードも無効にします:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/snchngny/bettercamp/bea78ad008343870b5381a124296eea18b562ca1/run.ps1))) -RemoveAudioPatch
```

`MacBookPro9,1`、`MacBookPro10,1`、`MacBookPro10,2`には同じDSDTを自動適用しません。元READMEでの2012年実機確認が`MacBookPro9,2`だけで、機種固有ACPIの横断利用を確認できないためです。`-Diagnose`で機種IDを確認できます。Boot Camp導入だけにする場合は`-SkipAudioPatch`を指定できます。

**旧 `bettercamp.py`、`bettercamp2.py`、`fix9400.py`、`bclaunch_test.ps1` は新しい起動入口ではありません。** 上流の履歴・素材として保持していますが、直接実行しないでください。

## 改修内容と検証

- Python・WMIC依存の起動手順をWindows標準のPowerShell 5.1へ置換
- 実機の機種IDをCIMで取得し、対象モデルとWindows 11を確認
- 管理者昇格、空白・角括弧・アポストロフィを含むパス、終了コードを処理
- `BootCamp.xml` をXMLとして読み、行番号に依存しないバージョン確認
- Apple公式ZIPの取得、Appleのインストーラー署名確認、ログ保存
- `MacBookPro9,2` UEFI環境のテスト署名設定、DSDT音声パッチ、状態記録と復旧
- 複数のインストーラーを同時に起動せず、完了まで待機

Windows PowerShell 5.1での回帰テスト:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BetterCamp.ps1
```

テストは機種判定、パス、XML、署名エラー、終了コード、診断入口、音声パッチ適用・失敗時のロールバック・削除を確認し、実際のドライバーや起動設定を変更しません。GitHub Actionsでも同じテストを実行します。

## 出典・既存手段との比較

既存のAppleインストーラーを使い、独自ドライバーや配布基盤は追加していません。Boot Campアシスタントは最新の機種別パックの取得元として優先し、Windows側だけで起動できる入口をこの改修で補います。Brigadierによる動的取得も候補ですが、追加の実行ファイル・展開依存を増やさずに済むApple公式ZIPを予備の取得元としました。新しいドライバーを自作・更新したものではありません。

- [Apple: Boot Camp 5.1.5621の対象機種・ダウンロード](https://support.apple.com/en-us/106412)
- [Apple: Windowsサポートソフトウェアをダウンロード](https://support.apple.com/en-us/102465)
- [Microsoft: WMICの廃止とPowerShellへの移行](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wmic)
- [Microsoft: ASL CompilerとACPIテーブル上書き](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/microsoft-asl-compiler)
- [Microsoft: Windowsテスト署名モード](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/the-testsigning-boot-configuration-option)
- [上流READMEとクレジット](docs/UPSTREAM-README.md)

上流のコード・同梱素材・クレジットを保持したForkです。上流にはリポジトリ全体のLICENSEファイルがないため、このForkで第三者素材の利用許諾を新たに付与するものではありません。Appleのドライバーパックはリポジトリに含めず、公式配布元から取得します。
