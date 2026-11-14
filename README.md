# BetterCamp — MacBook Pro 2012・Mac mini 2018 / Windows 11

**インストール済みのWindows 11**から、MacBook Pro 2012（`MacBookPro9,2`）またはMac mini 2018（`Macmini8,1`）用のApple公式ドライバーを取得・導入します。MacBook ProにはUEFI音声パッチもあります。Pythonのインストールは不要です。

[vinaypundith/bettercamp](https://github.com/vinaypundith/bettercamp) の2026-07-04時点の最新 `main`（`b2bd633675116ef489f8cd76ae82ba0fb22f8d16`）を基に改修しています。確認日: 2026-09-29。

## 起動方法

手元の最新版では、`Start-BetterCamp.cmd`をダブルクリックします。PowerShellからも実行できます。

```powershell
.\Start-BetterCamp.cmd
```

以下の固定版1行起動は従来のMacBook Pro 2012版です。Mac miniの初期セットアップ機能は含みません。Mac miniではこの改修を含むローカルコピーを使ってください。リモートへの公開は別途行います。

```powershell
irm https://raw.githubusercontent.com/snchngny/bettercamp/9adc1f1524ef8397978d45c9b2db8edd2a4aa8b1/run.ps1 | iex
```

管理者権限を求めるWindowsの画面で「はい」を選びます。必要なデバイスドライバーを順番に導入した後、Windowsを再起動してください。

1行起動の「ダウンロード不要」はブラウザーで手動取得しないという意味です。起動用ファイルは一時フォルダーへ自動取得して終了時に削除します。Apple公式ドライバーパックの通信取得は必要です。オフライン導入には事前取得したパックを使います。

公開済みのソースは[リポジトリのZIP](https://github.com/snchngny/bettercamp/archive/refs/heads/main.zip)でも取得できます。未公開のローカル改修はZIPへ含まれません。

ドライバーがなければ、Apple公式サイトから対応パックを取得・展開します。MacBook Proは約925MB、Mac miniは約548MBです。Mac miniの初回展開には約5GBの空き容量を用意してください。Wi-Fiがまだ使えない場合は有線接続か、次のオフライン手順を使ってください。

このツールはWindows自体をインストールするものではありません。macOSからは実行できません。Appleは対象MacでのWindows 11を公式サポートしていません。**回帰テストとMac mini用実配布物の取得・検証を行っていますが、新しい導入処理による実機ドライバー適用・再起動後の動作は未検証です。**

## 対象機種

| 機種ID | 主なモデル |
| --- | --- |
| MacBookPro9,1 | 15インチ Mid 2012（診断のみ） |
| MacBookPro9,2 | 13インチ Mid 2012（ドライバー・音声パッチ対応） |
| MacBookPro10,1 | Retina 15インチ Mid 2012系（診断のみ） |
| MacBookPro10,2 | Retina 13インチ Late 2012系（診断のみ） |
| Macmini8,1 | Mac mini 2018（ドライバー取得・導入・診断） |

64-bit Windows 11（build 22000以上）を確認してから起動します。導入先は実機の機種IDで判定します。同梱DSDTは`MacBookPro9,2`専用で、Mac miniには適用しません。別のWindows PCからは、機種を指定した取得だけが可能です。

## Mac mini 2018の初期セットアップ

通常起動でApple公式の機種専用パック **041-91731 / Boot Camp 6.1.7139** を取得し、ドライバーを導入します。これは検証した固定パックで、最新版を動的に探す機能ではありません。

- Apple SSD、USB、音声、SMC・Thunderbolt等の識別情報
- Broadcom Wi-Fi・Bluetooth・Ethernet、Aquantia Ethernet（10Gbモデル用）
- Intel Graphics、Management Engine、Serial IO（UART等）、音声関連
- 同梱のAppleキーボード・マウス等のドライバー。実機への適用可否はWindowsが判定

パック全体のSHA-256と展開後の`BootCamp`・`$WinPEDriver$`のファイル名・全ファイル内容を検証します。配布元の`setup.exe`のApple署名も確認します。公式7-Zip 26.06を取得・ハッシュ検証し、BetterCamp専用キャッシュ内で展開に使います。7-Zipのインストーラーは実行せず、PATHや関連付けは変更しません。ライセンスはキャッシュの`tools/7zip-26.06/portable/License.txt`に保持します。

導入はWindows標準の`pnputil /add-driver <INF> /install`で39個のINFを順に処理します。Windowsが適合する最上位のドライバーを選び、旧版の強制適用・既存ドライバー削除・自動再起動は行いません。「処理完了」は39個すべてが現在のデバイスへ適用されたという意味ではありません。既存の新版が優先される場合や、該当機器がない場合もあります。

Boot Camp Manager・Control Panel・Apple Software Updateは導入しません。Windowsセットアップ用のBluetooth代替INF（AppleBTBC、UHE）は通常導入から除外します。標準Bluetoothドライバーの導入で既知のCode 10が直ることは保証せず、残るデバイスエラーを終了時に表示します。失敗時はそのINFで停止し、先に導入したドライバーは残ります。ログを確認してください。

取得だけ行う場合:

```powershell
.\Start-BetterCamp.cmd -DownloadOnly
```

別のWindows 11 PCでMac mini用を準備する場合:

```powershell
.\Start-BetterCamp.cmd -DownloadOnly -TargetModel 'Macmini8,1'
```

保存先は`%LOCALAPPDATA%\BetterCamp\downloads\Macmini8,1-041-91731\WindowsSupport`です。取得時に表示するこのフォルダーを丸ごとUSBへコピーし、対象Macで次を実行します。`BootCamp`だけではSSD・Wi-Fi・UART・GPU等が不足するため受け付けません。

```powershell
.\Start-BetterCamp.cmd -BootCampPath 'D:\WindowsSupport'
```

同じパックの改変されていないファイル構成だけを受け付けます。別版を指定して検証に失敗した場合は、そのまま導入せず`-DownloadOnly`で対応版を取得してください。キャッシュが破損した場合も自動削除はしません。表示された該当フォルダーを退避し、再取得してください。

Windowsを入れる前に内蔵SSDが見えない場合は、別PCで取得した`WindowsSupport\$WinPEDriver$\AppleSSD64`をUSBへ用意し、Windowsセットアップの「ドライバーの読み込み」で指定します。Windows導入後にBetterCampを実行してください。Bluetooth代替ドライバーを含む`$WinPEDriver$`全体を導入済みWindowsへ一括適用しないでください。

## Mac mini 2018の内蔵Bluetooth診断

`Macmini8,1`で`Broadcom Serial Bus Driver over UART Bus Enumerator`（`ACPI\BCM2E7C\1`）がコード10になった場合の状態確認に使います。互換性のためコマンド名は`-RepairBluetooth`のままですが、ドライバーやWindows設定は変更しません。

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/snchngny/bettercamp/9adc1f1524ef8397978d45c9b2db8edd2a4aa8b1/run.ps1))) -RepairBluetooth
```

実機ではBroadcom `12.0.1.879`からApple配布版`12.0.1.874`への変更、UHE `12.0.1.870`、Intel UART `30.100.2132.2`を確認しましたが、再起動後も内蔵Bluetooth無線は復帰しませんでした。そのため自動変更は行いません。Bluetoothを使わない場合、このコード10はそのままでも音声、Wi-Fi、GPU、SSDには影響しません。Bluetoothが必要な場合は、Windows Updateの「現在のWindowsを再インストール（アプリ、ファイル、設定を保持）」を次の候補として手動で検討してください。

## Boot Camp Managerを入れない理由

通常の`BootCamp\setup.exe`はデバイスドライバーだけでなく、Boot Camp Manager、Boot Camp Control Panel、Apple Software Update、常駐処理もまとめて導入します。この版は`setup.exe`と`BootCamp.msi`を実行せず、MacBook Proは個別インストーラー、Mac miniは個別INFで導入します。

そのためBoot Camp Managerの常駐や古いApple Software Updateは追加されません。Boot Camp Control Panelが提供する起動ディスク切替なども入りません。macOSへの切替は起動時のOptionキーを使ってください。

以前の版で一括セットアップを実行済みの場合、次の救済コマンドはBoot Camp ManagerとControl PanelのMSIを対話表示付きでアンインストールします。Apple Software Updateも削除を試みますが、そちらだけ失敗してもBoot Campの削除は完了扱いにします。導入済みのデバイスドライバーと音声パッチは残します。MSIエラー時は`%LOCALAPPDATA%\BetterCamp\logs`に詳細ログを保存します。

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/snchngny/bettercamp/9adc1f1524ef8397978d45c9b2db8edd2a4aa8b1/run.ps1))) -CleanupBootCamp
```

## 手元のドライバー・最新版を使う

**Boot Campドライバーの最新版と、このリポジトリの最新版は別です。** Appleは最新のWindowsサポートソフトウェアの取得にBoot Campアシスタントを案内しています。

Appleの標準取得方法は、そのMacのmacOSでBoot Campアシスタント → メニューバー「アクション」→「Windowsサポートソフトウェアをダウンロード」です。ただし、このツールの個別導入は検証済みの固定パックに限定します。以下はMacBook Pro用の配置です。Mac miniは前節の完全な`WindowsSupport`を使ってください。

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

MacBook Proで手元にない場合の自動取得は、2012年モデルを対象に含む **Boot Camp 5.1.5621** です。これはAppleのアーカイブ版であり、最新ドライバーと称するものではありません。通常の個別導入は5.1.5621だけを受け付けます。ダウンロード先は `%LOCALAPPDATA%\BetterCamp\downloads` です。取得ごとに別フォルダーを使うため、再利用時は表示されたパスを `-BootCampPath` に渡してください。

オフラインの場合は、別PCで[Apple公式の配布ページ](https://support.apple.com/en-us/106412)からZIPを取得・展開し、上記の `BootCamp` フォルダーをUSB経由で渡せます。古い証明書の検証に失敗した場合は、Windowsの時計とインターネット接続を確認してください。

## 診断・ダウンロードのみ

インストールせず機種・Windowsビルド・GPU・起動方式を確認:

```powershell
.\Start-BetterCamp.cmd -Diagnose
```

ファイルを保存していない場合は次の1行で診断できます。`acpitabl.dat`のhashに加え、Windowsが実際に読み込んだDSDTのOEM revisionとhashも表示します:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/snchngny/bettercamp/9adc1f1524ef8397978d45c9b2db8edd2a4aa8b1/run.ps1))) -Diagnose
```

対応MacBook上で取得・署名検証だけ実行:

```powershell
.\Start-BetterCamp.cmd -DownloadOnly
```

ログは `%LOCALAPPDATA%\BetterCamp\logs` に保存します。診断はログファイルを作成しません。失敗時は画面のエラーとログを確認し、成功と表示されるまで再起動後の動作確認を完了扱いにしないでください。

## UEFI音声パッチ

`MacBookPro9,2`をUEFI起動している場合、通常の1行起動で次も自動実行します。

1. 同梱`dsdt_2012.aml`のSHA-256を検証
2. Windowsがファームウェア側より確実に新しい版として選べるOEM revisionのDSDTを生成し、ACPI checksumを再計算
3. `bcdedit`でWindowsのテスト署名モードを有効化
4. 音声修正済みDSDTをMicrosoft公式の`%SystemRoot%\System32\acpitabl.dat`として配置
5. Boot Camp Managerを除外して個別デバイスドライバーを導入

変更は再起動後に有効になります。テスト署名モードではデスクトップに「テスト モード」の表示が出ます。MicrosoftはACPIテーブル上書きを開発・テスト用とし、起動不能になる可能性を警告しています。実行前にWindows回復環境またはmacOSからWindowsボリュームへアクセスできる状態を用意してください。Secure Bootが有効な場合は適用を停止します。

すでにBoot Campドライバーを導入済みで、音声パッチだけ適用する場合:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/snchngny/bettercamp/9adc1f1524ef8397978d45c9b2db8edd2a4aa8b1/run.ps1))) -AudioPatchOnly
```

元へ戻す場合。登録したDSDTを削除し、BetterCampが今回有効にした場合だけテスト署名モードも無効にします:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/snchngny/bettercamp/9adc1f1524ef8397978d45c9b2db8edd2a4aa8b1/run.ps1))) -RemoveAudioPatch
```

`MacBookPro9,1`、`MacBookPro10,1`、`MacBookPro10,2`には同じDSDTを自動適用しません。元READMEでの2012年実機確認が`MacBookPro9,2`だけで、機種固有ACPIの横断利用を確認できないためです。`-Diagnose`で機種IDを確認できます。Boot Camp導入だけにする場合は`-SkipAudioPatch`を指定できます。

### High Definition Audio Controllerがコード10の場合

初期版は同梱DSDTを元のOEM revisionのまま登録していました。Microsoftの仕様では、レジストリから読み込むACPI tableはファームウェア内の同じtableより高いversionでなければ採用されません。ASLが登録成功を返しても、再起動時に置換DSDTが選ばれず、Intel High Definition Audio Controllerがコード10のまま残る場合があります。

次の修復コマンドは、検証済みDSDTの処理内容を変えずOEM revisionとchecksumだけを更新し、Microsoftが案内する`%SystemRoot%\System32\acpitabl.dat`として起動時に読み込ませます。異なる既存`acpitabl.dat`は上書きしません。テスト署名は再起動後に有効になるため、同じ実行中の`asl /loadtable`には依存しません。続けて`MacBookPro9,2`のCirrus CS4206ドライバーを入れ直してデバイスを再スキャンします。**完了後の再起動が必須です。**

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/snchngny/bettercamp/9adc1f1524ef8397978d45c9b2db8edd2a4aa8b1/run.ps1))) -RepairAudio
```

Legacy BIOS起動ではDSDTを変更しません。`-RepairAudio`はCode 10のIntel HDA controllerだけを削除・再検出し、Cirrus driverを再導入します。完了後は再起動ではなくWindowsを完全にシャットダウンし、20秒待ってから電源を入れてください。

再起動後もコード10なら、デバイスマネージャーの対象デバイスで「詳細」→「ハードウェアID」を確認してください。`PCI\VEN_8086`ならCirrus endpointではなくIntel HDA controllerの初期化失敗です。`HDAUDIO\FUNC_01&VEN_1013&DEV_4206`ならCirrus CS4206です。別IDへ別機種用INFを強制適用しないでください。

`PCI\VEN_8086&DEV_1E20`はIntel Panther Point HDA controllerです。MacBook Pro 2012の類似事例では、BIOS互換起動時はCirrus endpointが`HDAUDIO\FUNC_01&VEN_1013&DEV_4206`として見え、UEFI直接起動時は`DEV_1E20`がCode 10になるという一致した報告があります。この状態では下流のCirrus driverだけを入れ直してもcontrollerが開始しないため直りません。

`-Diagnose`はレジストリの`PEFirmwareType`に加えて、現在のBCD entryが`winload.efi`か`winload.exe`かを表示します。Microsoftの対応は`winload.efi`がUEFI、`winload.exe`がBIOSです。両者が食い違う場合、音声修復は現在実行中のWindows loaderを優先します。これは`PEFirmwareType`がBIOSを示しても、実際に`winload.efi`で動作するMacBookPro9,2でUEFI用DSDT修復が誤ってskipされるのを防ぎます。

**旧 `bettercamp.py`、`bettercamp2.py`、`fix9400.py`、`bclaunch_test.ps1` は新しい起動入口ではありません。** 上流の履歴・素材として保持していますが、直接実行しないでください。

## 改修内容と検証

- Python・WMIC依存の起動手順をWindows標準のPowerShell 5.1へ置換
- 実機の機種IDをCIMで取得し、対象モデルとWindows 11を確認
- 管理者昇格、空白・角括弧・アポストロフィを含むパス、終了コードを処理
- `BootCamp.xml` をXMLとして読み、行番号に依存しないバージョン確認
- Apple公式ZIPの取得、Appleのインストーラー署名確認、ログ保存
- `BootCamp\setup.exe`、`BootCamp.msi`、Apple Software Updateを除外した`MacBookPro9,2`用個別ドライバー導入
- `MacBookPro9,2` UEFI環境のテスト署名設定、DSDT音声パッチ、状態記録と復旧
- ACPI overrideが採用される高いOEM revisionとchecksumの決定的生成、コード10修復入口
- 既存Boot Camp Manager／Control Panel／Apple Software Updateだけを除去する救済入口
- 複数のインストーラーを同時に起動せず、完了まで待機

Windows PowerShell 5.1での回帰テスト:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BetterCamp.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-BetterCampMacmini.ps1
```

テストは機種判定、パス、XML、署名エラー、終了コード、診断入口、音声パッチ適用・失敗時のロールバック・削除を確認し、実際のドライバーや起動設定を変更しません。診断テストの機種、ACPI、BCD、デバイスは隔離した模擬値で、開発PCのMac mini 2018をMacBook Pro 2012の実機検証には使っていません。GitHub Actionsでも同じテストを実行します。

## 出典・既存手段との比較

Apple公式パック内の個別ドライバーを使い、独自ドライバーや配布基盤は追加していません。Apple公式の通常手順は`setup.exe`による一括導入ですが、Windows 11上で旧Boot Camp Managerを常駐させないため、この版では採用していません。Brigadierの機種別取得方式も参考にしつつ、ここでは検証したAppleの固定パックを取得します。Mac miniのPKG・DMG展開には公式7-Zipを使います。新しいドライバーを自作・更新したものではありません。

- [Apple: Boot Camp 5.1.5621の対象機種・ダウンロード](https://support.apple.com/en-us/106412)
- [Apple: Windowsサポートソフトウェアをダウンロード](https://support.apple.com/en-us/102465)
- [Apple: Macmini8,1専用パック041-91731の配布定義](https://swcdn.apple.com/content/downloads/23/15/041-91731-A_LBI7Q8UWOG/juk1ng0hm623gxh3jv4qxt190ga1h5p0lw/041-91731.English.dist)
- [Microsoft: PnPUtilのドライバー選択とコマンド](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/pnputil-command-syntax)
- [7-Zip: 公式配布](https://www.7-zip.org/download.html)・[ライセンス](https://www.7-zip.org/license.txt)
- [Microsoft: WMICの廃止とPowerShellへの移行](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/wmic)
- [Microsoft: ASL CompilerとACPIテーブル上書き](https://learn.microsoft.com/en-us/windows-hardware/drivers/bringup/microsoft-asl-compiler)
- [Microsoft: Windowsテスト署名モード](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/the-testsigning-boot-configuration-option)
- [Microsoft: BIOSとUEFIのWindows loaderの違い](https://learn.microsoft.com/en-ie/troubleshoot/windows-client/performance/windows-boot-issues-troubleshooting)
- [Windows 8 Forums: BIOS互換時とUEFI直接起動時の音声Hardware ID比較](https://www.eightforums.com/threads/sound-driver-windows-8-uefi-boot-no-bios-emulation-mac.25934/)
- [OSR: DEV_1E20はIntel Panther Point HDA controller](https://community.osr.com/t/cant-find-correct-audio-driver-tiny-11-on-macbook-pro-2012/58999)
- [上流READMEとクレジット](docs/UPSTREAM-README.md)

上流のコード・同梱素材・クレジットを保持したForkです。上流にはリポジトリ全体のLICENSEファイルがないため、このForkで第三者素材の利用許諾を新たに付与するものではありません。Appleのドライバーパックはリポジトリに含めず、公式配布元から取得します。
