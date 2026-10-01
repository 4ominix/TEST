# Kết quả kiểm tra chức năng — 2026-10-01

**Chưa xác nhận tất cả chức năng thực sự hoạt động trên iPhone.**
Nguồn có triển khai các tính năng dưới đây. Host tests đạt không đồng nghĩa app
khởi động, GPU render hoặc injection hoạt động trên thiết bị.

| Chức năng | Đã kiểm tra | Kết quả thực tế trên iPhone |
|---|---|---|
| Không đăng nhập/backend/OBS | Quét mã nguồn; checker từ chối API mạng/legacy được liệt kê | Chưa test chế độ máy bay |
| Chọn ảnh/video | Rà PHPicker, sao chép URL trong callback, probe trước commit | Chưa test local/iCloud/HEIC/HEVC |
| Preview và video lặp/giữ frame cuối | Rà decoder, bounded sample loop; sửa timer retain-cycle và stop/start race; picker chủ động pause/resume | Chưa chạy decoder/GPU iOS |
| Bật/tắt và thay camera | Rà 5 selector, ABI guard, sample ownership, fallback | Chưa có hook/frame trên thiết bị của bản mới |
| Fit/Fill, xoay/lật, zoom/pan/mũi tên/reset | 42 assertion của C geometry bằng AST interpreter; rà UI mapping | Chưa so preview với Camera |
| Nhiều kích thước/định dạng camera | Sửa registry 3 slot; 10 assertion C bằng AST interpreter | Chưa đo FPS/độ trễ/các output đồng thời |
| Format/timing/attachments | Sửa tạo description từ pixel mới; test cấu trúc đạt; thêm native CoreMedia test | Native CoreMedia test và hook iOS chưa chạy |
| Lưu cấu hình dùng chung | Rà flock/atomic/path/quyền; native storage test đã có trong CI | Chưa xác nhận quyền RootHide và ghi đồng thời trên iPhone |
| Điều khiển nổi | Đã sửa bố cục theo ảnh Camera control; rà SpringBoard, pass-through và lockstate; mặc định tắt | Chưa test render UIKit/respring/khóa máy/điều khiển |
| Fail-safe | Rà try-lock, watchdog .75s, ngân sách 3 cache/48 MiB, gọi original khi lỗi | Chưa fault injection trên mediaserverd/cameracaptured |
| Cài/gỡ, icon, arm64/arm64e | Kiểm tra plist/Makefile/script; 35 Python tests gồm UI/source contracts và binary/package fixture tổng hợp | Chưa build/check DEB mới hoặc cài thiết bị |

## Bằng chứng và giới hạn

- 35 Python regression tests đạt trên Windows. Fixtures Mach-O/DEB trong tests là
  **tổng hợp**, không phải binary sản xuất đã build hoặc ký hợp lệ trên iOS.
- 42 geometry + 10 request assertions chạy **C AST interpreter**. Đây không phải
  compiler native, không kiểm tra thread scheduling, CoreImage hay iOS frameworks.
- Registry/sample fixes dựa trên mã nguồn và yêu cầu API; không khẳng định đây là
  nguyên nhân crash trước đó khi chưa có `.ips`.
- Workflow có native C/Foundation/CoreMedia/engine ARC-GCD tests và build Theos; chưa có kết quả
  job tương ứng với các thay đổi này. Chưa có DEB mới trong thư mục nguồn.
- Không có kết nối iPhone đang hoạt động được xác nhận trong phiên kiểm tra.

## Tiêu chí để xác nhận hoạt động

1. Job CI của đúng source hash phải xanh: native tests, build, checker binary thực tế.
2. Ghi SHA256 DEB, model/iOS/RootHide; thực hiện toàn bộ `DEVICE_TESTS.md`.
3. Camera thật phải hiển thị nguồn đã chọn; `Hooks > 0` và `Replaced` tăng cùng
   bằng chứng hình ảnh trên từng đường preview/photo/video/front/rear được thử.
4. Tắt hoặc gây lỗi nguồn phải trả camera thật; không crash/treo camera host.

Chỉ tổng frame tăng hoặc preview trong app là chưa đủ để chứng minh toàn hệ thống.

## Rà toàn bộ source sau khôi phục UI

- Timer chỉ giữ weak reference đến engine; engine hủy timer khi được giải phóng.
  Test native `tests/engine.m` kiểm tra engine chạy/dừng được giải phóng, đã thêm
  vào CI nhưng chưa chạy trong phiên Windows.
- Completion khởi tạo kiểm tra `wantsPreview`, controller đang hiển thị và không
  có sheet khác. PHPicker pause trước khi mở và resume ở completion dismiss kể cả
  khi hủy chọn; không chỉ dựa vào `viewDidAppear` của page sheet.
- Chiều cao bảng Camera control dùng priority 999 để nhường khi stack bị ẩn.
  Đây là sửa nguy cơ suy ra từ constraints, chưa tái hiện warning UIKit trên iPhone.
- Ba source-contract tests mới đều bắt lỗi của baseline và các mutation đối chứng.
  Chúng không chứng minh ARC, scheduler hoặc Auto Layout native đã chạy đúng.

Giao diện: xem `UI_RESTORATION.md`. Ảnh Camera control là reference đã có;
toàn bộ màn hình chính/cài đặt của VCNext gốc chưa có đủ ảnh, không đánh dấu khôi
phục 1:1 hoàn tất và không đưa binary có login/server trở lại gói mới.
