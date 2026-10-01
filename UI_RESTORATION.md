# Khôi phục giao diện — trạng thái 2026-10-01

Yêu cầu: **Back lại toàn bộ về giao diện gốc**.
**Chưa đánh dấu toàn bộ giao diện khôi phục 1:1 hoàn tất.**

## Đã sửa trực tiếp trong source

- Bảng Camera control theo ảnh gốc: nền đen bo góc, header trái, reset/đóng phải,
  nút tròn lên/trái/xoay/phải/xuống thành chữ thập, zoom −/+/giá trị x, lật ở dưới.
- Tên SF Symbol đối chiếu với binary app/overlay gốc: arrow.up/left/right/down,
  arrow.clockwise, arrow.counterclockwise, chevron.right, minus.magnifyingglass,
  plus.magnifyingglass, arrow.left.and.right và camera.aperture.
- Nút aperture xanh mở bảng nổi, kéo bubble được; placement giới hạn safe area.
- Main shell bỏ nhãn Rebuild và forced dark; nền sáng/title iCamV3/nút chọn media
  theo ảnh iCamV3 trắng đã gửi. **Ảnh này không chứng minh màn hình VCNext gốc.**
  Bảng điều khiển mở qua Camera control, chẩn đoán không chiếm đầu màn hình.
- Preview dùng tỉ lệ viewport thực, không còn luôn render 480×640 rồi ép vào ô khác tỉ lệ.
- Lưu lỗi vẫn báo; overlay khóa máy vẫn fail-closed và pass-through ngoài vùng điều khiển.

## Giữ nguyên

Tên/icon iCamV3 đã yêu cầu, account/backend đã loại bỏ, shared settings và toàn bộ
Core/camera hook/sửa request registry/sample format trước đó. Không copy executable,
network daemon, branding dylib hoặc logic login của VCNext vào package.

## Còn thiếu để xác nhận toàn bộ

App VCNext gốc trong thư mục phân tích chỉ có Mach-O, plist và PNG; không có source
UIKit, storyboard/xib/nib để khôi phục layout tự động. Chuỗi trong binary xác nhận
tên mục và biểu tượng, không chứng minh khoảng cách, màu, font hay toàn bộ màn hình.

Cần ảnh màn hình chính/cài đặt/media của bản gốc (bỏ màn hình login/server như đã
yêu cầu), rồi đối chiếu build mới trên iPhone. Ảnh Camera control hiện có không
đại diện cho mọi màn hình. Đã hỏi thêm ảnh; không suy đoán rồi gọi là nguyên bản.

35 Python tests kiểm tra source/coordinate/action/lifecycle contracts và package fixtures;
không render UIKit, không chứng minh các nút hoạt động trên iPhone. Chưa build/cài
bản UI mới từ phiên Windows này. Checklist thực tế ở `DEVICE_TESTS.md`.

Rà soát bổ sung: height của bảng trong stack dùng priority 999 thay vì required,
tránh chống lại việc collapse khi ẩn. Chỉ kiểm tra source/constraint model, chưa
đo layout hoặc warning của UIKit trên thiết bị. Thay đổi này không thay bố cục bảng nổi.
