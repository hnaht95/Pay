// Các câu thử cho bộ đọc giọng nói (QuickParse.spoken). Chạy: ios/Tests/run-quickparse.sh

let cases: [(String, Int?, String)] = [
  // cũ
  ("35k cafe", 35000, "cafe"), ("ba mươi lăm nghìn cà phê", 35000, "cà phê"), ("ba lăm cafe", 35000, "cafe"), ("cafe ba lăm", 35000, "cafe"),
  ("35 cafe", 35000, "cafe"), ("35 nghìn cà phê", 35000, "cà phê"), ("35.000 đồng cà phê", 35000, "cà phê"),
  ("hai trăm rưỡi Shopee", 250000, "Shopee"), ("hai trăm năm mươi nghìn", 250000, ""), ("hai trăm năm", 250000, ""),
  ("hai trăm linh năm nghìn", 205000, ""), ("một triệu hai tiền nhà", 1200000, "tiền nhà"), ("1 triệu 2 tiền nhà", 1200000, "tiền nhà"),
  ("một triệu hai trăm", 1200000, ""), ("một triệu rưỡi", 1500000, ""), ("nửa triệu", 500000, ""), ("3 củ", 3000000, ""),
  ("ba nghìn hai gửi xe", 3200, "gửi xe"), ("grab 52k", 52000, "grab"), ("một ly cafe 35 nghìn", 35000, "một ly cafe"),
  ("mười lăm nghìn trà đá", 15000, "trà đá"), ("bốn mươi lăm nghìn phở", 45000, "phở"), ("1tr2 điện", 1200000, "điện"),
  ("hai trăm 50 nghìn", 250000, ""), ("tám mươi nghìn đổ xăng", 80000, "đổ xăng"), ("cafe", nil, ""),
  ("mười nghìn rưỡi", 10500, ""), ("hai chục rưỡi", 25000, ""), ("năm chục rưỡi", 55000, ""), ("năm chục", 50000, ""),
  ("hai mươi mốt nghìn", 21000, ""), ("hai mươi tư nghìn", 24000, ""), ("ba mươi nhăm", 35000, ""), ("ba mốt", 31000, ""),
  ("một trăm lẻ năm nghìn", 105000, ""), ("một trăm linh năm", 105000, ""), ("trăm hai", 120000, ""), ("một trăm hai", 120000, ""),
  ("hai trăm mốt", 210000, ""), ("triệu hai", 1200000, ""), ("triệu rưỡi", 1500000, ""), ("triệu mốt", 1100000, ""),
  ("một trăm hai mươi lăm nghìn", 125000, ""), ("hai triệu ba trăm nghìn", 2300000, ""), ("một tỷ hai", 1200000000, ""),
  ("ba ngàn", 3000, ""), ("một trăm rưỡi", 150000, ""),
  ("1.000.000 2", 1200000, ""), ("1000000 2 tiền nhà", 1200000, "tiền nhà"), ("2.000.000 5", 2500000, ""), ("1.000.000", 1000000, ""),
  ("1 triệu 2.", 1200000, ""), ("10.000 5", 10500, ""), ("35.000 2", 35200, ""), ("1.500.000", 1500000, ""),
  ("10.000.002", 10200000, ""), ("10000002", 10200000, ""), ("45000", 45000, ""), ("1,5 triệu", 1500000, ""),
  ("1.000.002 tiền nhà", 1200000, "tiền nhà"), ("mười triệu 2", 10200000, ""), ("10 triệu 2", 10200000, ""), ("1.002", 1200, ""),
  ("45.000", 45000, ""), ("1.250.000", 1250000, ""), ("1.000.005", 1500000, ""),
  // lỗi vừa tìm ra
  ("tiền nhà tháng sau 3 triệu", 3000000, "tiền nhà tháng sau"), ("tiền điện tháng tư 500 nghìn", 500000, "tiền điện tháng tư"),
  ("học phí năm 2 triệu", 2000000, "học phí năm"), ("mua quà cho ba 200 nghìn", 200000, "mua quà cho ba"),
  ("ba ly cà phê 35.000đ", 35000, "ba ly cà phê"), ("cà phê 35.000₫", 35000, "cà phê"),
  ("tôi ăn phở 50 nghìn", 50000, "tôi ăn phở"), ("tối nay ăn 50k", 50000, "tối nay ăn"), ("vé máy bay 2 triệu", 2000000, "vé máy bay"),
  ("làm tóc 100k", 100000, "làm tóc"), ("mua củ cải 20k", 20000, "mua củ cải"), ("đổ xăng 2 lít 50k", 50000, "đổ xăng 2 lít"),
  ("mua tỏi 20k", 20000, "mua tỏi"), ("điện thoại cũ 3 triệu", 3000000, "điện thoại cũ"), ("thêm 1 ly nữa 30k", 30000, "thêm 1 ly nữa"),
  ("canh chua 50k", 50000, "canh chua"), ("chúc mừng sinh nhật 200k", 200000, "chúc mừng sinh nhật"), ("đóng tiền nhà 3 triệu", 3000000, "đóng tiền nhà"),
  ("tiền điện tháng tư", nil, ""), ("năm nay", nil, ""), ("ba mẹ", nil, ""),
  // gõ không dấu
  ("ba muoi lam nghin cafe", 35000, "cafe"), ("ve may bay 2 trieu", 2000000, "ve may bay"), ("toi an pho 50k", 50000, "toi an pho"),
]
var bad = 0
for (t, a, n) in cases {
  let r = QuickParse.spoken(t)
  let ok = r?.amount == a && (a == nil || r?.note == n)
  if !ok { bad += 1; print("SAI", t, "->", r.map { "\($0.amount) '\($0.note)'" } ?? "nil", " (mong đợi \(a.map(String.init) ?? "nil") '\(n)')") }
}
print(bad == 0 ? "TẤT CẢ \(cases.count) CÂU ĐÚNG" : "\(bad)/\(cases.count) SAI")
exit(bad == 0 ? 0 : 1)
