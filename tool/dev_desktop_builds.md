# dev ビルドのデスクトップ版 (Linux / Windows / macOS)

dev prerelease (タグ `dev`) には、CI が自動ビルドするモバイル版
(APK / IPA) に加えて、デスクトップ版も含める。

デスクトップ版のうち Windows は CI (`.github/workflows/dev-build.yml`
の windows ジョブ) が自動ビルドして資産を差し替える。Linux / macOS は
CI では作らない。dev ビルドのたびに担当がこの手順で作り、資産を
差し替える。資産名は固定で、差し替えで更新する
(ダウンロード URL は変わらない)。

| プラットフォーム | 資産名 | ビルド機 |
|---|---|---|
| Linux | `TorneMobileHomeBrew-dev-linux.tar.gz` | marnux |
| Windows | `TorneMobileHomeBrew-dev-windows.zip` | GitHub Actions (windows-latest) |
| macOS | `TorneMobileHomeBrew-dev-macos.zip` | Mac (署名後に任意で掲載) |

CI (`.github/workflows/dev-build.yml`) の prerelease 資産整理は、
上記のデスクトップ資産を保持リストに入れてあり、モバイル版の更新で
消えることはない。逆に、Linux / macOS の資産はこの手順で差し替えない
限り古いまま残るので、dev ビルドのたびに作り直すこと。

版数は pubspec.yaml のまま据え置く (版数を上げるのは実機確認が
通った正式リリース時だけ、という運用は dev でも同じ)。

## Linux (marnux)

```sh
cd ~/GitTmp/myClaude/TorneMobileHomeBrew
git pull
tool/build_linux_desktop.sh
# build/TorneMobileHomeBrew-linux-<version>.tar.gz ができる
cp build/TorneMobileHomeBrew-linux-<version>.tar.gz \
  /tmp/TorneMobileHomeBrew-dev-linux.tar.gz
gh release upload dev /tmp/TorneMobileHomeBrew-dev-linux.tar.gz \
  --repo mar1mo-41414/TorneMobileHomeBrew --clobber
```

`~/ダウンロード/TMHB/` は正式リリース専用なので dev は置かない。

## Windows (GitHub Actions)

dev ビルドでは CI の windows ジョブが自動でビルドし、
`TorneMobileHomeBrew-dev-windows.zip` を prerelease に掲載する。
CI のパッケージングは、以下の手作業手順と同じ構成
(Release の中身を `TorneMobileHomeBrew-dev-windows` フォルダに
入れた zip) に揃えてある。手元で作る必要がある場合は marog で
この手順を使う。

```powershell
cd $env:USERPROFILE\GitTmp\MyClaude\TorneMobileHomeBrew
git pull
flutter build windows --release
# build\windows\x64\runner\Release\ の中身が成果物
```

- zip: 中身を `TorneMobileHomeBrew-dev-windows` フォルダに入れて
  zip 化し、`TorneMobileHomeBrew-dev-windows.zip` として
  `gh release upload dev --clobber` で掲載する
  (正式リリースの zip と同じトップフォルダ付きの構成)。
- 実機確認用に、Desktop の `TorneMobileHomeBrew` フォルダの中身も
  新しいビルドに差し替える。Desktop にはフォルダだけを置き、
  zip は置かない。

## macOS (Mac)

署名は CI / リモートではしない。本人がローカルのターミナルで
署名コマンドを打つ運用なので、担当側はビルドとステージまでを行う。

```sh
cd ~/GitTmp/MyClaude/TorneMobileHomeBrew
git pull
tool/build_macos_desktop.sh
```

- ビルドは必ずこのスクリプト経由にする。`.xcworkspace` 経由でない
  xcodebuild は CocoaPods の embed 工程が走らず、フレームワーク
  欠落で起動不能な .app になる (スクリプト内に同梱ガードがある)。
- 成果物の .app は `build/macos/Build/Products/Release/` に残る。
  署名と `~/Applications` への配置は本人が行う。
- 署名後の zip を `TorneMobileHomeBrew-dev-macos.zip` として
  prerelease に掲載するのは任意 (Mac ではローカル配置が正規経路)。
