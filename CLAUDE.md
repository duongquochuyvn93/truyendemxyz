# truyendem.xyz — website truyện chữ

## Mục tiêu

Website đọc truyện chữ tiếng Việt. Tác giả tự viết và đăng thủ công qua WordPress local. Monetize bằng affiliate Shopee (gate JS). Hosting $0/tháng.

## Kiến trúc

```
Tác giả viết trong WP-Admin (local, không public)
        ↓
Simply Static export → e:\taotruyen (HTML/CSS/JS tĩnh)
        ↓
git push → Cloudflare Pages → truyendem.xyz
```

- WordPress chỉ bật khi đăng bài mới, tắt khi không dùng
- Site tĩnh trên Cloudflare chạy 24/7, không phụ thuộc máy local

## WordPress setup

- **Theme**: Blocksy (free, wordpress.org)
- **Plugins**: Custom Post Type UI + Advanced Custom Fields (ACF) + Simply Static
- **URL local**: `http://truyendemxyz.local`
- **Application Password**: xem `scripts/.env` (gitignored, không commit)

### Post types

| Post type | Slug | ACF fields |
|---|---|---|
| Truyện | `truyen` | cover_image, mo_ta, the_loai, trang_thai, shopee_link |
| Chương | `chuong` | so_chuong, truyen (relationship) |

### WordPress templates cần tạo (trong child theme)

- `single-truyen.php` — trang chi tiết truyện + danh sách chương
- `single-chuong.php` — trang đọc chương (luôn có gate)
- `archive-truyen.php` — trang danh sách truyện (homepage)

## Gate Shopee

**Quy tắc:** Tất cả chương đều có gate. Chỉ cần click 1 lần/phiên duyệt web → toàn bộ chương trong session đó không hỏi lại. Đóng tab → phiên mới → gate hiện lại.

**Kỹ thuật:** `sessionStorage` key `shopee_session_ok` (toàn site, tự xoá khi đóng tab).

**Flow:** Reader vào chương → thấy gate (icon túi Shopee + nút) → click → Shopee mở tab mới → 1 giây → nội dung chương hiện ra.

**Màu sắc** (theo demo2.png): nền `#FDF6F0`, heading `#7B3F00`, button `#A0522D`.

## Simply Static

Settings → Deploy → Local Directory → `E:\taotruyen`

## Deploy workflow

1. Viết/sửa trong WP-Admin → Publish
2. Simply Static → Generate
3. Chạy `scripts\deploy.ps1` → git push → Cloudflare auto-deploy (~30s)

## Repo & Hosting

- GitHub: `github.com/duongquochuyvn93/truyendemxyz`
- Cloudflare Workers: `truyendemxyz.duongquochuyvn.workers.dev`
- Domain: `truyendem.xyz` (mua tại Namecheap, DNS trỏ vào Cloudflare)

## Lưu ý quan trọng

- **Không dùng theme/plugin WordPress bản nulled/crack** — rủi ro backdoor/malware
- **Rủi ro affiliate**: gate có thể vi phạm điều khoản Shopee Affiliates ("forced click") — nếu bị cảnh báo, đổi sang sticky banner gợi ý thay vì chặn cứng
- Site tĩnh không có search server-side — dùng Pagefind nếu cần tìm kiếm

## Chi phí

| Mục | Chi phí |
|---|---|
| WordPress (local) | $0 |
| Hosting (Cloudflare Pages) | $0 |
| Domain | đã mua |

Chi tiết kỹ thuật: `C:\Users\Huy\.claude\plans\t-i-ang-c-d-elegant-river.md`
