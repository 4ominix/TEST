# iCamV3 Rebuild 2.0.0

Bản viết lại trong thư mục mới, không dùng mã hook của binary VCNext cũ.
Bảng Camera control đã dựng lại theo ảnh gốc và tên SF Symbol trong binary gốc.
Xem `UI_RESTORATION.md`: chưa có đủ ảnh để xác nhận toàn bộ màn hình gốc giống 1:1.
Package: `com.icamv3.rebuild`; app: `ICamController.app`; tên trên màn hình: **iCamV3**.

**Trạng thái:** mã nguồn và bộ kiểm tra có sẵn. Kiểm tra Python trên Windows
không thay thế việc biên dịch iOS hay chạy thử iPhone. Chưa xác nhận bản viết lại
khởi động/thay camera thành công trên thiết bị. Xem `DEVICE_TESTS.md` trước khi phát hành.

## Chức năng được triển khai

- PHPicker chọn một ảnh hoặc video từ thư viện; sao chép tệp trong callback trước khi URL tạm hết hạn.
- Preview độc lập; ảnh/video làm nguồn frame camera qua hook private BW đã quan sát trước đó.
- Bật/tắt, video lặp/giữ frame cuối, lật ngang **trong tọa độ đầu ra**, xoay 0/90/180/270, Fit/Fill.
- Dịch chuyển bằng nút mũi tên hoặc vuốt preview; zoom bằng nút hoặc pinch.
  Vuốt/pinch áp dụng khi kết thúc cử chỉ; nút áp dụng ngay sau lưu.
- Cấu hình schema 2 dùng `flock` và ghi plist atomic; mỗi tiến trình đọc lại khoảng 0.5 giây.
- Bảng điều khiển nổi trong SpringBoard có di chuyển nút, mũi tên, xoay, zoom và đặt lại;
  mặc định **tắt**, ẩn khi khóa màn hình hoặc không đọc được trạng thái khóa.
  Nút camera.aperture xanh mở bảng nhỏ; nút tròn bố trí chữ thập, xoay xanh giữa,
  zoom −/+, lật xanh lam dưới, reset và đóng ở đầu bảng, theo ảnh Camera control.
  Trong app, nút Camera control mở/đóng cùng bảng; chẩn đoán nằm trong phần thông tin.
- Chẩn đoán số hook/frame từ từng camera host. **Preview không chứng minh injection camera.**
- Không có đăng nhập, tài khoản, giới hạn thiết bị, backend, lease/token, daemon mạng,
  OBS/RTMP, color picker, nhận diện mặt, privacy mask hay obfuscation.

## Kiến trúc và bảo vệ camera

| Thư mục | Vai trò |
|---|---|
| `App` | Controller UIKit arm64; dựng giao diện trước, media engine sau `viewDidAppear` |
| `Camera` | Tweak arm64 + arm64e cho `mediaserverd` / `cameracaptured`; kiểm tra ABI trước hook |
| `Controls` | Tweak SpringBoard cho bảng nổi tùy chọn |
| `Core` | Đường dẫn RootHide, cấu hình, decoder, geometry và cache frame |
| `UI` | Nút điều chỉnh dùng chung |
| `layout/DEBIAN` | Đăng ký app bằng uicache, chuẩn bị thư mục/quyền, gỡ đăng ký khi remove |
| `tools`, `tests` | Manifest, kiểm tra gói và hồi quy; không đưa vào payload DEB |

App không liên kết trực tiếp libroothide/libsubstrate. Đường dẫn được lấy qua
`jbroot` có sẵn hoặc symlink `.jbroot` bên cạnh executable/dylib; thiếu bootstrap
thì hiển thị lỗi, không ghi vào `/var/mobile/Library` thật. Cơ chế symlink này theo
[tài liệu RootHide](https://github.com/roothide/Developer/blob/main/roothide.md).
Shared media nằm trong **jbroot** `/var/mobile/Library/iCamV3Rebuild`, độc lập dữ liệu cũ.

Hook chỉ lấy frame cache với try-lock; không giải mã, render hoặc đọc cấu hình
trong callback camera. Cache chưa sẵn/định dạng không hỗ trợ/lỗi decoder thì gọi
implementation gốc với sample nhận vào. Sample thay thế mới giữ timing và attachment;
worker không tiến triển hơn 0.75 giây thì ngừng trả frame cache cũ.
không ghi đè pixel của sample camera thật. Điều này giảm nguy cơ treo, nhưng không
bảo đảm miễn crash: private ABI, dylib injection, driver GPU và lỗi native vẫn cần thử trên máy.

BGRA/NV12 `420f`/`420v` được hỗ trợ; frame đích tối đa 4096 mỗi chiều, 6 megapixel.
Cache tối đa 3 tổ hợp kích thước/định dạng, 48 MiB **ước lượng pixel**, không phải tổng RAM tiến trình.
Request registry cố định 3 slot giữ các đầu ra đang hoạt động; không để một callback
ghi đè duy nhất kích thước của callback trước. Tổ hợp ngoài giới hạn có thể trở về
camera thật, không hứa mọi resolution đều được thay đồng thời.
Format description được tạo từ pixel buffer thay thế, thay vì tái sử dụng format
camera thật chỉ vì cùng kích thước/fourcc. Timing và sample attachments được giữ.
Điều kiện format/attachment tương thích theo [CoreMedia của Apple](https://developer.apple.com/documentation/coremedia/cmsamplebuffercreateforimagebuffer(allocator:imagebuffer:dataready:makedatareadycallback:refcon:formatdescription:sampletiming:samplebufferout:)).
Ảnh tối đa 32 MP/8192 mỗi chiều; video tối đa 8.3 MP/4096 mỗi chiều.
Video không phát audio; decoder giới hạn 8 sample/tick và không chạy trong callback.
Worker tối đa 30 fps, preview 15 fps; stop/pause xả nguồn, cache GPU; camera nhàn rỗi
hơn 2 giây xả decoder. Media quá nặng vẫn có thể ảnh hưởng bộ nhớ/độ trễ trên thiết bị.
Timer không giữ engine qua strong capture; khi engine được giải phóng thì timer
bị hủy. Controller chặn completion khởi tạo sau stop/background và pause/resume
picker rõ ràng, kể cả hủy chọn trong page sheet.

## Upload GitHub và tạo DEB

1. Upload **nội dung** thư mục này vào root repository. Phải có cả `.github/workflows`,
   `.gitattributes`, `.gitignore`, `SOURCE_SHA256.json`, `tools` và `tests`.
   Không ghép `scripts/verify_entitlements.py` hay workflow của bản cũ vào dự án mới.
2. Actions → **Build iCamV3 Rebuild RootHide** → Run workflow.
3. Workflow chạy kiểm tra manifest, Python, native geometry/request registry,
   Foundation storage, CoreMedia sample compatibility và ARC/GCD engine lifetime trên macOS;
   chuẩn bị RootHide Theos; build rồi kiểm tra **binary đã đóng gói**.
4. Chỉ job xanh mới upload artifact `iCamV3-Rebuild-RootHide-DEB`.
   Download artifact và cài file `.deb` bên trong qua Sileo đang chạy trong RootHide.

Không cần biến THEOS trong PowerShell Windows để dùng GitHub Actions.
Để build trên máy macOS có RootHide Theos:

```sh
python3 tools/verify_release.py manifest
python3 tools/verify_release.py source
python3 tests/test_release.py
chmod 755 layout/DEBIAN/postinst layout/DEBIAN/prerm
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

Khi **chủ động sửa nguồn**, cập nhật manifest rồi commit toàn bộ file thay đổi:

```sh
python3 tools/verify_release.py manifest --write
python3 tools/verify_release.py manifest
```

Manifest phát hiện upload thiếu/lẫn phiên bản, không phải chữ ký xác thực.
Checker đọc entitlement từ từng Mach-O slice trực tiếp, không dùng output XML nối
từ `ldid -e` và không gọi `lipo -verify_arch` sai thứ tự. Kiểm tra CodeDirectory là
**cấu trúc**, không phải xác thực mật mã hay chứng minh app được iOS cho chạy.

## Chuyển từ bản cũ và khôi phục

Metadata `Conflicts/Replaces: com.icamv3.app` yêu cầu dpkg xử lý thay package cũ.
Không tự sửa database dpkg và không xóa source cũ. Nếu Sileo có lỗi `reinstreq`,
khôi phục package manager trước; không ép cài bản mới để che lỗi trạng thái đó.
Sau cài đặt, mở app, nhập ảnh nhỏ, bật camera, mở Camera và xem bộ đếm trong app.
Respring khi cần nạp bộ điều khiển nổi. Trên RootHide cần camera host được phép
injection; chỉ có icon app không chứng minh tweak đã nạp.

Để quay lại: tắt camera/bảng nổi, remove `com.icamv3.rebuild` bằng Sileo; cài lại DEB
cũ đã giữ nếu cần. Media/schema mới không tự xóa khi remove. Không có thao tác
gỡ/cài nào được thực hiện trên iPhone từ máy Windows này.

## File cũ đã nhận và chẩn đoán còn thiếu

`com.icamv3.app_1.3.1_iphoneos-arm64e.deb` SHA256:
`e5856689a30344f669477dce1a0f656f59dfd319b2738155a29d3e876f12cd35`.
App trong gói cũ có arm64/arm64e, minimum iOS 15 và đủ 4 entitlement;
không xác nhận thiếu entitlement là nguyên nhân crash. App có dependency
`@loader_path/.jbroot/usr/lib/libroothide.dylib`; thiếu library/symlink là **giả thuyết**,
không phải lỗi đã chứng minh. Bản mới tránh hard dependency đó.
Chưa có `.ips` hoặc kết quả dyld/injection trên iPhone để xác định nguyên nhân chính xác.

## Lần rà soát chức năng 2026-10-01

Xem `FEATURE_STATUS.md`: phân biệt kiểm tra nguồn/host với native build và iPhone.
Hai thay đổi frame ở trên được rà soát và thêm test; chưa phải kết quả tái hiện
hoặc khắc phục crash đã đo được trên iPhone. Native tests được thêm vào workflow,
không được tính là đã chạy chỉ vì mã test tồn tại.

Rà soát tiếp sau khôi phục UI: sửa retain-cycle của frame timer, race giữa start/stop
preview và height required trong stack ẩn. 35 Python tests kiểm tra source/fixtures;
native engine lifetime test có trong CI nhưng chưa chạy ở phiên Windows. Không
khẳng định đã hết mọi lỗi hoặc ổn định trên iPhone chỉ từ các kiểm tra này.
