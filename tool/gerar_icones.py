"""Gera os ícones dos apps (arte original, desenhada em código).

Para cada app produz:
  icone.png        1024x1024, fundo cheio (iOS e Android legado)
  icone_frente.png 1024x1024, fundo transparente, desenho na zona segura (Android adaptativo)
"""
import math
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONTE = str(__import__('pathlib').Path(__file__).resolve().parent.parent / 'assets' / 'fonts' / 'NotoSans-Bold.ttf')

S = 4  # superamostragem
N = 1024 * S


def novo(transparente=False):
    return Image.new('RGBA', (N, N), (0, 0, 0, 0) if transparente else (0, 0, 0, 255))


def fundo_gradiente(img, c1, c2):
    d = ImageDraw.Draw(img)
    for y in range(N):
        t = y / (N - 1)
        c = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3)) + (255,)
        d.line([(0, y), (N, y)], fill=c)


def finalizar(img):
    return img.resize((1024, 1024), Image.LANCZOS)


def p(x, y, escala, cx=512, cy=512):
    """Converte coordenadas do desenho (0..1024) aplicando escala em torno do centro."""
    return ((cx + (x - cx) * escala) * S, (cy + (y - cy) * escala) * S)


# ---------------- Coqueiro ----------------
def desenhar_coqueiro(img, escala):
    d = ImageDraw.Draw(img)
    # Areia / chão
    d.ellipse([*p(250, 800, escala), *p(800, 900, escala)], fill=(233, 201, 139, 255))
    # Tronco curvo (segmentos)
    pts = []
    for i in range(0, 21):
        t = i / 20
        x = 560 - 90 * math.sin(t * math.pi * 0.9) + 40 * t
        y = 850 - 460 * t
        pts.append((x, y))
    for i, (x, y) in enumerate(pts[:-1]):
        larg = 46 - 18 * (i / 20)
        x2, y2 = pts[i + 1]
        cor = (166, 112, 62, 255) if i % 2 == 0 else (140, 92, 50, 255)
        d.polygon([p(x - larg, y, escala), p(x + larg, y, escala), p(x2 + larg - 2, y2, escala), p(x2 - larg + 2, y2, escala)],
                  fill=cor)
    topo = pts[-1]
    # Folhas (palmas)
    folhas = [(-165, 40), (-120, -55), (-45, -110), (45, -115), (125, -60), (170, 35), (-10, -125)]
    for ang_x, ang_y in folhas:
        fx, fy = topo[0] + ang_x * 1.6, topo[1] + ang_y * 1.4
        cx, cy = (topo[0] + fx) / 2, min(topo[1], fy) - 70
        curva = []
        for k in range(0, 31):
            t = k / 30
            x = (1 - t) ** 2 * topo[0] + 2 * (1 - t) * t * cx + t ** 2 * fx
            y = (1 - t) ** 2 * topo[1] + 2 * (1 - t) * t * cy + t ** 2 * fy
            curva.append((x, y))
        # contorno da folha com largura variável
        lado_a, lado_b = [], []
        for k, (x, y) in enumerate(curva):
            t = k / 30
            w = 34 * math.sin(math.pi * min(1, t * 1.1))
            if k < 30:
                nx, ny = curva[k + 1][0] - x, curva[k + 1][1] - y
            else:
                nx, ny = x - curva[k - 1][0], y - curva[k - 1][1]
            n = math.hypot(nx, ny) or 1
            ox, oy = -ny / n * w, nx / n * w
            lado_a.append(p(x + ox, y + oy, escala))
            lado_b.append(p(x - ox, y - oy, escala))
        d.polygon(lado_a + lado_b[::-1], fill=(132, 196, 74, 255))
        d.line([p(x, y, escala) for x, y in curva], fill=(92, 150, 46, 255), width=int(6 * S * escala))
    # Cocos
    for dx, dy, cor in [(-38, 30, (122, 74, 36, 255)), (30, 34, (102, 60, 28, 255)), (-2, 66, (96, 158, 58, 255))]:
        x, y = topo[0] + dx, topo[1] + dy
        r = 38
        d.ellipse([*p(x - r, y - r, escala), *p(x + r, y + r, escala)], fill=cor)
        d.ellipse([*p(x - r * 0.45, y - r * 0.6, escala), *p(x - r * 0.05, y - r * 0.25, escala)], fill=(255, 255, 255, 60))


# ---------------- Sacola de compras ----------------
def desenhar_sacola(img, escala):
    d = ImageDraw.Draw(img)
    # Sombra
    sombra = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ds = ImageDraw.Draw(sombra)
    ds.rounded_rectangle([*p(300, 400, escala), *p(740, 860, escala)], radius=int(40 * S * escala), fill=(0, 0, 0, 90))
    sombra = sombra.filter(ImageFilter.GaussianBlur(18 * S * escala))
    img.alpha_composite(sombra, (int(12 * S * escala), int(18 * S * escala)))
    d = ImageDraw.Draw(img)
    # Alça
    d.arc([*p(400, 250, escala), *p(640, 520, escala)], start=180, end=360, fill=(255, 255, 255, 255), width=int(34 * S * escala))
    # Corpo da sacola
    d.rounded_rectangle([*p(290, 380, escala), *p(730, 840, escala)], radius=int(40 * S * escala), fill=(255, 255, 255, 255))
    # Furos da alça
    for x in (420, 620):
        d.ellipse([*p(x - 16, 410, escala), *p(x + 16, 442, escala)], fill=(142, 59, 110, 255))
    # Faixa do catálogo
    d.rounded_rectangle([*p(340, 520, escala), *p(680, 560, escala)], radius=int(16 * S * escala), fill=(246, 214, 232, 255))
    d.rounded_rectangle([*p(340, 590, escala), *p(560, 625, escala)], radius=int(14 * S * escala), fill=(246, 214, 232, 255))
    # Etiqueta de preço (dourada), inclinada
    tag = Image.new('RGBA', img.size, (0, 0, 0, 0))
    dt = ImageDraw.Draw(tag)
    cx, cy = 640, 720
    dt.polygon([p(cx - 120, cy - 70, escala), p(cx + 60, cy - 70, escala), p(cx + 130, cy, escala),
                p(cx + 60, cy + 70, escala), p(cx - 120, cy + 70, escala)], fill=(242, 182, 50, 255))
    dt.ellipse([*p(cx + 38, cy - 16, escala), *p(cx + 70, cy + 16, escala)], fill=(255, 255, 255, 255))
    # "R$" com a fonte Noto Sans Bold do próprio app
    fonte = ImageFont.truetype(FONTE, int(78 * S * escala))
    dt.text(p(cx - 38, cy + 4, escala), 'R$', font=fonte, fill=(122, 46, 93, 255), anchor='mm')
    tag = tag.rotate(-14, center=p(cx, cy, escala), resample=Image.BICUBIC)
    img.alpha_composite(tag)


# ---------------- Bolo ----------------
def desenhar_bolo(img, escala):
    d = ImageDraw.Draw(img)
    # Prato
    d.ellipse([*p(230, 790, escala), *p(794, 870, escala)], fill=(255, 255, 255, 235))
    # Andar de baixo
    d.rounded_rectangle([*p(290, 560, escala), *p(734, 820, escala)], radius=int(36 * S * escala), fill=(240, 160, 190, 255))
    d.rectangle([*p(290, 690, escala), *p(734, 712, escala)], fill=(255, 236, 214, 255))  # recheio
    # Andar de cima
    d.rounded_rectangle([*p(370, 400, escala), *p(654, 580, escala)], radius=int(30 * S * escala), fill=(240, 160, 190, 255))
    # Cobertura com pingos (andar de cima)
    d.rounded_rectangle([*p(360, 392, escala), *p(664, 450, escala)], radius=int(28 * S * escala), fill=(255, 250, 244, 255))
    for x, h in [(395, 40), (450, 62), (510, 36), (565, 58), (625, 44)]:
        d.rounded_rectangle([*p(x - 17, 420, escala), *p(x + 17, 450 + h, escala)], radius=int(17 * S * escala), fill=(255, 250, 244, 255))
    # Cobertura com pingos (andar de baixo)
    d.rounded_rectangle([*p(280, 552, escala), *p(744, 612, escala)], radius=int(30 * S * escala), fill=(255, 250, 244, 255))
    for x, h in [(320, 48), (385, 70), (450, 42), (515, 74), (580, 46), (645, 66), (705, 44)]:
        d.rounded_rectangle([*p(x - 19, 585, escala), *p(x + 19, 612 + h, escala)], radius=int(19 * S * escala), fill=(255, 250, 244, 255))
    # Confeitos
    for x, y, c in [(330, 760, (255, 214, 92)), (420, 780, (126, 200, 227)), (520, 755, (255, 214, 92)),
                    (610, 785, (126, 200, 227)), (690, 760, (255, 255, 255)), (440, 520, (255, 214, 92)), (590, 530, (126, 200, 227))]:
        d.ellipse([*p(x - 10, y - 10, escala), *p(x + 10, y + 10, escala)], fill=c + (255,))
    # Vela e chama
    d.rounded_rectangle([*p(497, 260, escala), *p(527, 400, escala)], radius=int(10 * S * escala), fill=(126, 200, 227, 255))
    for k in range(3):
        y = 285 + k * 40
        d.line([p(497, y + 18, escala), p(527, y, escala)], fill=(255, 255, 255, 255), width=int(8 * S * escala))
    d.ellipse([*p(488, 185, escala), *p(536, 262, escala)], fill=(255, 196, 61, 255))
    d.ellipse([*p(500, 212, escala), *p(524, 255, escala)], fill=(255, 240, 180, 255))


# ---------------- Carrinho de compras ----------------
def desenhar_carrinho(img, escala):
    d = ImageDraw.Draw(img)
    branco = (255, 255, 255, 255)
    # Caixas dentro do carrinho
    d.rounded_rectangle([*p(400, 330, escala), *p(540, 480, escala)], radius=int(12 * S * escala), fill=(255, 196, 61, 255))
    d.rectangle([*p(462, 330, escala), *p(478, 480, escala)], fill=(230, 160, 30, 255))
    d.rounded_rectangle([*p(555, 380, escala), *p(690, 480, escala)], radius=int(12 * S * escala), fill=(120, 210, 160, 255))
    d.rounded_rectangle([*p(300, 400, escala), *p(390, 480, escala)], radius=int(12 * S * escala), fill=(255, 140, 120, 255))
    # Cesto
    d.polygon([p(250, 470, escala), p(770, 470, escala), p(720, 650, escala), p(320, 650, escala)], fill=branco)
    for x in (390, 480, 570, 660):
        d.line([p(x, 500, escala), p(x - 10, 620, escala)], fill=(31, 95, 168, 255), width=int(14 * S * escala))
    # Alça e estrutura
    d.line([p(160, 360, escala), p(240, 360, escala), p(330, 720, escala), p(720, 720, escala)], fill=branco,
           width=int(34 * S * escala), joint='curve')
    # Rodas
    for x in (370, 680):
        d.ellipse([*p(x - 42, 760, escala), *p(x + 42, 844, escala)], fill=branco)
        d.ellipse([*p(x - 16, 786, escala), *p(x + 16, 818, escala)], fill=(31, 95, 168, 255))


# ---------------- Agenda com coração (serviços) ----------------
def desenhar_servicos(img, escala):
    d = ImageDraw.Draw(img)
    branco = (255, 255, 255, 255)
    rosa = (180, 69, 122, 255)
    # Calendário
    d.rounded_rectangle([*p(250, 300, escala), *p(774, 800, escala)], radius=int(60 * S * escala), fill=branco)
    d.rounded_rectangle([*p(250, 300, escala), *p(774, 420, escala)], radius=int(60 * S * escala), fill=(246, 214, 231, 255))
    d.rectangle([*p(250, 380, escala), *p(774, 420, escala)], fill=(246, 214, 231, 255))
    for x in (380, 644):
        d.rounded_rectangle([*p(x - 22, 250, escala), *p(x + 22, 350, escala)], radius=int(22 * S * escala), fill=(142, 47, 94, 255))
    # Coração
    cx, cy, r = 512, 585, 72
    d.ellipse([*p(cx - 2 * r + 10, cy - r - 20, escala), *p(cx + 10, cy + r - 20, escala)], fill=rosa)
    d.ellipse([*p(cx - 10, cy - r - 20, escala), *p(cx + 2 * r - 10, cy + r - 20, escala)], fill=rosa)
    d.polygon([p(cx - 2 * r + 14, cy - 2, escala), p(cx + 2 * r - 14, cy - 2, escala), p(cx, cy + 150, escala)], fill=rosa)
    # Brilho dourado
    sx, sy, t = 730, 300, 70
    d.polygon([p(sx, sy - t, escala), p(sx + 16, sy - 16, escala), p(sx + t, sy, escala), p(sx + 16, sy + 16, escala),
               p(sx, sy + t, escala), p(sx - 16, sy + 16, escala), p(sx - t, sy, escala), p(sx - 16, sy - 16, escala)],
              fill=(255, 205, 90, 255))


def gerar(app, destino):
    if app == 'coco':
        cor1, cor2, desenho = (46, 107, 58), (24, 74, 36), desenhar_coqueiro
    elif app == 'servicos':
        cor1, cor2, desenho = (196, 84, 138), (142, 47, 94), desenhar_servicos
    elif app == 'geral':
        cor1, cor2, desenho = (44, 120, 200), (23, 74, 133), desenhar_carrinho
    elif app == 'bolo':
        cor1, cor2, desenho = (123, 63, 97), (88, 40, 68), desenhar_bolo
    else:
        cor1, cor2, desenho = (176, 72, 136), (122, 46, 93), desenhar_sacola
    cheio = novo()
    fundo_gradiente(cheio, cor1, cor2)
    desenho(cheio, 0.92)
    finalizar(cheio).convert('RGB').save(f'{destino}/icone.png')
    frente = novo(transparente=True)
    desenho(frente, 0.62)  # zona segura do ícone adaptativo (~66%)
    finalizar(frente).save(f'{destino}/icone_frente.png')


if __name__ == '__main__':
    gerar(sys.argv[1], sys.argv[2])
