import importlib.util, sys
spec = importlib.util.spec_from_file_location("hh", "/Users/thanhnguyen/Documents/peakapp.vn/tools/hand-heading.py")
hh = importlib.util.module_from_spec(spec); spec.loader.exec_module(hh)
from pathlib import Path
hh.SITE = Path("/Users/thanhnguyen/Documents/Pay/web/pay").parent / "pay"
# trang Pay: một dòng tiếng Việt, ngắt nhóm ở dấu chấm -> chia thành 2 nhóm bằng dấu chấm sau "tiêu"
hh.HEADINGS = {"hand": {"vi": "Ghi chi tiêu|trong một giây."}}
import re as _re, types
hh.re = types.SimpleNamespace(split=lambda pat, s: s.split("|"))  # ngắt nhóm ở "|", giữ đúng câu không thêm dấu chấm
orig = hh.written
def written(html, marker, LINES, *a):
    out = orig(html, marker, LINES, *a)
    return out
hh.written = written
# index.html của Pay nằm ở web/pay
hh.SITE = Path("/Users/thanhnguyen/Documents/Pay/web/pay")
hh.main(sys.argv[1])
