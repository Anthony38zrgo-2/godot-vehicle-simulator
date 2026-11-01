"""Reproducible procedural sand-on-bodywork one-shot. Python + numpy only."""
from pathlib import Path
import hashlib, json, wave
import numpy as np
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/sounds/banks/surfaces/synthetic"
def main():
    rate, duration, seed = 22050, 0.72, 43017
    rng = np.random.default_rng(seed)
    count = round(rate * duration)
    signal = np.zeros(count)
    for onset in np.sort(rng.uniform(0.015, 0.40, 95)):
        length = round(rate * rng.uniform(0.008, 0.045))
        t = np.arange(length) / rate
        noise = rng.normal(size=length)
        # Fine grains, with quiet damped panel resonances rather than a crash.
        noise = np.convolve(noise, np.array([0.25, 0.5, 0.25]), mode="same")
        grain = (noise * 0.8 + 0.12 * np.sin(2*np.pi*rng.uniform(650,1400)*t))
        grain *= (1-np.exp(-t/0.0007))*np.exp(-t/rng.uniform(0.003,0.012))
        start = round(onset * rate)
        signal[start:start+length] += grain * rng.uniform(0.1,0.55) * np.exp(-onset/0.23)
    frequencies = np.fft.rfftfreq(count, 1/rate)
    response = (frequencies / np.maximum(frequencies, 250))**2 / np.sqrt(1+(frequencies/4800)**8)
    signal = np.fft.irfft(np.fft.rfft(signal)*response, n=count)
    signal -= signal.mean()
    fade = round(rate*0.015)
    signal[:fade] *= np.linspace(0,1,fade)
    signal[-fade:] *= np.linspace(1,0,fade)
    signal *= 10**(-9/20) / max(np.max(np.abs(signal)),1e-12)
    pcm = np.round(signal*32767).astype("<i2")
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / "sand_body_impact.wav"
    with wave.open(str(path),"wb") as w:
        w.setparams((1,2,rate,0,"NONE","not compressed"));w.writeframes(pcm.tobytes())
    (OUT/"manifest.json").write_text(json.dumps({"source":"Original procedural synthesis; no game samples", "generator":"tools/audio/synthesize_sand_impact.py", "seed":seed,"sample_rate":rate,"channels":1,"bits":16,"duration_s":duration,"peak_dbfs":-9,"rms_dbfs":float(20*np.log10(np.sqrt(np.mean(signal**2)))),"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"role":"Sparse sand grains hitting bodywork; non-looping; Sand contact only"},indent=2)+"\n")
    print(path)
if __name__ == "__main__": main()
