// Các câu thử cho bộ đọc giọng nói (QuickParse.spoken). Chạy: ios/Tests/run-quickparse.sh

let cases: [(String, Int?, String)] = [
  // khoản thu
  ("nhận lương mười lăm triệu", 15000000, "nhận lương"), ("lương 15 triệu", 15000000, "lương"), ("được chuyển 500k", 500000, "được chuyển"),
  ("tiền thưởng hai triệu", 2000000, "tiền thưởng"), ("chuyển vào 500k", 500000, "chuyển vào"), ("chuyển vào năm trăm nghìn", 500000, "chuyển vào"),
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
  ("50k 2 ly cafe", 50000, "2 ly cafe"), ("cafe 35k 2 ly", 35000, "cafe 2 ly"), ("₫35.000 cafe", 35000, "cafe"),
  ("ba trăm nghìn hai chục", 320000, ""),
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
  // "rưỡi" sau số trơn; số lẻ nhân 1.000 rồi mới làm tròn
  ("ba lăm rưỡi", 35500, ""), ("hai lăm rưỡi", 25500, ""), ("35 rưỡi cà phê", 35500, "cà phê"), ("25 rưỡi trà sữa", 25500, "trà sữa"),
  ("mười hai rưỡi gửi xe", 12500, "gửi xe"), ("bảy rưỡi", 7500, ""), ("200 rưỡi tiền chợ", 250000, "tiền chợ"), ("100 rưỡi", 150000, ""),
  ("1.000.000 rưỡi", 1500000, ""), ("10.000 rưỡi", 10500, ""), ("35,5 cà phê", 35500, "cà phê"), ("ba lăm nghìn rưỡi", 35500, ""),
  ("thirty five and a half coffee", 35500, "coffee"), ("35.5 coffee", 35500, "coffee"),
  // câu tiếng Việt lẫn chữ tiếng Anh (tên hàng, thương hiệu): có đơn vị tiếng Việt thì đọc kiểu tiếng Việt
  ("mua Number One 2 triệu", 2000000, "mua Number One"), ("sửa xe Grand i10 2 triệu", 2000000, "sửa xe Grand i10"),
  ("bath and body works 1 triệu rưỡi", 1500000, "bath and body works"), ("H and M 2 triệu", 2000000, "H and M"),
  ("Fish and chips 1 triệu 2", 1200000, "Fish and chips"), ("seven eleven 9 nghìn", 9000, "seven eleven"),
  ("mua Number One 10 nghìn", 10000, "mua Number One"), ("mua number one 2 trieu", 2000000, "mua number one"),
  // câu tiếng Anh vẫn đọc kiểu tiếng Anh
  ("200k for gas", 200000, "gas"), ("forty five thousand coffee", 45000, "coffee"), ("a million two rent", 1200000, "rent"),
  ("cà phê 2 million", 2000000, "cà phê"), ("phở 45 thousand", 45000, "phở"), ("mười cái bánh 45 thousand", 45000, "mười cái bánh"),
  // số quá dài (mã giao dịch) và chữ số không phải 0-9: trả nil hoặc bỏ qua, không được văng
  ("12345678901234567890 cafe", nil, ""), ("99999999999999999999tr", nil, ""), ("9999999999999999k cafe", nil, ""),
  ("３５k cafe", nil, ""), ("٣٥k cafe", nil, ""),
  ("ma GD 98765432109876543210 chuyen tien 50k", 50000, "ma GD 98765432109876543210 chuyen tien"),
]
var bad = 0
for (t, a, n) in cases {
  let r = QuickParse.spoken(t)
  let ok = r?.amount == a && (a == nil || r?.note == n)
  if !ok { bad += 1; print("SAI", t, "->", r.map { "\($0.amount) '\($0.note)'" } ?? "nil", " (mong đợi \(a.map(String.init) ?? "nil") '\(n)')") }
  // Câu không ra số tiền còn đi tiếp qua bộ đọc câu gõ (Store.quickAdd): ở đó cũng phải nil, không văng
  if a == nil, let e = QuickParse.expense(t) { bad += 1; print("SAI (gõ)", t, "->", e.amount, "'\(e.note)'", " (mong đợi nil)") }
}

// Ngày và quẹt thẻ (QuickParse.when, rồi đọc số tiền như Store.quickAdd). "Bây giờ" cố định: thứ sáu 16/10/2026 10:30.
// Ngày mong đợi "" = bây giờ (date nil)
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 10, minute: 30))!
let df = DateFormatter()
df.calendar = cal; df.timeZone = cal.timeZone; df.dateFormat = "yyyy-MM-dd HH:mm"
let dated: [(String, Int?, String, String, Bool)] = [
  ("50k cafe thứ hai", 50000, "cafe", "2026-10-12 10:30", false), ("hai trăm nghìn hôm qua", 200000, "", "2026-10-15 10:30", false),
  ("tối qua ăn lẩu 300k", 300000, "ăn lẩu", "2026-10-15 20:00", false), ("sáng qua cafe 30k", 30000, "cafe", "2026-10-15 08:00", false),
  ("trưa qua cơm 40k", 40000, "cơm", "2026-10-15 12:00", false), ("chiều qua trà sữa 45k", 45000, "trà sữa", "2026-10-15 16:00", false),
  ("tối hôm qua nhậu 500k", 500000, "nhậu", "2026-10-15 20:00", false), ("hôm kia đổ xăng 80k", 80000, "đổ xăng", "2026-10-14 10:30", false),
  ("sáng nay phở 50k", 50000, "phở", "2026-10-16 08:00", false), ("tối nay ăn 50k", 50000, "ăn", "", false),
  ("thứ sáu cafe 30k", 30000, "cafe", "", false), ("chủ nhật đi chợ 200k", 200000, "đi chợ", "2026-10-11 10:30", false),
  ("thứ hai tuần trước tiền điện 500k", 500000, "tiền điện", "2026-10-05 10:30", false),
  ("tiền điện 500k thứ hai tuần rồi", 500000, "tiền điện", "2026-10-05 10:30", false),
  ("ngày 12 tiền nước 100k", 100000, "tiền nước", "2026-10-12 10:30", false), ("hôm 20 mua giày 1 triệu", 1000000, "mua giày", "2026-09-20 10:30", false),
  ("ngày 31 cafe 50k", 50000, "cafe", "2026-09-30 10:30", false), ("ngày 16 cafe 50k", 50000, "cafe", "", false),
  ("gửi xe ngày 5 nghìn", 5000, "gửi xe ngày", "", false), ("thứ ba 35 cafe", 35000, "cafe", "2026-10-13 10:30", false),
  ("thứ tư hai trăm nghìn", 200000, "", "2026-10-14 10:30", false), ("năm mươi nghìn thứ năm", 50000, "", "2026-10-15 10:30", false),
  ("lần thứ hai 50k", 50000, "lần thứ hai", "", false), ("vào hôm thứ hai mua sách 120k", 120000, "mua sách", "2026-10-12 10:30", false),
  ("hôm nay cafe 30k", 30000, "cafe", "", false),
  ("50k quẹt thẻ cafe", 50000, "cafe", "", true), ("mua giày 1 triệu trả bằng thẻ tín dụng", 1000000, "mua giày", "", true),
  ("hôm qua quẹt thẻ ăn tối 400k", 400000, "ăn tối", "2026-10-15 10:30", true), ("siêu thị 800k thẻ tín dụng", 800000, "siêu thị", "", true),
  ("nạp thẻ 50k", 50000, "nạp thẻ", "", false),
  // gõ không dấu
  ("hom qua cafe 30k", 30000, "cafe", "2026-10-15 10:30", false), ("toi qua 50k", 50000, "toi qua", "", false),
  ("thu hai trieu", 2000000, "thu", "", false), ("thu 2 cafe 50k", 50000, "cafe", "2026-10-12 10:30", false),
  ("quet the 200k sieu thi", 200000, "sieu thi", "", true),
]
for (t, a, n, d, cr) in dated {
  let w = QuickParse.when(t, now: now, calendar: cal)
  let r = QuickParse.spoken(w.rest) ?? QuickParse.expense(w.rest)
  let got = w.date.map(df.string) ?? ""
  if r?.amount != a || r?.note != n || got != d || w.credit != cr {
    bad += 1
    print("SAI (ngày)", t, "->", r.map { "\($0.amount) '\($0.note)'" } ?? "nil", "'\(got)'", w.credit ? "thẻ" : "", " (mong đợi \(a.map(String.init) ?? "nil") '\(n)' '\(d)'\(cr ? " thẻ" : ""))")
  }
}
// Tiếng Anh: chỉ khi app ở tiếng Anh
Lang.isEnglish = true
let english: [(String, Int?, String, String, Bool)] = [
  ("coffee 45k yesterday", 45000, "coffee", "2026-10-15 10:30", false), ("lunch 100k on monday by card", 100000, "lunch", "2026-10-12 10:30", true),
  ("dinner last night 300k", 300000, "dinner", "2026-10-15 20:00", false), ("this morning coffee 30k", 30000, "coffee", "2026-10-16 08:00", false),
  ("200k for gas with my credit card", 200000, "gas", "", true),
]
for (t, a, n, d, cr) in english {
  let w = QuickParse.when(t, now: now, calendar: cal)
  let r = QuickParse.spoken(w.rest) ?? QuickParse.expense(w.rest)
  let got = w.date.map(df.string) ?? ""
  if r?.amount != a || r?.note != n || got != d || w.credit != cr {
    bad += 1
    print("SAI (ngày)", t, "->", r.map { "\($0.amount) '\($0.note)'" } ?? "nil", "'\(got)'", w.credit ? "card" : "", " (mong đợi \(a.map(String.init) ?? "nil") '\(n)' '\(d)'\(cr ? " card" : ""))")
  }
}
Lang.isEnglish = false
let total = cases.count + dated.count + english.count
print(bad == 0 ? "TẤT CẢ \(total) CÂU ĐÚNG" : "\(bad)/\(total) SAI")
exit(bad == 0 ? 0 : 1)
