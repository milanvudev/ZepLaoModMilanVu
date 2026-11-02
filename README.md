# Zép Lào Mod của MilanVu (bản port iOS từ ZaloXposed Android)

Bản mod này dựa trên ZaloXposed của ElectroHeavenVN (AGPL-3.0). Giữ nguyên giấy phép và ghi công tác giả gốc.

Tweak Theos cho Zalo iOS, port từ https://github.com/ElectroHeavenVN/ZaloXposed (AGPL-3.0, giữ nguyên giấy phép).
Dùng thuần Objective-C runtime, không cần Logos.

> Dùng tweak có thể vi phạm điều khoản của Zalo và có nguy cơ bị khóa tài khoản. Tự chịu rủi ro.

## Trạng thái từng tính năng (đọc kỹ)

Bản Android hook vào class Java đã bị obfuscate, tìm bằng DexKit theo chuỗi/hằng số. iOS không có các class đó,
và tên class/method của Zalo iOS không có trong repo gốc. Vì vậy:

| Tính năng | Trạng thái |
|---|---|
| Chặn endpoint ads / QoS / tracking / Firebase | Chạy ngay (hook NSURLSession). Chỉ có tác dụng với request đi qua NSURLSession; nếu Zalo dùng socket/curl riêng thì không chặn được. |
| Firebase Analytics `logEventWithName:` | Chạy ngay (rule mặc định, chỉ có tác dụng nếu app có FIRAnalytics) |
| Anti-Recall / Anti-Delete | Logic đã port đầy đủ (`ZXAntiRecall.m`), **cần bạn trỏ vào đúng method nhận gói tin** (1 rule) |
| Chặn "Đã xem", Không gửi "Đang nhập" | Engine sẵn sàng, **cần rule trỏ vào đúng method** |
| Ghi đè TTL | Engine sẵn sàng, **cần rule** |
| Màn hình cài đặt trong app | Chạy ngay: nút "Zép Lào Mod của MilanVu" ở cuối trang Cài đặt của Zalo (hoặc nhấn giữ 3 ngón tay 0.8 giây) |
| Không port | Mở khóa tính năng trả phí (Z Cloud), spoof chữ ký/package, Chat Head, menu/tab tùy biến, Google Drive backup (đặc thù Android hoặc né thanh toán) |

Chưa có bản build thử trên thiết bị: môi trường tạo gói này không có Theos/iOS SDK, nên code chưa được biên dịch.
Nếu build lỗi, gửi log cho mình để sửa.

## Tìm target hook (làm 1 lần cho mỗi phiên bản Zalo)

1. Mở Zalo đã tiêm tweak, nhấn giữ 3 ngón tay -> **Quét class/method** -> **Xem / chia sẻ kết quả quét**.
   Danh sách gồm các method có tên chứa recall/undo/seen/typing/ttl... của app (scan.txt, AirDrop/Lưu vào Files).
   Cách chính xác hơn: dùng `class-dump` / `dsdump` / Hopper trên IPA đã giải mã.
2. Chọn đúng method, rồi sửa `rules.json` ngay trong app (Công cụ -> Sửa rules.json). Ví dụ trong `rules.example.json`.
3. Thoát app và mở lại để rule có hiệu lực. Xem **log.txt** để biết rule nào hook thành công.

Gợi ý theo logic Android:
- Anti-Recall: tìm method xử lý gói tin chat nhận về, có tham số là JSON (NSDictionary / NSString / NSData) chứa `chat.undo`,
  `chat.delete`. Dùng `"action": "antirecall"` + `"argIndex"` (đếm từ 1, không tính self/_cmd). Hook tự tìm đệ quy khóa `msg`.
- Seen: method gửi danh sách tin đã đọc lên server -> `"action": "skip"`, `"configKey": "block_send_seen"`.
- Typing: method gửi trạng thái đang gõ -> `"action": "skip"`, `"configKey": "enable_silent_typing"`.
- TTL: method trả về TTL (số nguyên) -> `"action": "ttl"`.
- Điền **User ID** của bạn trong cài đặt để phân biệt tin do mình thu hồi/xóa.

Giới hạn của engine: method chỉ có tham số kiểu số nguyên/con trỏ (tối đa 6), không có tham số float/double/struct,
kiểu trả về void hoặc số nguyên/con trỏ. Method không đạt sẽ bị bỏ qua và ghi vào log.

## Build ra file .deb

Cách 1: máy Mac có Theos
```
export THEOS=~/theos
make package FINALPACKAGE=1                              # rootful
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless # rootless
```
File nằm trong `packages/`.

Cách 2: không có Mac -> đẩy thư mục này lên GitHub, tab Actions -> "Build deb" -> Run workflow, tải artifact
(`.github/workflows/build.yml`, build cả rootful và rootless).

## Tiêm vào Zalo
- Máy jailbreak: cài .deb. Filter nhắm `vn.com.vng.zingme`. Hãy kiểm tra bundle id Zalo trên máy bạn và sửa `ZaloXposediOS.plist` nếu khác.
- Không jailbreak: dùng Sideloadly/TrollStore, kéo IPA Zalo (đã giải mã) + file .deb/.dylib vào mục Inject. Nếu báo thiếu Substrate, bật tùy chọn inject Substrate/ElleKit trong Sideloadly.
- Dữ liệu (rules.json, scan.txt, log.txt) nằm trong thư mục `Documents/ZaloXposed` của app.

## Cấu trúc
`Tweak.m` (khởi tạo) · `ZXConfig` (cài đặt) · `ZXHookEngine` (hook theo rules.json) · `ZXAntiRecall` (port `processMsgPayload`) ·
`ZXNetwork` (chặn request) · `ZXScanner` (tìm target) · `ZXUI` (màn hình cài đặt)
