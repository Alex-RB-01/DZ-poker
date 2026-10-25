"""生成动作语音（真人声占位）：男声(Yunxi) / 女声(Xiaoxiao)，覆盖 弃牌/跟注/加注/全下。

用法：
  python3 gen_voices.py
输出到 assets/voices/voice_{male|female}_{fold|call|raise|allin}.mp3

说明：受工具限制无法克隆真实明星声线，这里用高质量中文神经 TTS 作为占位真人声。
若你有肖战 / 林志玲等真人配音片段，按同名文件替换 assets/voices/ 下对应 mp3 即可
（替换后需修改 lib/util/voice_sound.dart 中的扩展名为对应格式，或保持 .mp3）。
"""
import asyncio
import os

import edge_tts

OUT_DIR = os.path.join(os.path.dirname(__file__), 'assets', 'voices')
TEXTS = {
    'fold': '弃牌',
    'check': '过牌',
    'call': '跟注',
    'raise': '加注',
    'allin': 'all in',
}
VOICES = {
    'male': 'zh-CN-YunxiNeural',     # 男声
    'female': 'zh-CN-XiaoxiaoNeural',  # 女声
}


async def gen_one(gender: str, clip: str, text: str):
    voice = VOICES[gender]
    out = os.path.join(OUT_DIR, f'voice_{gender}_{clip}.mp3')
    communicate = edge_tts.Communicate(text, voice)
    await communicate.save(out)
    print('saved', out)


async def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for gender in VOICES:
        for clip, text in TEXTS.items():
            await gen_one(gender, clip, text)


if __name__ == '__main__':
    asyncio.run(main())
