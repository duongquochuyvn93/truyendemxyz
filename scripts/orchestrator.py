"""
DEPRECATED - KHONG DUNG NUA. Thay bang app story-gen tai E:\\story-gen.

Script nay chen gate Shopee truc tiep vao content post (localStorage key
'shopee_unlocked_<path>'), KHAC voi gate hien tai o template single-chuong.php
(localStorage key 'shopee_gate_ok', TTL 24h). Neu chay lai se tao post co gate
nhung cung xung dot voi gate cua template. Giu file chi de tham khao.

Orchestrator: AI generate -> review -> keyword match -> Shopee gate -> WP post -> git push
"""

import csv
import io
import os
import re
import subprocess
import unicodedata
from pathlib import Path

import requests

# ─── CẤU HÌNH ────────────────────────────────────────────────────────────────

# Load từ scripts/.env nếu có
_env_file = Path(__file__).parent / ".env"
if _env_file.exists():
    for _line in _env_file.read_text(encoding="utf-8").splitlines():
        if "=" in _line and not _line.startswith("#"):
            _k, _v = _line.split("=", 1)
            os.environ.setdefault(_k.strip(), _v.strip())

OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL_GENERATE = "qwen3:8b"
MODEL_REVIEW   = "qwen3:14b"

GOOGLE_SHEET_CSV = (
    "https://docs.google.com/spreadsheets/d/e/"
    "2PACX-1vRzrT9Agmz6QzKZBz_Pmmi4MWOph8jU8CJ0RauUxKtOuxwZMv5f_oVExcMPkNdR88kZMQn_wXxp5G-p"
    "/pub?gid=0&single=true&output=csv"
)

WP_URL      = os.environ["WP_URL"]
WP_USER     = os.environ["WP_USER"]
WP_APP_PASS = os.environ["WP_APP_PASS"]

GATE_SPLIT_CHARS = 800

REPO_PATH = Path(__file__).parent.parent   # e:\taotruyen

# ─── AI ──────────────────────────────────────────────────────────────────────

def ollama(model: str, prompt: str) -> str:
    resp = requests.post(
        OLLAMA_URL,
        json={"model": model, "prompt": prompt, "stream": False, "options": {"num_predict": 2048}},
        timeout=300,
    )
    resp.raise_for_status()
    return resp.json()["response"].strip()


def generate_chapter(story_title: str, chapter_num: int, outline: str) -> str:
    prompt = (
        f"Viết chương {chapter_num} của truyện '{story_title}'.\n"
        f"Tóm tắt nội dung cần có: {outline}\n\n"
        "Yêu cầu: văn xuôi tiếng Việt, sinh động, ít nhất 1200 từ, không thêm giải thích ngoài lề."
    )
    print(f"[generate] {MODEL_GENERATE} đang viết chương {chapter_num}...")
    return ollama(MODEL_GENERATE, prompt)


def review_chapter(draft: str) -> str:
    prompt = (
        "Bạn là biên tập viên văn học. Hãy đọc đoạn văn dưới đây và sửa lại:\n"
        "- Cải thiện văn phong, câu văn tự nhiên hơn\n"
        "- Giữ nguyên cốt truyện và nhân vật\n"
        "- Không thêm/bớt nội dung lớn\n"
        "- Chỉ trả về bản đã sửa, không giải thích.\n\n"
        f"{draft}"
    )
    print(f"[review] {MODEL_REVIEW} đang review...")
    return ollama(MODEL_REVIEW, prompt)

# ─── GOOGLE SHEET ─────────────────────────────────────────────────────────────

def fetch_keyword_table() -> list[dict]:
    """Trả về list dict: {keywords: [str], title: str, link: str, is_default: bool}"""
    print("[sheet] Đang tải bảng từ khoá...")
    resp = requests.get(GOOGLE_SHEET_CSV, timeout=30)
    resp.raise_for_status()
    reader = csv.DictReader(io.StringIO(resp.text))
    rows = []
    for row in reader:
        # Tên cột mặc định: keyword, title, link
        # Nếu sheet bạn dùng tên khác, sửa 3 dòng dưới
        raw_kw = row.get("keyword", "").strip()
        title  = row.get("title", "").strip()
        link   = row.get("link", "").strip()
        if not link:
            continue
        is_default = raw_kw.lower() == "default"
        keywords = [] if is_default else [k.strip() for k in raw_kw.split(",") if k.strip()]
        rows.append({"keywords": keywords, "title": title, "link": link, "is_default": is_default})
    print(f"[sheet] Đã tải {len(rows)} dòng (gồm default).")
    return rows


def _normalize(text: str) -> str:
    """Chuyển về chữ thường, bỏ dấu để so sánh mềm."""
    text = text.lower()
    nfkd = unicodedata.normalize("NFKD", text)
    return "".join(c for c in nfkd if not unicodedata.combining(c))


def match_shopee(chapter_text: str, table: list[dict]) -> dict | None:
    """Trả về row khớp đầu tiên; nếu không có thì trả row default; nếu không có default thì None."""
    norm_text = _normalize(chapter_text)
    default_row = None
    for row in table:
        if row["is_default"]:
            default_row = row
            continue
        for kw in row["keywords"]:
            if _normalize(kw) in norm_text:
                print(f"[match] Khớp từ khoá '{kw}' → {row['title']}")
                return row
    if default_row:
        print(f"[match] Không khớp từ khoá nào, dùng default → {default_row['title']}")
    return default_row

# ─── SHOPEE GATE ──────────────────────────────────────────────────────────────

def insert_gate(chapter_html: str, shopee_link: str, product_title: str) -> str:
    """Chia chương làm đôi, chèn nút Shopee gate vào giữa."""
    # Tìm điểm cắt an toàn (cuối đoạn văn gần vị trí GATE_SPLIT_CHARS)
    split_at = GATE_SPLIT_CHARS
    close_p = chapter_html.find("</p>", split_at)
    if close_p != -1:
        split_at = close_p + 4

    part1 = chapter_html[:split_at]
    part2 = chapter_html[split_at:]

    gate_html = f"""
<div class="shopee-gate" style="text-align:center;margin:32px 0;padding:24px;border:2px solid #ee4d2d;border-radius:8px;background:#fff8f7">
  <p style="font-size:1.05em;margin-bottom:12px">
    ✨ Ủng hộ tác giả bằng cách xem qua sản phẩm gợi ý — hoàn toàn miễn phí với bạn!
  </p>
  <p style="font-weight:bold;margin-bottom:16px">{product_title}</p>
  <button id="shopee-btn"
    onclick="openShopeeAndUnlock('{shopee_link}')"
    style="background:#ee4d2d;color:#fff;border:none;padding:12px 28px;font-size:1em;border-radius:6px;cursor:pointer">
    Xem sản phẩm &amp; Đọc tiếp ▶
  </button>
  <p id="shopee-note" style="font-size:0.85em;color:#888;margin-top:8px">
    (Mở Shopee ở tab mới, sau đó chương sẽ hiện ra)
  </p>
</div>

<div id="chapter-rest" style="display:none">
{part2}
</div>

<script>
(function(){{
  var KEY = 'shopee_unlocked_' + window.location.pathname;
  if (localStorage.getItem(KEY)) {{ unlockChapter(); }}

  function unlockChapter() {{
    var el = document.getElementById('chapter-rest');
    if (el) el.style.display = '';
    var btn = document.getElementById('shopee-btn');
    if (btn) btn.style.display = 'none';
    var note = document.getElementById('shopee-note');
    if (note) note.style.display = 'none';
  }}

  window.openShopeeAndUnlock = function(url) {{
    window.open(url, '_blank');
    localStorage.setItem(KEY, '1');
    unlockChapter();
  }};
}})();
</script>
"""
    return part1 + gate_html


def text_to_html(text: str) -> str:
    """Chuyển plain text thành HTML đơn giản (mỗi đoạn -> <p>)."""
    paragraphs = [p.strip() for p in text.split("\n") if p.strip()]
    return "\n".join(f"<p>{p}</p>" for p in paragraphs)

# ─── WORDPRESS ────────────────────────────────────────────────────────────────

def wp_get_or_create_story(story_title: str) -> int:
    """Lấy ID category tương ứng với tên truyện (tạo mới nếu chưa có)."""
    auth = (WP_USER, WP_APP_PASS)
    slug = re.sub(r"[^a-z0-9]+", "-", story_title.lower()).strip("-")

    resp = requests.get(f"{WP_URL}/categories", params={"slug": slug}, auth=auth, timeout=30)
    cats = resp.json()
    if cats:
        return cats[0]["id"]

    resp = requests.post(
        f"{WP_URL}/categories",
        json={"name": story_title, "slug": slug},
        auth=auth,
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()["id"]


def wp_post_chapter(
    story_title: str,
    chapter_num: int,
    chapter_title: str,
    content_html: str,
) -> str:
    """Đăng chương lên WordPress local, trả về permalink."""
    auth = (WP_USER, WP_APP_PASS)
    cat_id = wp_get_or_create_story(story_title)
    post_title = f"Chương {chapter_num}: {chapter_title}"

    resp = requests.post(
        f"{WP_URL}/posts",
        json={
            "title":      post_title,
            "content":    content_html,
            "status":     "publish",
            "categories": [cat_id],
        },
        auth=auth,
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()
    print(f"[wp] Đã đăng: {data['link']}")
    return data["link"]

# ─── GIT PUSH ─────────────────────────────────────────────────────────────────

def git_push(message: str):
    """Commit toàn bộ thay đổi trong repo và push."""
    cmds = [
        ["git", "-C", str(REPO_PATH), "add", "-A"],
        ["git", "-C", str(REPO_PATH), "commit", "-m", message],
        ["git", "-C", str(REPO_PATH), "push"],
    ]
    for cmd in cmds:
        print(f"[git] {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            # commit rỗng không phải lỗi
            if "nothing to commit" in result.stdout + result.stderr:
                print("[git] Không có gì để commit.")
                return
            print(result.stderr)
            raise RuntimeError(f"Git lỗi: {result.returncode}")

# ─── MAIN ─────────────────────────────────────────────────────────────────────

def run(
    story_title: str,
    chapter_num: int,
    chapter_title: str,
    outline: str,
    skip_wp: bool = False,
    skip_git: bool = False,
):
    """Pipeline đầy đủ cho 1 chương."""

    # 1. Generate
    draft = generate_chapter(story_title, chapter_num, outline)

    # 2. Review
    polished = review_chapter(draft)

    # 3. Chuyển thành HTML
    chapter_html = text_to_html(polished)

    # 4. Khớp từ khoá Shopee
    table = fetch_keyword_table()
    matched = match_shopee(polished, table)

    # 5. Chèn gate (nếu có link)
    if matched:
        chapter_html = insert_gate(chapter_html, matched["link"], matched["title"])
    else:
        print("[gate] Không tìm được link Shopee, bỏ qua gate.")

    # 6. Đăng WordPress
    if not skip_wp:
        wp_post_chapter(story_title, chapter_num, chapter_title, chapter_html)
    else:
        # In ra để kiểm tra khi chưa có WP
        preview_path = REPO_PATH / "scripts" / f"preview_chapter_{chapter_num}.html"
        preview_path.write_text(chapter_html, encoding="utf-8")
        print(f"[preview] HTML lưu tại: {preview_path}")

    # 7. Git push (sau khi Simply Static export - thủ công hoặc WP hook)
    if not skip_git:
        git_push(f"chap: {story_title} - Chương {chapter_num}")
    else:
        print("[git] Bỏ qua git push (skip_git=True).")

    print("\n✓ Hoàn thành pipeline.")


# ─── CHẠY THỬ ─────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    run(
        story_title   = "Đêm Trắng Sài Gòn",
        chapter_num   = 1,
        chapter_title = "Cuộc gặp gỡ đầu tiên",
        outline       = (
            "Nhân vật chính Minh, 28 tuổi, lập trình viên freelance, "
            "tình cờ gặp Lan tại quán cà phê lúc 2 giờ sáng. "
            "Cả hai đều không ngủ được vì áp lực công việc. "
            "Họ bắt đầu trò chuyện và phát hiện nhiều điểm chung."
        ),
        skip_wp  = True,   # ← đổi thành False sau khi cài WordPress xong
        skip_git = True,   # ← đổi thành False sau khi WP + Simply Static chạy được
    )
