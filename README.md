# 🌙 Zép Lào Mod của MilanVu

**Tweak Theos cho Zalo iOS** — bản port lấy cảm hứng từ [ZaloXposed](https://github.com/ElectroHeavenVN/ZaloXposed) (Android), viết lại hoàn toàn bằng Objective-C runtime cho `vn.com.vng.zingalo`.

> ⚠️ Chỉ dùng cho mục đích cá nhân, học tập. Yêu cầu phải có iPhone

---

## ✨ Tính năng

### 👻 Quyền riêng tư
| Tính năng | Mô tả |
|---|---|
| 🙈 Chặn "Đã xem" | Đọc tin thoải mái, người gửi không biết bạn đã xem |
| ⌨️ Ẩn "Đang nhập" | Soạn tin không bị lộ trạng thái đang gõ |

### ↩️ Tin thu hồi & tin xóa
| Tính năng | Mô tả |
|---|---|
| 🛡️ Giữ tin bị thu hồi | Tin vẫn hiển thị trong khung chat dù người kia đã thu hồi |
| 📝 Hiện nội dung tin bị thu hồi/xóa | Nội dung được lưu tạm ngay trên máy bạn |
| 🏷️ Nhãn "đã thu hồi" | Hiện chữ nhỏ mờ trong khung tin được giữ lại, không làm rối giao diện |
| 🧍 Tuỳ chọn áp dụng cho tin do chính bạn thu hồi/xóa | Bật riêng nếu muốn giữ luôn cả tin của mình |
| 📜 Lịch sử tin bị thu hồi/xóa | Xem lại toàn bộ theo thời gian |
| 🧹 Quản lý: xoá đánh dấu, xoá cache tin nhắn, xem User ID | Vài công cụ dọn dẹp nhanh |

### 🚫 Quảng cáo & theo dõi
| Tính năng | Mô tả |
|---|---|
| 🛑 Chặn quảng cáo | Chặn thẳng các máy chủ ads của Zalo |
| 🕵️ Tắt tracking | Không gửi log hành vi sử dụng về Zalo |
| 📡 Chặn log QoS | Bớt được một phần lưu lượng nền |
| 🔥 Tắt Firebase logging | Chặn luôn Crashlytics/Analytics |

### 🖼️ Ảnh, video, file & tự hủy
| Tính năng | Mô tả |
|---|---|
| 📷 Gửi ảnh **Original** mặc định | Tự chọn sẵn chất lượng gốc, khỏi bấm lại mỗi lần |
| 🎞️ Gửi video giữ nguyên gốc *(thử nghiệm)* | Can thiệp thẳng vào bước encode để video không bị ép xuống "HD" |
| 📦 Nâng giới hạn dung lượng gửi | Gửi file/ảnh vượt mức mặc định của Zalo |
| ⏳ Đặt thời gian tự hủy tin (TTL) | Tin tự biến mất sau khoảng thời gian bạn chọn |

### 🪟 Giao diện — Liquid Glass
| Tính năng | Mô tả |
|---|---|
| 💎 **Liquid Glass** cho bảng cài đặt | Ô menu, nút Thu gọn/Xong, từng hàng tính năng — tất cả dùng vật liệu kính trong suốt kiểu iOS 26, tự fallback sang nền mờ khi bật Reduce Transparency |
| 🫧 Thanh tab nổi, kính lỏng *(thử nghiệm)* | Biến thanh `Tin nhắn / Danh bạ / Khám phá / Tường nhà / Cá nhân` ở đáy màn hình thành một **viên thuốc nổi, bo tròn, kính trong suốt**, lơ lửng phía trên nội dung |
| 💧 Hiệu ứng "giọt nước" khi nhấn giữ | Nhấn giữ vào thanh tab rồi kéo qua lại: một viên kính mờ **bám theo ngón tay**, tự "nảy" (spring) và snap sang icon gần nhất — thả tay ra là chuyển tab luôn, y như chạm vào Dynamic Island/Control Center của Apple |
| 🖌️ Tuỳ chỉnh ảnh nền chat | Chọn ảnh từ thư viện, kéo & thu phóng để cắt vừa khung chat, hoặc quay lại ảnh nền mặc định |

### 🧰 Công cụ nâng cao
| Tính năng | Mô tả |
|---|---|
| 🔍 Quét class/method | Dò runtime của Zalo để tìm hàm có thể hook, phục vụ phát triển mod |
| 📄 Xem/chia sẻ kết quả quét | Xuất log ra để debug hoặc gửi báo lỗi |
| ⚙️ Sửa `rules.json` trực tiếp trong app | Chỉnh luật hook mà không cần build lại |
| 🧾 Xem log realtime | Theo dõi mọi hook đang chạy |

---

## 🛠️ Build

Repo build qua **GitHub Actions** ([Randomblock1/theos-action](https://github.com/Randomblock1/theos-action)), 2 job song song:

- `build (rootful)`
- `build (rootless)`

Sau khi Actions chạy xong, tải file `.deb` tương ứng với kiểu jailbreak của máy ở mục **Artifacts**, rồi cài bằng Sideloadly / Filza / trình quản lý package tuỳ môi trường.

---

## ⚠️ Lưu ý

- Các tính năng đánh dấu *(thử nghiệm)* có thể cần **thoát hẳn app** hoặc **quay lại màn hình chính** để áp dụng.
- Đổi `rules.json` sai cú pháp có thể khiến mod không hook được gì — dùng chức năng "Xem log" để kiểm tra.
- Mod phụ thuộc vào cấu trúc nội bộ (private class/selector) của Zalo, nên **mỗi khi Zalo cập nhật phiên bản mới, một vài tính năng có thể cần vá lại**.

---

## 📜 Giấy phép

Dựa trên [ZaloXposed](https://github.com/ElectroHeavenVN/ZaloXposed) — phát hành theo **AGPL-3.0**.
