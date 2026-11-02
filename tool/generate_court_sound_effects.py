from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path("assets/court_sounds")
RATE = 22050
ROOT.mkdir(parents=True, exist_ok=True)
random.seed(8)

def render(name, length, tones=(), knocks=(), gain=0.72):
    count = int(RATE * length)
    samples = [0.0] * count

    def add_tone(freq, start, duration, amplitude=0.12, waveform="sine", decay=5.2):
        first = int(start * RATE)
        size = min(int(duration * RATE), count - first)
        for i in range(max(0, size)):
            t = i / RATE
            attack = min(1.0, t / 0.008)
            envelope = attack * math.exp(-decay * t / max(duration, 0.001))
            value = math.sin(2 * math.pi * freq * t)
            if waveform == "bell":
                value = (value + 0.32 * math.sin(2 * math.pi * freq * 2.01 * t)
                         + 0.12 * math.sin(2 * math.pi * freq * 3.9 * t))
            samples[first + i] += amplitude * envelope * value

    def add_knock(start, amplitude=0.25):
        first = int(start * RATE)
        duration = 0.19
        size = min(int(duration * RATE), count - first)
        for i in range(max(0, size)):
            t = i / RATE
            envelope = math.exp(-31 * t)
            noise = (random.random() * 2 - 1) * 0.045
            low = math.sin(2 * math.pi * 112 * t) + 0.34 * math.sin(2 * math.pi * 224 * t)
            samples[first + i] += amplitude * envelope * (0.82 * low + noise)

    for freq, start, duration, amplitude, waveform in tones:
        add_tone(freq, start, duration, amplitude, waveform)
    for start, amplitude in knocks:
        add_knock(start, amplitude)

    peak = max(0.001, max(abs(s) for s in samples))
    scale = min(0.82, gain / peak)
    path = ROOT / name
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, value * scale)) * 32767))
            for value in samples
        ))

render("objection.wav", 0.65, tones=[(740, .04, .11, .065, "bell")], knocks=[(0.0, .30), (.24, .24)])
render("sustained.wav", 0.72, tones=[(659, .18, .25, .11, "bell"), (784, .32, .27, .08, "bell")], knocks=[(0.0, .24)])
render("overruled.wav", 0.78, tones=[(440, .19, .22, .10, "bell"), (330, .38, .27, .09, "bell")], knocks=[(0.0, .29)])
render("verdict.wav", 1.12, tones=[(523, .08, .38, .11, "bell"), (659, .25, .40, .11, "bell"), (784, .47, .52, .10, "bell")], knocks=[(0.0, .23)])
render("appeal_decision.wav", 1.08, tones=[(392, .08, .35, .09, "bell"), (523, .28, .40, .10, "bell"), (698, .50, .48, .09, "bell")], knocks=[(0.0, .20)])
render("accepted.wav", 0.94, tones=[(523, .02, .27, .10, "bell"), (659, .18, .33, .10, "bell"), (784, .38, .48, .09, "bell")])
render("unresolved.wav", 0.8, tones=[(440, .03, .32, .075, "bell"), (349, .27, .38, .065, "bell")])
render("evidence.wav", 0.42, tones=[(1260, .02, .035, .075, "sine"), (940, .13, .04, .06, "sine"), (587, .20, .18, .06, "bell")])
render("turn.wav", 0.38, tones=[(587, .02, .16, .07, "bell"), (740, .16, .18, .06, "bell")])
render("courtroom.wav", 0.88, tones=[(659, .42, .35, .08, "bell")], knocks=[(0.0, .27), (.23, .20)])
render("judge_voice.wav", 0.25, tones=[(196, .02, .11, .045, "sine"), (220, .12, .11, .035, "sine")])
render("partner_voice.wav", 0.25, tones=[(523, .02, .10, .04, "sine"), (659, .12, .11, .03, "sine")])
render("type_tick.wav", 0.035, tones=[(740, .0, .024, .025, "sine")], gain=.25)

for path in sorted(ROOT.glob("*.wav")):
    print(f"{path.name}: {path.stat().st_size} bytes")
