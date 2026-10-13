#!/bin/zsh
# Chụp các màn chính trên máy ảo iOS 18 / 26 / 27, sáng và tối, rồi ghép ảnh so sánh cạnh nhau (mỗi màn một ảnh).
# Chạy trước mỗi lần tải lên TestFlight để thấy giao diện có lệch giữa các bản iOS không.
#
#   scripts/shots.sh                 # dựng app rồi chụp mọi màn
#   scripts/shots.sh -n home stats   # không dựng lại, chỉ chụp các màn cho trước
#
# Kết quả: build/shots/<màn>.png (cột: iOS 18 sáng, 26 sáng, 27 sáng, 18 tối, 26 tối, 27 tối)
set -e
cd "${0:A:h}/.."

BUILD=1
if [[ "$1" == "-n" ]]; then BUILD=0; shift; fi
SCENES=(home home-mid home-end stats settings history house entry)
(( $# )) && SCENES=($@)
VERSIONS=(18 26 27)
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
APP=build/sim/Build/Products/Debug-iphonesimulator/Pay.app
OUT=build/shots
BUNDLE=com.hnaht95.sochipay

# Một máy ảo "Pay iOS <bản>" cho mỗi bản iOS đã cài; tạo nếu chưa có
typeset -A UDID
for v in $VERSIONS; do
  runtime=$(xcrun simctl list runtimes -j | python3 -c "
import json,sys
rs=[r for r in json.load(sys.stdin)['runtimes'] if r['platform']=='iOS' and r['version'].split('.')[0]=='$v' and r['isAvailable']]
print(sorted(rs,key=lambda r:[int(x) for x in r['version'].split('.')])[-1]['identifier'] if rs else '')")
  if [[ -z "$runtime" ]]; then echo "Thiếu máy ảo iOS $v (xcodebuild -downloadPlatform iOS -buildVersion $v...) — bỏ qua"; continue; fi
  name="Pay iOS $v"
  id=$(xcrun simctl list devices -j | python3 -c "
import json,sys
for rt,ds in json.load(sys.stdin)['devices'].items():
  for d in ds:
    if d['name']=='$name' and rt=='$runtime' and d['isAvailable']: print(d['udid']); sys.exit()")
  [[ -z "$id" ]] && id=$(xcrun simctl create "$name" "$DEVICE_TYPE" "$runtime")
  UDID[$v]=$id
done

if (( BUILD )); then
  xcodebuild -project Pay.xcodeproj -scheme Pay -destination "generic/platform=iOS Simulator" \
    -derivedDataPath build/sim build -quiet > build/shots-build.log 2>&1 || { grep -E "\.swift:[0-9]+:[0-9]+: error" build/shots-build.log; exit 1 }
fi

mkdir -p $OUT/raw
for v in ${(k)UDID}; do
  u=$UDID[$v]
  xcrun simctl boot $u 2>/dev/null || true
  xcrun simctl bootstatus $u >/dev/null
  xcrun simctl status_bar $u override --time 9:41 --batteryState charged --batteryLevel 100 --wifiBars 3 2>/dev/null || true
  xcrun simctl install $u $APP
  for mode in light dark; do
    xcrun simctl ui $u appearance $mode
    for s in $SCENES; do
      args=(-filmSeed YES -filmLang vi -proOn YES)
      case $s in
        home) ;;
        home-mid) args+=(-shotScroll 0.5) ;;
        home-end) args+=(-shotScroll 1) ;;
        house) args+=(-shotOpen house -houseDemo YES) ;;
        *) args+=(-shotOpen $s) ;;
      esac
      xcrun simctl launch --terminate-running-process $u $BUNDLE $args >/dev/null
      sleep 4
      xcrun simctl io $u screenshot $OUT/raw/$s-$v-$mode.png >/dev/null 2>&1
    done
  done
done

# Ghép: mỗi màn một hàng 6 ảnh, nhãn ở trên
for s in $SCENES; do
  tiles=()
  for mode in light dark; do
    for v in $VERSIONS; do
      f=$OUT/raw/$s-$v-$mode.png
      [[ -f $f ]] || continue
      magick $f -resize 402x -gravity north -background '#888' -splice 0x40 -pointsize 26 -fill white \
        -annotate +0+6 "iOS $v $mode" $OUT/raw/_t-$v-$mode.png
      tiles+=($OUT/raw/_t-$v-$mode.png)
    done
  done
  (( ${#tiles} )) && magick $tiles -background '#888' -splice 8x0 +append $OUT/$s.png
done
rm -f $OUT/raw/_t-*.png
echo "Ảnh so sánh: $OUT/"
