import Foundation

extension English {
    static let stats: [String: String] = [
        // ghi chú của dữ liệu mẫu quay phim (Store.filmSeed)
        "ăn trưa": "lunch", "cà phê": "coffee", "ăn sáng": "breakfast", "ăn tối": "dinner",
        "trà sữa": "milk tea", "đi chợ": "groceries", "tiền nhà": "rent", "điện nước": "power & water",
        // Danh mục có sẵn
        "Ăn uống": "Food",
        "Cafe": "Coffee",
        "Đi lại": "Transport",
        "Mua sắm": "Shopping",
        "Hoá đơn": "Bills",
        "Khác": "Other",

        // Thống kê
        "Thống kê": "Stats",
        "Xong": "Done",
        "Tổng chi %@": "Spent in %@",
        "so với cùng kỳ": "vs same period",
        "so với tháng trước": "vs last month",
        "so với hôm trước": "vs previous day",
        "so với tuần trước": "vs last week",
        "so với năm trước": "vs last year",
        "Tuần": "Week",
        "Tháng": "Month",
        "Năm": "Year",
        "Chi %@": "Spent %@",
        "Tổng chi tuần này": "Spent this week",
        "Tổng chi tuần": "Spent that week",
        "Tổng chi năm %@": "Spent in %@",
        "Chi trong tuần": "This week",
        "Chi từng tháng": "By month",
        "Trước": "Previous",
        "Tuần này": "This week",
        "Ít": "Less",
        "Nhiều": "More",
        "Sau": "Next",
        "Hôm nay": "Today",
        "chưa có để so": "nothing to compare",
        "Ngày có chi": "Spending days",
        "%ld%% số ngày": "%ld%% of days",
        "TB mỗi ngày": "Daily avg",
        "Lớn nhất": "Largest",
        "chưa có": "none yet",
        "Số khoản": "Entries",
        "Hạn mức chi tháng": "Monthly limit",
        "Chưa đặt hạn mức. Vào Cài đặt › Ngân sách để đặt.": "No limit set. Go to Settings › Budget to set one.",
        "Chi 6 tháng": "Last 6 months",
        "Chi theo tháng": "By month",
        "bằng mức trung bình": "same as average",
        "cao hơn TB %ld%%": "%ld%% above average",
        "thấp hơn TB %ld%%": "%ld%% below average",
        "Đã chi %@": "Spent %@",
        "Hạn mức %@": "Limit %@",
        "Hạn mức tháng này": "This month's limit",
        "Đã dùng %ld%% của %@": "%ld%% of %@ used",
        "Còn %@/ngày": "%@/day left",
        "Còn %@ · đã dùng %@%%": "%@ left · %@%% used",
        "Vượt %@ · đã dùng %@%%": "%@ over · %@%% used",
        "Chi tiêu khác": "Other spending",
        "Trung bình": "Average",
        "Thấp nhất": "Lowest",
        "Cao nhất": "Highest",
        "Theo danh mục": "By category",
        "Khoản chi gần đây": "Recent expenses",
        "%ld khoản": "%ld items",   // số ít dùng "1 khoản" (EN+Home: "1 item")

        // Thông báo (Model)
        "Đã lưu %@": "Saved %@",
        "Đã xoá": "Deleted",
        "Đã xoá tất cả khoản chi": "All expenses deleted",
        "File sao lưu không hợp lệ": "Invalid backup file",
        "Đã khôi phục %ld khoản": "Entries restored: %ld",   // không theo số ít / số nhiều, để 1 khoản không thành "1 entries"
        "Đã xoá danh mục %@": "Deleted category %@",
        "Sẽ tự ghi ngày %1$ld hằng tháng, lần tới %2$ld/%3$ld": "Repeats monthly on day %1$ld, next on %3$ld/%2$ld",
        "Đã bỏ lặp %@": "Stopped repeating %@",

        // Cột file CSV
        "Ngày": "Date",
        "Giờ": "Time",
        "Số tiền": "Amount",
        "Danh mục": "Category",
        "Ghi chú": "Note",

        // Ngân sách
        "Còn %@": "%@ left",
    ]
}
