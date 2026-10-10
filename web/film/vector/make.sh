#!/bin/zsh
# Phim giới thiệu của Pay dạng vector cho peakapp.vn (vẽ bằng canvas như Shot, Peek, Swoop):
#
#   web/film/vector/make.sh <phim> [ngôn ngữ…] [--no-build]      vd  web/film/vector/make.sh again "vi en"
#
# 1. Chạy app trên máy ảo với -filmExport: mỗi khung hình là một trang PDF do chính màn hình của app vẽ (ios/Pay/FilmExport.swift).
# 2. vpack (FilmVectors của Shot, thêm phần đọc PDF kiểu iOS): các trang -> JSON phim.
# 3. peakapp.vn/tools/pack-films.py: nén sang dạng trang web đọc.
# 4. Chép vào peakapp.vn/assets/pay/vfilms. Xong thì tăng VERSION của trình phát Pay trong index.html rồi tools/deploy.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SITE="$HOME/Documents/peakapp.vn"
U="${PAY_SIM:-9144A179-A6A9-488B-B015-AF26A3284037}"
SCENE="$1"; LANGS="${2:-vi en}"; BUILD="${3:-}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

swiftc -O -o "$WORK/vpack" "$ROOT/web/film/vector/FilmVectors.swift" "$ROOT/web/film/vector/main.swift"
cd "$ROOT/ios"
if [ "$BUILD" != "--no-build" ]; then
  xcodebuild -project Pay.xcodeproj -scheme Pay -destination "platform=iOS Simulator,id=$U" -derivedDataPath build/sim build -quiet 2>&1 | grep -E "error:" && exit 1 || true
  xcrun simctl terminate $U com.hnaht95.sochipay 2>/dev/null || true
  xcrun simctl install $U build/sim/Build/Products/Debug-iphonesimulator/Pay.app
fi
mkdir -p "$SITE/assets/pay/vfilms/img"
for lang in ${=LANGS}; do
  xcrun simctl terminate $U com.hnaht95.sochipay 2>/dev/null || true
  C=$(xcrun simctl get_app_container $U com.hnaht95.sochipay data)
  TAKE="$C/Documents/film/$SCENE.$lang"; rm -rf "$TAKE"
  # Ảnh phim cần (màn hình khoá…): chép vào app để nó đọc lúc vẽ
  mkdir -p "$C/Documents/film-assets" && cp "$ROOT/web/film/vector/assets/"* "$C/Documents/film-assets/"
  echo "▸ $SCENE.$lang: khung hình…"
  xcrun simctl launch $U com.hnaht95.sochipay -filmSeed YES -filmLang $lang -filmExport $SCENE >/dev/null
  for i in $(seq 1 300); do [ -f "$TAKE/done" ] && break; sleep 1; done
  xcrun simctl terminate $U com.hnaht95.sochipay 2>/dev/null || true
  [ -f "$TAKE/done" ] || { echo "✗ app không xuất xong $SCENE.$lang" >&2; exit 1; }
  echo "▸ $SCENE.$lang: vector…"
  "$WORK/vpack" "$TAKE" "$WORK/out" "$SCENE.$lang" | tail -1 | cut -c1-160
  python3 "$SITE/tools/pack-films.py" "$WORK/out/$SCENE.$lang.json"
  cp "$WORK/out/$SCENE.$lang.json" "$SITE/assets/pay/vfilms/"
  rm -f "$SITE/assets/pay/vfilms/img/$SCENE.$lang."*(N)
done
cp "$WORK/out/img/"* "$SITE/assets/pay/vfilms/img/"
du -sh "$SITE/assets/pay/vfilms"
