#!/bin/sh
# Chạy bộ câu thử của QuickParse.spoken mà không cần máy ảo: ghép strip() + QuickParse + các câu thử rồi biên dịch.
set -e
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
{
  echo 'import Foundation'
  sed -n '/^func strip/,/^}/p' Pay/Category.swift
  sed 1d Pay/QuickParse.swift
  cat Tests/QuickParseCases.swift
} > "$tmp/main.swift"
swiftc -o "$tmp/run" "$tmp/main.swift"
"$tmp/run"
