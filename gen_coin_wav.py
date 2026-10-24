"""生成金币「哗啦啦」音效 assets/coin.wav（纯标准库合成，无需 numpy）。"""
import math
import os
import random
import struct
import wave

SR = 44100
DUR = 0.6
N = int(SR * DUR)
random.seed(20261024)
samples = [0.0] * N


def add_clink(start, base, amp, decay):
    # 金属质感：多个非谐波分音 + 快速衰减
    ratios = [1.0, 1.51, 2.13, 2.74, 3.46, 4.12]
    s0 = int(start * SR)
    for k, r in enumerate(ratios):
        f = base * r
        a = amp / (k + 1)
        length = int(decay * SR * 3)
        for i in range(length):
            idx = s0 + i
            if idx >= N:
                break
            t = i / SR
            env = math.exp(-t * decay * 8)
            samples[idx] += a * env * math.sin(2 * math.pi * f * t)


# 开场一缕「哗」的高频噪声底
for i in range(int(0.05 * SR)):
    t = i / SR
    env = math.exp(-t * 60)
    samples[i] += random.uniform(-1, 1) * 0.12 * env

# 一串细碎的金属碰撞
for _ in range(9):
    start = random.uniform(0.0, 0.46)
    base = random.uniform(2200, 5200)
    amp = random.uniform(0.25, 0.5)
    decay = random.uniform(0.05, 0.11)
    add_clink(start, base, amp, decay)

peak = max(1e-9, max(abs(s) for s in samples))
gain = 0.9 / peak
out = b""
for s in samples:
    v = int(max(-1.0, min(1.0, s * gain)) * 32767)
    out += struct.pack("<h", v)

os.makedirs("assets", exist_ok=True)
with wave.open("assets/coin.wav", "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(out)
print("wrote assets/coin.wav", len(out), "bytes")
