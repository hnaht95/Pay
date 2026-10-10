#!/bin/sh
# Chạy bộ câu thử của QuickParse.spoken mà không cần máy ảo: ghép strip() + QuickParse + các câu thử rồi biên dịch.
set -e
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
{
  echo 'import Foundation'
  echo 'enum Lang { static var isEnglish = false }   // QuickParse đọc theo ngôn ngữ của app; câu thử chạy kiểu tiếng Việt'
  sed -n '/^func strip/,/^}/p' Pay/Category.swift
  sed 1d Pay/QuickParse.swift
  cat Tests/QuickParseCases.swift
} > "$tmp/main.swift"
swiftc -o "$tmp/run" "$tmp/main.swift"
"$tmp/run"
