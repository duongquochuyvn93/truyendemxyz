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

**Quy tắc:** Tất cả chương đều có gate. Click 1 lần → unlock toàn site trong 24 giờ. Hết 24 giờ → gate hiện lại.

**Kỹ thuật:** `localStorage` key `shopee_gate_ok` lưu timestamp, TTL 24 giờ (xem `single-chuong.php`). Link Shopee lấy từ Google Sheet CSV theo thể loại (`td_get_shopee_link()` trong `functions.php`); không khớp keyword và không có dòng `default` → lấy link đầu bảng.

**Flow:** Reader vào chương → thấy gate (icon túi Shopee + nút) → click → Shopee mở tab mới → 1 giây → nội dung chương hiện ra.

**Màu sắc** (theo demo2.png): nền `#FDF6F0`, heading `#7B3F00`, button `#A0522D`.

## Simply Static

Settings → Deploy → Local Directory → `E:\taotruyen`

## Deploy workflow

1. Viết/sửa trong WP-Admin → Publish
2. Chạy `scripts\sync-views.ps1` — kéo lượt xem thật từ Cloudflare KV về ghi vào `luot_xem` trên WP (để "Truyện Hot" sort đúng)
3. Simply Static → Generate
4. Chạy `scripts\deploy.ps1` → git push + gọi deploy hook (đọc `CF_DEPLOY_HOOK` từ `scripts\.env`) → Cloudflare Workers build (~60s)

Deploy chạy `npx wrangler deploy` với `wrangler.toml` (assets = toàn bộ repo, trừ các file trong `.assetsignore`). Giới hạn Workers: 25 MiB/file.

## Lượt xem (luot_xem)

- Truyện mới publish (WP-Admin hoặc qua story-gen) tự động random 10-500 (`save_post_truyen` hook trong `functions.php`), chỉ chạy 1 lần (đánh dấu bằng meta `_luot_xem_seeded`).
- View thật: mỗi lần đọc 1 chương, JS trong `single-chuong.php` gọi `POST /api/views/{truyen_id}` (dedupe 24h/trình duyệt qua `localStorage`). `worker.js` chuyển request vào Durable Object `VIEW_STORE`, nơi tăng counter tuần tự để không mất lượt khi có request đồng thời.
- Đồng bộ dùng batch: `POST /api/views/export` với `Authorization: Bearer <SYNC_SECRET>` tạo/lấy batch đang chờ; chỉ `POST /api/views/ack` sau khi WordPress cập nhật thành công mới xoá batch. Lượt phát sinh trong lúc sync nằm ở batch kế tiếp. `worker.js` phải được commit để Wrangler deploy, nhưng bị loại khỏi static assets trong `.assetsignore`.
- `scripts\sync-views.ps1` lưu journal tạm `scripts\.sync-views-state.json` (gitignored) để chạy lại batch dở dang mà không cộng trùng. Chạy script trước Simply Static Generate để số liệu hiển thị khớp.

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
