#!/usr/bin/env python3
# Tách ảnh chụp màn hình chính thật của máy ảo (shots/en/*.png) thành các mảnh cho phim "Widget":
# hình nền sạch, từng biểu tượng / widget có nền trong suốt (để chúng rung, trượt riêng), bảng nút Edit.
#   python3 widget-assets.py     -> assets/w-*.jpg|png   (toạ độ trong code theo ảnh rộng 920px, như ảnh xem thử)
import os
from PIL import Image, ImageChops, ImageDraw, ImageFilter
D = os.path.dirname(os.path.abspath(__file__)); S = D + "/shots/en/"; A = D + "/assets/"
K = 1206 / 920          # 920 -> điểm ảnh gốc
OUT = 804               # ảnh xuất rộng 804px = 2x điểm (402pt)
def load(n): return Image.open(S + n + ".png").convert("RGB")
def box(b): return tuple(round(v * K) for v in b)
def save(im, name, q=80):
    im = im.resize((round(im.width * OUT / 1206), round(im.height * OUT / 1206)), Image.LANCZOS)
    im.save(A + name, quality=q) if name.endswith(".jpg") else im.save(A + name)

home, empty, edit, menu = load("01-home"), load("00-empty"), load("02-jiggle"), load("03-menu")
# Nền thường: màn hình chính thật nhưng vùng biểu tượng thay bằng hình nền sạch. Nền khi sửa: trang trống (có Edit / Done)
normal = home.copy(); normal.paste(empty.crop(box((0, 150, 920, 1580))), box((0, 150))[:2])
editing = empty.copy(); editing.paste(edit.crop(box((300, 1590, 620, 1700))), box((300, 1590))[:2])
save(normal, "w-bg.jpg"); save(editing, "w-bg-edit.jpg")

def sprite(name, b, body, radius):
    """Mảnh `b` của màn hình chính, trong suốt ở chỗ chỉ là hình nền: thân (bo góc) lấy trọn, chữ bên dưới lấy theo chỗ khác nền."""
    crop, back = home.crop(box(b)), empty.crop(box(b))
    diff = ImageChops.difference(crop, back).convert("L").point(lambda v: 255 if v > 14 else 0).filter(ImageFilter.GaussianBlur(1.2))
    mask = Image.new("L", crop.size, 0)
    r = box((body[0] - b[0], body[1] - b[1], body[2] - b[0], body[3] - b[1]))
    ImageDraw.Draw(mask).rounded_rectangle(r, radius=round(radius * K), fill=255)
    mask = ImageChops.lighter(mask.filter(ImageFilter.GaussianBlur(0.8)), diff)
    out = crop.convert("RGBA"); out.putalpha(mask); save(out, name)

for i, x in enumerate((62, 486)):   # hai widget (Maps, Calendar) và tên bên dưới
    sprite(f"w-big{i}.png", (x - 12, 195, x + 386, 640), (x, 207, x + 374, 580), 62)
for r, y in enumerate((665, 895)):  # hai hàng biểu tượng
    for c, x in enumerate((70, 282, 494, 706)):
        sprite(f"w-app{r}{c}.png", (x - 24, y - 12, x + 169, y + 200), (x, y, x + 145, y + 145), 36)
# Bảng của nút Edit
m = menu.crop(box((90, 143, 660, 572))).convert("RGBA")
mk = Image.new("L", m.size, 0); ImageDraw.Draw(mk).rounded_rectangle((0, 0, m.width - 1, m.height - 1), radius=round(62 * K), fill=255)
m.putalpha(mk); save(m, "w-menu.png")
# Các trang của bảng thêm tiện ích: giữ nguyên ảnh chụp
for n, src in (("w-sheet-gallery", "04-gallery"), ("w-sheet-search", "05-search"), ("w-sheet-1", "06-w1"), ("w-sheet-2", "07-w2"),
               ("w-sheet-3", "08-w3"), ("w-sheet-4", "09-w4"), ("w-sheet-5", "10-w5")):
    save(load(src), n + ".jpg", 78)
s = load("05-search")
print("field", s.getpixel(box((560, 400))[:2]), "sheet", s.getpixel(box((460, 800))[:2]))
