# Tạo Truyện — website truyện chữ AI

## Mục tiêu

Website đăng truyện chữ, nội dung do AI sinh và review, monetize bằng affiliate Shopee, vận hành với chi phí tối thiểu (chỉ tốn tiền domain).

## Kiến trúc

```
[PC có GPU — toàn bộ xử lý + lưu trữ nội dung]
 Ollama (qwen3:8b)  --draft chương-->
 Ollama (qwen3:14b) --review/sửa văn-->
 Google Sheet (từ khoá/title/link Shopee) --CSV-->
 Script Python (orchestrator: khớp từ khoá -> chọn link -> chèn gate Shopee)
        |
        v
 WordPress chạy LOCAL (chỉ dùng để soạn/quản lý nội dung, không public)
        | (plugin Simply Static export ra HTML/CSS/JS tĩnh)
        v
 git commit + push (script tự động)
        |
        v
[Cloudflare Pages — free, không giới hạn băng thông]  <-- domain trỏ vào đây
```

- **AI pipeline**: Ollama local chạy `qwen3:8b` (sinh nội dung) + `qwen3:14b` (review văn phong). Không tốn phí inference, chỉ tốn điện.
- **Nội dung được soạn trong WordPress chạy local** (không public 24/7), dùng REST API (Application Password) để script tự động đăng bài.
- **Xuất tĩnh**: plugin Simply Static export site WordPress local ra HTML/CSS/JS thuần.
- **Hosting**: Cloudflare Pages (free), deploy qua git push từ repo GitHub.
- **Monetize**: chèn link affiliate Shopee vào giữa chương, ép/gợi ý người đọc bấm link trước khi đọc tiếp (gate bằng JavaScript phía client, dùng `localStorage` để lưu trạng thái đã bấm).
  - Danh sách link được quản lý trong **Google Sheet** (cột: từ khoá, tiêu đề sản phẩm, link Shopee), lấy qua URL CSV public (Publish to web), không cần OAuth.
  - Orchestrator quét text chương, khớp từ khoá để chọn link Shopee phù hợp; có dòng "default" trong sheet nếu không khớp.

## Lưu ý quan trọng

- **Không dùng theme/plugin WordPress bản "nulled"/crack** — rủi ro backdoor/malware.
- **Rủi ro affiliate**: cơ chế ép bấm link có thể vi phạm điều khoản "forced click"/"incentivized click" của Shopee Affiliates — cần xem lại điều khoản trước khi launch, có phương án làm mềm (gợi ý thay vì chặn cứng).
- Máy local cần bật khi muốn đăng/deploy chương mới; site đã deploy là tĩnh nên không ảnh hưởng người đọc khi máy tắt.
- Nội dung AI nên có review thủ công định kỳ ngoài review tự động bằng 14B, tránh lỗi logic truyện/lặp nội dung.
- Site tĩnh không có search server-side — nếu cần tìm kiếm, dùng Pagefind (build-time, vẫn free).

## Chi phí

| Mục | Chi phí |
|---|---|
| AI inference (local) | $0 |
| WordPress (local) | $0 |
| Hosting (Cloudflare Pages) | $0 |
| Domain | đã mua |

Chi tiết đầy đủ và các bước triển khai: xem `C:\Users\Huy\.claude\plans\t-i-ang-c-d-elegant-river.md`.
