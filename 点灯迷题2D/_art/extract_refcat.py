# -*- coding: utf-8 -*-
"""参考猫图 → 64×64 像素画 + 派生 16×16 轮廓

流程（按 pixel-lua-reconstruction skill）：
  ① O 原图 → k-means 聚出主色（避开 JPEG 噪声，不用单点取样）
  ② 面积多数取样：主体等比铺进 64×64（四周留 MARGIN 格），每格 5×5 点投票
  ③ 背景 = 从画布边界 4 连通泛洪的"近奶油色"区域（脸内的奶油色不会误判，因为有描边隔断）
  ④ 去孤立点 → Q（量化后的 64×64）
  ⑤ 派生 16×16：4×4 格里"墨色"（深棕描边/眼/嘴 + 粉鼻）≥50% → 黑格
产物：out/refcat/{cat64.png,cat64_big.png,cat16_big.png,_compare.png,_glua.lua,_pic16.lua}
"""
import json
import os
from collections import Counter, deque

from PIL import Image, ImageDraw, ImageFont

SRC = r"E:\聊天信息\QQ信息\Tencent Files\2902922874\nt_qq\nt_data\Pic\2026-10\Thumb\c5253f2493abaf630999641508e46d7b_720.jpg"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "refcat")
S = 64
N = 16
K = S // N
MARGIN = 5                 # 主体四周留白（格）

BG_REF = (255, 252, 235)   # 奶油底（仅用于泛洪判定）
BG_TOL = 30


# ---------------------------------------------------------------- 工具
def load():
    return Image.open(SRC).convert("RGB")


def find_bbox(im):
    px = im.load()
    W, H = im.size
    xs, ys = [], []
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            if x > 860 and y > 1140:      # 右下角水印
                continue
            c = px[x, y]
            if abs(c[0] - BG_REF[0]) + abs(c[1] - BG_REF[1]) + abs(c[2] - BG_REF[2]) > 30:
                xs.append(x)
                ys.append(y)
    return min(xs), min(ys), max(xs), max(ys)


def kmeans(pixels, k=8, iters=14):
    """极简 k-means（RGB），初始中心按亮度分位取"""
    pixels = list(pixels)
    pixels.sort(key=lambda c: c[0] * 0.3 + c[1] * 0.6 + c[2] * 0.1)
    centers = [pixels[int((i + 0.5) * len(pixels) / k)] for i in range(k)]
    for _ in range(iters):
        buckets = [[] for _ in range(k)]
        for c in pixels[::3]:
            bi = min(range(k), key=lambda i: (centers[i][0] - c[0]) ** 2 +
                     (centers[i][1] - c[1]) ** 2 + (centers[i][2] - c[2]) ** 2)
            buckets[bi].append(c)
        new = []
        for i, b in enumerate(buckets):
            if not b:
                new.append(centers[i])
                continue
            n = len(b)
            new.append((sum(c[0] for c in b) // n, sum(c[1] for c in b) // n,
                        sum(c[2] for c in b) // n))
        if new == centers:
            break
        centers = new
    return centers


def nearest(pal, c):
    return min(range(len(pal)),
               key=lambda i: (pal[i][0] - c[0]) ** 2 + (pal[i][1] - c[1]) ** 2 +
                             (pal[i][2] - c[2]) ** 2)


def sample_grid(im, bbox, pal):
    x0, y0, x1, y1 = bbox
    bw, bh = x1 - x0, y1 - y0
    span = S - 2 * MARGIN
    scale = max(bw, bh) / float(span)
    gw, gh = bw / scale, bh / scale
    ox = (S - gw) / 2.0
    oy = (S - gh) / 2.0
    px = im.load()
    grid = [[None] * S for _ in range(S)]
    for gy in range(S):
        for gx in range(S):
            votes = Counter()
            for sy in range(5):
                for sx in range(5):
                    fx = x0 + (gx + (sx + 0.5) / 5.0 - ox) * scale
                    fy = y0 + (gy + (sy + 0.5) / 5.0 - oy) * scale
                    xi, yi = int(fx), int(fy)
                    if 0 <= xi < im.size[0] and 0 <= yi < im.size[1]:
                        votes[nearest(pal, px[xi, yi])] += 1
            grid[gy][gx] = votes.most_common(1)[0][0]
    return grid


def flood_bg(grid, pal):
    """从画布边界把"近奶油色"格子标记为背景（None）"""
    cream = nearest(pal, BG_REF)
    out = [row[:] for row in grid]
    q = deque()
    for x in range(S):
        for y in (0, S - 1):
            q.append((x, y))
    for y in range(S):
        for x in (0, S - 1):
            q.append((x, y))
    seen = set()
    while q:
        x, y = q.popleft()
        if (x, y) in seen or not (0 <= x < S and 0 <= y < S):
            continue
        seen.add((x, y))
        if out[y][x] != cream:
            continue
        out[y][x] = None
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q.append((x + dx, y + dy))
    return out


def clean(grid, passes=2):
    for _ in range(passes):
        out = [row[:] for row in grid]
        for y in range(1, S - 1):
            for x in range(1, S - 1):
                c = grid[y][x]
                nb = [grid[y - 1][x], grid[y + 1][x], grid[y][x - 1], grid[y][x + 1]]
                if all(n != c for n in nb):
                    m = Counter(nb).most_common(1)[0][0]
                    out[y][x] = m
        grid = out
    return grid


def drop_specks(grid, min_size=8):
    """去掉孤立小色块（参考图两边的胡须小横线在 64 格里会变成噪点）"""
    seen = [[False] * S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            if grid[y][x] is None or seen[y][x]:
                continue
            comp, q = [], deque([(x, y)])
            seen[y][x] = True
            while q:
                cx, cy = q.popleft()
                comp.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < S and 0 <= ny < S and not seen[ny][nx] and grid[ny][nx] is not None:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if len(comp) < min_size:
                for cx, cy in comp:
                    grid[cy][cx] = None
    return grid


def fix_eye_highlight(grid, dark_id, cream_id):
    """修正眼珠高光。

    参考图里两只眼睛各有一个白色高光方块（约 1 个原生块），位置是**镜像**的：
    靠脸中线那一侧、偏上（约 2/3 宽 / 22% 高 与 1/3 宽 / 22% 高）。
    面积多数取样会把这种 1~2 格的小洞取丢或取偏，所以这里按眼珠连通块重盖。
    """
    seen = [[False] * S for _ in range(S)]
    eyes = []
    for y in range(S):
        for x in range(S):
            if grid[y][x] != dark_id or seen[y][x]:
                continue
            q, comp = deque([(x, y)]), []
            seen[y][x] = True
            while q:
                cx, cy = q.popleft()
                comp.append((cx, cy))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < S and 0 <= ny < S and not seen[ny][nx] and grid[ny][nx] == dark_id:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            xs = [p[0] for p in comp]
            ys = [p[1] for p in comp]
            w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
            # 眼珠：大致 8×8、面积 40~80、四周被脸包住（不贴画布边）
            if 40 <= len(comp) <= 90 and 6 <= w <= 10 and 6 <= h <= 10 \
                    and min(xs) > 3 and max(xs) < S - 4 and min(ys) > 3:
                eyes.append((min(xs), min(ys), max(xs), max(ys)))
    for (x0, y0, x1, y1) in eyes:
        # ① 先把眼珠里的"洞"（取样留下的高光残片）全部补成深色
        #    从 bbox 边界向内泛洪非深色格 → 能到达的算外部，到不了的是洞
        outside = set()
        q = deque()
        for x in range(x0, x1 + 1):
            for y in (y0, y1):
                if grid[y][x] != dark_id:
                    q.append((x, y))
        for y in range(y0, y1 + 1):
            for x in (x0, x1):
                if grid[y][x] != dark_id:
                    q.append((x, y))
        while q:
            cx, cy = q.popleft()
            if (cx, cy) in outside or not (x0 <= cx <= x1 and y0 <= cy <= y1):
                continue
            if grid[cy][cx] == dark_id:
                continue
            outside.add((cx, cy))
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q.append((cx + dx, cy + dy))
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if grid[y][x] != dark_id and (x, y) not in outside:
                    grid[y][x] = dark_id

        # ② 距离变换（到眼珠边界），只在安全核心里放 2×2 高光
        INF = 99
        dist = [[INF] * S for _ in range(S)]
        q2 = deque()
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                edge = False
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if not (x0 <= nx <= x1 and y0 <= ny <= y1) or grid[ny][nx] != dark_id:
                        edge = True
                        break
                if edge:
                    dist[y][x] = 1
                    q2.append((x, y))
        while q2:
            cx, cy = q2.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = cx + dx, cy + dy
                if x0 <= nx <= x1 and y0 <= ny <= y1 and dist[ny][nx] > dist[cy][cx] + 1:
                    dist[ny][nx] = dist[cy][cx] + 1
                    q2.append((nx, ny))

        inner_left = (x0 + x1) / 2.0 < S / 2.0
        tx, ty = ((x1 - 2) if inner_left else (x0 + 2)), y0 + 2
        best = None
        for cy in range(y0, y1):
            for cx in range(x0, x1):
                if min(dist[cy][cx], dist[cy][cx + 1], dist[cy + 1][cx], dist[cy + 1][cx + 1]) < 3:
                    continue
                d = (cx - tx) ** 2 + (cy - ty) ** 2
                if best is None or d < best[0]:
                    best = (d, cx, cy)
        if best:
            _, cx, cy = best
            for dy in range(2):
                for dx in range(2):
                    grid[cy + dy][cx + dx] = cream_id
    return grid, len(eyes)


def fix_mouth(grid, dark_id, cream_id, cx=32):
    """重画嘴：参考图这两笔被 JPEG 噪点弄得左右不对齐，直接盖一个对称 ω。

    cx 是脸的对称轴（x ↔ 2*cx+1-x）。鼻底 → 2 格竖线 → 两道上翘的小弧。
    """
    # 清掉嘴巴区域原有的深色，填回脸的奶油色（不能填 None，那会打穿透明）
    for y in range(40, 47):
        for x in range(cx - 8, cx + 9):
            if grid[y][x] == dark_id:
                grid[y][x] = cream_id
    spec = []
    for dy in range(3):                     # 人中：鼻底向下 3 格（左右各 1 格）
        spec += [(cx, 40 + dy), (cx + 1, 40 + dy)]
    # 两个对称的小 U（ω 的两瓣），各 3×3，中间留人脸中线
    spec += [(cx - 5, 42), (cx - 4, 42), (cx + 4, 42), (cx + 5, 42)]   # 上口
    spec += [(cx - 5, 43), (cx - 3, 43), (cx + 3, 43), (cx + 5, 43)]   # 两侧
    spec += [(cx - 4, 44), (cx - 3, 44), (cx + 3, 44), (cx + 4, 44)]   # 底
    for (x, y) in spec:
        if 0 <= x < S and 0 <= y < S:
            grid[y][x] = dark_id
    return grid


def refine_region(im, bbox, pal, grid, target_id, y0, y1, x0, x1, thr=0.34):
    """细笔画补全：对指定区域用 7×7 子采样，"墨色占比 ≥ thr → 墨色"。

    嘴是 1 个原生块粗的细线，5×5 多数投票会把它削成 1 格断续的虚线；
    改用更密的子采样 + 更低阈值，能把笔画恢复到应有的 2 格粗。
    """
    bx0, by0, bx1, by1 = bbox
    bw, bh = bx1 - bx0, by1 - by0
    span = S - 2 * MARGIN
    scale = max(bw, bh) / float(span)
    gw, gh = bw / scale, bh / scale
    ox = (S - gw) / 2.0
    oy = (S - gh) / 2.0
    px = im.load()
    for gy in range(y0, y1 + 1):
        for gx in range(x0, x1 + 1):
            hit = tot = 0
            for sy in range(7):
                for sx in range(7):
                    fx = bx0 + (gx + (sx + 0.5) / 7.0 - ox) * scale
                    fy = by0 + (gy + (sy + 0.5) / 7.0 - oy) * scale
                    xi, yi = int(fx), int(fy)
                    if not (0 <= xi < im.size[0] and 0 <= yi < im.size[1]):
                        continue
                    tot += 1
                    if nearest(pal, px[xi, yi]) == target_id:
                        hit += 1
            if tot and hit / float(tot) >= thr:
                grid[gy][gx] = target_id
    return grid


def symmetrize(grid, dark_id, cream_id, y0, y1, x0, x1, axis=32):
    """把区域内深色笔画按 axis（x ↔ 2*axis+1-x）做成左右对称。

    以左半为准，镜像到右半；区域内的深色先清回奶油色。
    """
    left = {(x, y) for y in range(y0, y1 + 1) for x in range(x0, axis + 1)
            if grid[y][x] == dark_id}
    sym = set(left) | {(2 * axis + 1 - x, y) for (x, y) in left}
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if grid[y][x] == dark_id:
                grid[y][x] = cream_id
    for (x, y) in sym:
        if x0 <= x <= x1 and y0 <= y <= y1:
            grid[y][x] = dark_id
    return grid


# ---------------------------------------------------------------- 输出
def to_png(grid, pal, path, scale, bg=None):
    im = Image.new("RGBA", (S * scale, S * scale), bg if bg else (0, 0, 0, 0))
    dr = ImageDraw.Draw(im)
    for y in range(S):
        for x in range(S):
            i = grid[y][x]
            if i is None or i < 0:
                continue
            c = pal[i]
            dr.rectangle([x * scale, y * scale, (x + 1) * scale - 1, (y + 1) * scale - 1],
                         fill=(c[0], c[1], c[2], 255))
    im.save(path)
    return im


CH = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"


def rle_rows(grid, idx_of):
    rows = []
    for y in range(S):
        runs, prev, cnt = [], "~", 0
        for x in range(S):
            k = grid[y][x]
            if k == prev:
                cnt += 1
            else:
                if cnt > 0:
                    runs.append((prev, cnt))
                prev, cnt = k, 1
        runs.append((prev, cnt))
        s = ""
        for (ch, c) in runs:
            i = 35 if ch is None else idx_of[ch]
            left = c
            while left > 0:
                n = min(left, 35)
                s += CH[i] + CH[n]
                left -= n
        rows.append(s)
    return rows


def main():
    os.makedirs(OUT, exist_ok=True)
    im = load()
    bbox = find_bbox(im)
    print("主体 bbox:", bbox, " 尺寸 %dx%d" % (bbox[2] - bbox[0], bbox[3] - bbox[1]))

    # ① 主色：直接用从参考图实测的语义色（k-means 会被 JPEG 噪点与描边抗锯齿带偏）
    pal = [
        (251, 246, 230),   # 奶油白（脸 + 背景）
        (252, 201, 139),   # 浅橙斑
        (247, 175, 109),   # 中橙
        (247, 149, 85),    # 深橙（腮部条纹）
        (248, 146, 127),   # 三文鱼粉（鼻 / 耳内）
        (239, 213, 196),   # 阴影（下巴 / 边缘）
        (56, 24, 16),      # 深棕描边
    ]
    pal.sort(key=lambda c: -(c[0] * 0.3 + c[1] * 0.6 + c[2] * 0.1))
    print("\n调色板（亮→暗）：")
    for c in pal:
        print("   #%02X%02X%02X" % c)

    # ② 采样 + 背景 + 去噪
    grid = sample_grid(im, bbox, pal)
    grid = flood_bg(grid, pal)
    grid = clean(grid)
    grid = drop_specks(grid, min_size=22)

    # ②b 修正眼珠高光（取样会把它取丢/取偏）
    cream0 = nearest(pal, BG_REF)
    dark0 = min(range(len(pal)), key=lambda i: 0.3 * pal[i][0] + 0.6 * pal[i][1] + 0.1 * pal[i][2])
    grid, n_eye = fix_eye_highlight(grid, dark0, cream0)
    # 嘴：先用密集子采样把细笔画补全（保持参考图原形），再左右镜像成对称
    grid = refine_region(im, bbox, pal, grid, dark0, 40, 46, 25, 41)
    grid = symmetrize(grid, dark0, cream0, 41, 46, 24, 41, axis=32)
    print("眼珠高光修正：%d 只；嘴已补全并对称化" % n_eye)

    # ③ 预览
    to_png(grid, pal, os.path.join(OUT, "cat64.png"), 1)
    to_png(grid, pal, os.path.join(OUT, "cat64_big.png"), 9)

    used, order = {}, []
    for y in range(S):
        for x in range(S):
            i = grid[y][x]
            if i is None:
                continue
            if i not in used:
                used[i] = len(order)
                order.append(i)

    # ④ 派生 16×16：墨色 = 深棕描边/眼/嘴 + 粉鼻
    lum = [0.3 * c[0] + 0.6 * c[1] + 0.1 * c[2] for c in pal]
    dark_id = min(range(len(pal)), key=lambda i: lum[i])
    pink_id = min(range(len(pal)),
                  key=lambda i: (pal[i][0] - 248) ** 2 + (pal[i][1] - 146) ** 2 + (pal[i][2] - 127) ** 2)
    eye_ids = {dark_id}
    nose_ids = {pink_id}
    print("\n墨色: 深棕 #%02X%02X%02X / 粉 #%02X%02X%02X" % (pal[dark_id] + pal[pink_id]))

    # ★ 派生策略：先把剪影降到 16×16（块内非透明 ≥50%），再在 16 级取"轮廓"
    #   —— 直接在 64 级按墨色占比阈值会被 2px 描边跨块切成虚线，不可靠。
    def block_frac(ids=None, solid=False):
        m = [[0] * N for _ in range(N)]
        for by in range(N):
            for bx in range(N):
                n = 0
                for yy in range(K):
                    for xx in range(K):
                        v = grid[by * K + yy][bx * K + xx]
                        if solid:
                            n += 1 if v is not None else 0
                        else:
                            n += 1 if v in ids else 0
                m[by][bx] = n
        return m

    sil_c = block_frac(solid=True)
    ink_c = block_frac({dark_id, pink_id})
    sil16 = [[1 if sil_c[y][x] * 2 >= K * K else 0 for x in range(N)] for y in range(N)]
    # ★ 猫脸左右对称 → 剪影 16 级也强制对称（左半为准，x ↔ 15-x）
    for y in range(N):
        for x in range(8):
            sil16[y][N - 1 - x] = sil16[y][x]
    # 轮廓：剪影内、且四邻里有无剪影（或贴边）的格子
    mask16 = [[0] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            if not sil16[y][x]:
                continue
            edge = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < N and 0 <= ny < N) or not sil16[ny][nx]:
                    edge = True
                    break
            if edge:
                mask16[y][x] = 1
    # ★ 墨块（深棕描边/眼 + 粉耳内/鼻）≥ 5/16 也点亮：
    #   耳朵在 16 格只有 2 格高，只取"边界"会变成空心环；它的内耳是粉色，
    #   本来就该实心，所以用墨色占比直接补上。
    for y in range(N):
        for x in range(N):
            if ink_c[y][x] >= 5:
                mask16[y][x] = 1

    # 五官：眼 2×2、鼻 2×1（按 64 级连通块 bbox 吸附，保证 16 级干净、左右一致）
    def blobs_of(cid):
        seen = [[False] * S for _ in range(S)]
        out = []
        for y in range(S):
            for x in range(S):
                if grid[y][x] != cid or seen[y][x]:
                    continue
                q, comp = deque([(x, y)]), []
                seen[y][x] = True
                while q:
                    cx, cy = q.popleft()
                    comp.append((cx, cy))
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < S and 0 <= ny < S and not seen[ny][nx] and grid[ny][nx] == cid:
                            seen[ny][nx] = True
                            q.append((nx, ny))
                xs = [p[0] for p in comp]
                ys = [p[1] for p in comp]
                out.append((len(comp), min(xs), min(ys), max(xs), max(ys)))
        return out

    eyes64 = [b for b in blobs_of(dark_id)
              if 40 <= b[0] <= 90 and 6 <= b[3] - b[1] + 1 <= 10 and 6 <= b[4] - b[2] + 1 <= 10]
    for (_a, x0, y0, x1, y1) in eyes64:
        bx0, by0 = int(round(x0 / float(K))), int(round(y0 / float(K)))
        bw = max(2, int(round((x1 - x0 + 1) / float(K))))
        bh = max(2, int(round((y1 - y0 + 1) / float(K))))
        for yy in range(by0, by0 + bh):
            for xx in range(bx0, bx0 + bw):
                if 0 <= xx < N and 0 <= yy < N:
                    mask16[yy][xx] = 1
    nose64 = [b for b in blobs_of(pink_id)
              if b[0] >= 10 and 26 <= (b[1] + b[3]) / 2.0 <= 38 and 33 <= (b[2] + b[4]) / 2.0 <= 43]
    if nose64:
        _a, x0, y0, x1, y1 = max(nose64)
        bx0, by0 = int(round(x0 / float(K))), int(round(y0 / float(K)))
        bw = max(2, int(round((x1 - x0 + 1) / float(K))))
        for xx in range(bx0, bx0 + bw):
            if 0 <= xx < N and 0 <= by0 < N:
                mask16[by0][xx] = 1
    # 填掉小"洞"：耳朵只有 2~3 格高，取边界后会留 1~2 格空心 → 小连通白区补黑
    seen = [[False] * N for _ in range(N)]
    for y in range(N):
        for x in range(N):
            if mask16[y][x] or seen[y][x]:
                continue
            q, comp, touch = deque([(x, y)]), [], False
            seen[y][x] = True
            while q:
                cx, cy = q.popleft()
                comp.append((cx, cy))
                if cx in (0, N - 1) or cy in (0, N - 1):
                    touch = True
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < N and 0 <= ny < N and not seen[ny][nx] and not mask16[ny][nx]:
                        seen[ny][nx] = True
                        q.append((nx, ny))
            if not touch and len(comp) <= 4:
                for (cx, cy) in comp:
                    mask16[cy][cx] = 1
    # 孤立点清理
    for _ in range(2):
        cp = [row[:] for row in mask16]
        for y in range(N):
            for x in range(N):
                if not mask16[y][x]:
                    continue
                n = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                        if 0 <= x + dx < N and 0 <= y + dy < N and mask16[y + dy][x + dx])
                if n == 0:
                    cp[y][x] = 0
        mask16 = cp

    # ★ 16×16 终稿：实心猫头剪影（2026-10-19 定稿，用户要求「必须一眼看出是猫」）。
    #   理由：16 格画不出耳根凹口、2 格高的耳朵，细勾线版怎么调都像方框；
    #   改成实心剪影后「三角耳 + 圆头」本身就是猫的符号，两眼/鼻挖空成洞。
    #   要改形状只改这里 + config.lua 的 local CAT，两处必须一致。
    MASK16_FINAL = """
................
..#..........#..
.###........###.
.#####....#####.
.##############.
.##############.
.###..####..###.
.###..####..###.
.##############.
.######..######.
.##############.
.##############.
..############..
....########....
................
................
""".strip("\n").split("\n")
    mask16 = [[1 if ch == "#" else 0 for ch in row] for row in MASK16_FINAL]
    assert len(mask16) == N and all(len(r) == N for r in mask16), "16×16 定稿尺寸不对"

    m16 = Image.new("RGB", (N * 16, N * 16), (255, 255, 255))
    d16 = ImageDraw.Draw(m16)
    for y in range(N):
        for x in range(N):
            if mask16[y][x]:
                d16.rectangle([x * 16, y * 16, x * 16 + 15, y * 16 + 15], fill=(26, 30, 42))
    m16.save(os.path.join(OUT, "cat16_big.png"))

    # ⑤ 对照图
    try:
        font = ImageFont.truetype(r"C:/Windows/Fonts/msyh.ttc", 15)
    except Exception:
        font = ImageFont.load_default()
    a = Image.open(os.path.join(OUT, "cat64_big.png")).convert("RGBA")
    W = a.size[0] + m16.size[0] + 56
    H = a.size[1] + 60
    c = Image.new("RGBA", (W, H), (250, 251, 253, 255))
    c.paste(a, (8, 44), a)
    c.paste(m16, (a.size[0] + 40, 44))
    d = ImageDraw.Draw(c)
    d.text((8, 14), "64×64 彩图（参考图重建）", font=font, fill=(30, 36, 50))
    d.text((a.size[0] + 40, 14), "派生 16×16 轮廓", font=font, fill=(30, 36, 50))
    c.save(os.path.join(OUT, "_compare.png"))

    # ⑥ Lua
    rows = rle_rows(grid, used)
    with open(os.path.join(OUT, "_glua.lua"), "w", encoding="utf-8") as f:
        f.write("M.ART64.cat = {\n")
        f.write("    pal = { %s },\n" % ", ".join('"%02X%02X%02X"' % pal[i] for i in order))
        f.write("    rows = {\n")
        for r in rows:
            f.write('        "%s",\n' % r)
        f.write("    },\n}\n")
    with open(os.path.join(OUT, "_pic16.lua"), "w", encoding="utf-8") as f:
        f.write("local CAT = {\n")
        for row in mask16:
            f.write('"%s",\n' % "".join("#" if v else "." for v in row))
        f.write("}\n")

    print("\n64×64 用色 %d 种；16×16 黑格 %d/256" % (len(order), sum(sum(r) for r in mask16)))
    print("\n--- 16×16 ---")
    for row in mask16:
        print("".join("#" if v else "." for v in row))
    with open(os.path.join(OUT, "_grid.json"), "w", encoding="utf-8") as f:
        json.dump({"pal": ["%02X%02X%02X" % c for c in pal],
                   "order": order, "grid": grid, "mask16": mask16}, f)


if __name__ == "__main__":
    main()
