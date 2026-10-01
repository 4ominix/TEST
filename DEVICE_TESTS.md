# Checklist iPhone bắt buộc — chưa chạy trong phiên Windows

Ghi phiên bản iOS, thiết bị, phiên bản RootHide và SHA256 DEB từ job xanh.
Không phát hành như bản ổn định trước khi có kết quả thiết bị.

1. **Install/remove/reinstall**: Sileo không lỗi, icon xuất hiện, app mở sau force quit,
   cold launch, reboot + jailbreak lại. Không sửa status dpkg bằng tay.
2. **Thiếu bootstrap/quyền**: controller hiển thị chẩn đoán khi shared path lỗi;
   không crash, không ghi vào rootfs. Nếu dyld báo thiếu library, đối chiếu `.ips`.
3. **Media**: ảnh JPEG/PNG/HEIC nhỏ, video H.264/HEVC local và iCloud download;
   hủy picker không đổi nguồn; import hỏng có thông báo và giữ nguồn trước.
4. **Preview**: không tự bật camera ảo khi nhập; loop/end frame video đúng;
   background/foreground không giữ video chạy ngầm và không treo UI.
   Mở picker ngay lúc app vừa khởi tạo, hủy rồi chọn lại; background trong lúc
   khởi tạo/dismiss không tự resume. Đóng/mở Camera control nhiều lần, kiểm tra
   log Auto Layout và đo RAM/timer khi controller/engine được giải phóng.
   Native `tests/engine.m` phải đạt trong CI; test này không thay test UIKit/iPhone.
5. **Injection**: mở Camera trước/sau bật, ghi `Host`, `Hooks`, `Replaced` tăng;
   hook count 0 là thiếu class/ABI hoặc injection, không phải thành công.
   Kiểm tra photo/video/front/rear và một app AVFoundation độc lập. Không suy ra
   toàn bộ app từ một lần test Camera; private pipeline có thể khác theo iOS.
6. **Transforms**: cả 4 góc xoay, mirror sau xoay, Fit/Fill, zoom .25–8,
   mũi tên/reset, pan/pinch; ảnh preview và camera cùng cấu hình.
7. **Fail-safe**: tắt camera trả về nguồn thật; cấu hình hỏng, nguồn bị xóa,
   media không hỗ trợ, decoder/GPU lỗi phải không tiếp tục frame giả cũ.
   Theo dõi crash log `mediaserverd`/`cameracaptured` và RAM khi đổi nguồn liên tục.
8. **Multi-output**: 1080×1440/1584×1188 `420f` đã thấy trước đây, NV12 video range,
   đổi resolution khi record/photo; kiểm tra FPS, timing, orientation, chất lượng màu.
   Mở các output đồng thời; ghi số frame mỗi output, không chỉ tổng `Replaced`.
   Registry giới hạn 3 tổ hợp/48 MiB ước lượng; output không được cache phải về
   camera thật. Kiểm tra việc chuyển format BGRA/420f/420v và metadata màu.
   Test `tests/sample.m` trên macOS phải đạt trước build: nó kiểm tra format
   description từ buffer mới, timing, sample attachments và input lỗi; vẫn cần
   chạy hook thật trên iPhone vì CoreMedia macOS không kiểm chứng private ABI iOS.
9. **Controls**: mặc định tắt; respring rồi bật bảng nổi, nút và kéo bubble hoạt động;
   khóa máy ẩn panel/bubble, mở khóa phục hồi; tắt camera ẩn controls; không chặn UI khác.
   So bố cục Camera control với ảnh gốc: d-pad tròn, xoay giữa, zoom −/+, lật dưới,
   reset/đóng ở đầu; đo các vùng chạm và thử VoiceOver. Xoay thiết bị, kéo bubble
   đến bốn góc để xác nhận bảng không vượt safe area. Tất cả thao tác phải lưu
   cấu hình; header báo lỗi nếu lưu thất bại. Preview phải khớp tỉ lệ vùng hiển thị.
10. **Atomic config**: app + bảng nổi sửa đồng thời không mất trường khác;
    khóa/quyền lỗi phải báo lỗi, không ghi plist một phần.
11. **Offline**: không đăng nhập, không yêu cầu backend; media local làm việc ở chế độ máy bay.
12. **Rollback**: remove bản mới, icon được gỡ; media giữ lại; package manager khỏe;
    nếu quay về bản cũ thì kiểm tra riêng lỗi launch cũ, không coi đó là bản đã được sửa.

Khi crash, lấy `ICamController*.ips` trong Dữ liệu phân tích và crash của camera host;
ghi thời điểm, thao tác ngay trước crash, job/DEB cụ thể. Chẩn đoán UI/preview không
thay được crash log hoặc test thật.
