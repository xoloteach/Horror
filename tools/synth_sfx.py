#!/usr/bin/env python3
"""
Procedural combat SFX synthesizer for MIDGARD FURY.

Generates every sound effect the game needs from first principles:
  - band-limited noise swooshes with time-varying formant sweeps (axe swings)
  - transient + modal synthesis (stone / wood embeds, metallic catch)
  - source-filter voice synthesis (grunts, draugr roars)
  - layered thump + grit (footsteps, flesh impacts)

Output: 22050 Hz mono 16-bit WAV. Authored from scratch -> CC0 / public domain.

Usage: python3 tools/synth_sfx.py [outdir]
"""
import os
import sys
import numpy as np
from scipy.io import wavfile

SR = 22050
rng = np.random.default_rng(0xA7E)


# ---------------------------------------------------------------- primitives

def n_samples(dur):
    return int(round(dur * SR))


def noise(dur):
    return rng.uniform(-1.0, 1.0, n_samples(dur))


def t_axis(dur):
    return np.arange(n_samples(dur)) / SR


def env_ad(dur, attack, decay, curve=2.0):
    """Attack/decay envelope with exponential-ish decay shaping."""
    n = n_samples(dur)
    t = np.arange(n) / SR
    a = np.clip(t / max(attack, 1e-6), 0.0, 1.0)
    d = np.exp(-curve * np.clip((t - attack) / max(decay, 1e-6), 0.0, None))
    return a * d


def env_hump(dur, peak=0.45, width=0.5):
    """Smooth bell envelope - used for swing swooshes."""
    t = t_axis(dur) / dur
    return np.exp(-((t - peak) ** 2) / (2.0 * (width * 0.35) ** 2))


def svf_bandpass(x, fc, q):
    """Cytomic TPT state-variable bandpass with per-sample modulated cutoff.

    fc may be a scalar or an array the same length as x. This is what makes the
    swooshes read as *motion* rather than as a static noise burst.
    """
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, dtype=float), (n,))
    fc = np.clip(fc, 20.0, SR * 0.45)
    g = np.tan(np.pi * fc / SR)
    k = 1.0 / max(q, 0.05)
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    out = np.empty(n)
    ic1 = 0.0
    ic2 = 0.0
    for i in range(n):
        v3 = x[i] - ic2
        v1 = a1[i] * ic1 + a2[i] * v3
        v2 = ic2 + a2[i] * ic1 + a3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        out[i] = v1
    return out


def svf_lowpass(x, fc, q=0.707):
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, dtype=float), (n,))
    fc = np.clip(fc, 20.0, SR * 0.45)
    g = np.tan(np.pi * fc / SR)
    k = 1.0 / max(q, 0.05)
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    out = np.empty(n)
    ic1 = 0.0
    ic2 = 0.0
    for i in range(n):
        v3 = x[i] - ic2
        v1 = a1[i] * ic1 + a2[i] * v3
        v2 = ic2 + a2[i] * ic1 + a3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        out[i] = v2
    return out


def modal(dur, partials):
    """Sum of exponentially-decaying sinusoids.

    partials: list of (freq_hz, decay_rate, amplitude). Inharmonic ratios give
    metal/stone character; harmonic ratios give wood/tonal character.
    """
    t = t_axis(dur)
    out = np.zeros_like(t)
    for f, dec, amp in partials:
        phase = rng.uniform(0, 2 * np.pi)
        out += amp * np.sin(2 * np.pi * f * t + phase) * np.exp(-dec * t)
    return out


def click(dur, bright=6000.0, decay=900.0):
    """Broadband attack transient - the 'crack' of an impact."""
    t = t_axis(dur)
    x = noise(dur) * np.exp(-decay * t)
    return svf_lowpass(x, bright)


def pulse_train(dur, f0_curve, duty=0.35):
    """Glottal-ish pulse source for voice synthesis."""
    n = n_samples(dur)
    f0 = np.broadcast_to(np.asarray(f0_curve, dtype=float), (n,))
    phase = np.cumsum(f0 / SR) % 1.0
    # bandlimited-ish sawtooth shaped into an asymmetric pulse
    saw = 2.0 * phase - 1.0
    return np.where(phase < duty, saw, -0.25 * saw)


def formants(x, table):
    """Apply parallel formant bandpasses: table = [(freq, q, gain), ...]"""
    out = np.zeros_like(x)
    for f, q, g in table:
        out += g * svf_bandpass(x, f, q)
    return out


def soft_clip(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def normalize(x, peak=0.89):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 1e-9 else x


def fade_edges(x, ms=4.0):
    k = max(2, int(SR * ms / 1000.0))
    k = min(k, len(x) // 2)
    w = np.linspace(0.0, 1.0, k)
    x = x.copy()
    x[:k] *= w
    x[-k:] *= w[::-1]
    return x


def save(name, x, gain=1.0, outdir="."):
    x = fade_edges(normalize(np.nan_to_num(x))) * gain
    x = np.clip(x, -1.0, 1.0)
    path = os.path.join(outdir, name + ".wav")
    wavfile.write(path, SR, (x * 32767.0).astype(np.int16))
    print(f"  {name+'.wav':28s} {len(x)/SR:5.2f}s  {os.path.getsize(path)//1024:4d}KB")


# ------------------------------------------------------------------- sounds

def swing(dur, lo, hi, q, grit, drive, whump=0.0):
    """Axe swoosh: noise through a bandpass whose centre sweeps up then down,
    tracking the arc of the blade past the camera.

    `whump` adds a low-mid displaced-air layer. Without it a swing is pure hiss
    and reads as weightless, so heavy swings lean on it hard.
    """
    t = t_axis(dur) / dur
    # centre frequency rises into the swing and falls off as it passes
    sweep = lo + (hi - lo) * np.sin(np.pi * np.clip(t, 0, 1) ** 0.85)
    x = noise(dur)
    body = svf_bandpass(x, sweep, q)
    # a second, higher, narrower band adds the "edge cutting air" hiss
    edge = svf_bandpass(x, sweep * 2.6, q * 1.8) * grit
    # low-mid mass: the volume of air actually being shoved out of the way
    low = svf_bandpass(x, np.clip(sweep * 0.30, 120, 520), 0.7) * whump * 1.6
    sig = (body + edge + low) * env_hump(dur, peak=0.52, width=0.62)
    return soft_clip(sig * 1.4, drive)


def flesh_impact(dur=0.34, wet=1.0):
    """Layered: bone-thud body + wet squelch mid + brief slicing transient.

    Deliberately mid-forward. An all-sub impact measures 'heavy' but vanishes on
    laptop and phone speakers, so the crunch/squelch layers carry the read.
    """
    t = t_axis(dur)
    thud = np.sin(2 * np.pi * 78 * t * (1 - 0.25 * t / dur)) * np.exp(-30 * t) * 0.50
    body = svf_bandpass(noise(dur), 260, 1.3) * np.exp(-24 * t) * 0.52
    squelch = svf_bandpass(noise(dur), np.linspace(1700, 380, n_samples(dur)), 1.0)
    squelch *= np.exp(-17 * t) * wet
    crunch = svf_bandpass(noise(dur), 900, 1.6) * np.exp(-30 * t) * 0.58
    slice_ = svf_bandpass(noise(dur), 4200, 2.2) * np.exp(-70 * t) * 0.60
    spray = svf_lowpass(noise(dur), 1200) * np.exp(-9 * t) * 0.18 * wet
    return soft_clip(thud + body + squelch * 0.95 + crunch + slice_ + spray, 1.7)


def embed_stone(dur=0.85):
    """Axe biting rock: hard crack, inharmonic stone ring, gravel debris tail."""
    t = t_axis(dur)
    crack = click(dur, bright=7500, decay=1100) * 1.0
    ring = modal(dur, [
        (2190, 34, 0.55), (3170, 41, 0.38), (4630, 55, 0.24),
        (1480, 28, 0.42), (6100, 70, 0.14),
    ])
    gravel = svf_bandpass(noise(dur), 2600, 0.8) * np.exp(-11 * t) * 0.3
    debris = svf_bandpass(noise(dur), 5200, 1.4) * np.exp(-4.0 * t) * 0.12
    sub = np.sin(2 * np.pi * 58 * t) * np.exp(-30 * t) * 0.6
    return soft_clip(crack + ring * 0.8 + gravel + debris + sub, 1.6)


def embed_wood(dur=0.7):
    """Deeper, woodier thunk with more harmonic content and a shorter tail."""
    t = t_axis(dur)
    crack = click(dur, bright=3600, decay=1400) * 0.85
    ring = modal(dur, [
        (196, 17, 0.70), (388, 22, 0.44), (612, 30, 0.26),
        (905, 40, 0.15), (1340, 52, 0.09),
    ])
    body = np.sin(2 * np.pi * 96 * t) * np.exp(-21 * t) * 0.7
    splinter = svf_bandpass(noise(dur), 3100, 1.2) * np.exp(-26 * t) * 0.18
    return soft_clip(crack + ring + body + splinter, 1.5)


def recall_whistle(dur=1.1):
    """Leviathan in flight: rising airy tone + rotor-style tremolo from the
    axe head spinning, so the pitch wobble sells the rotation."""
    t = t_axis(dur)
    k = t / dur
    f = 430 + 900 * k ** 1.7
    spin = 1.0 + 0.30 * np.sin(2 * np.pi * 19 * t)
    tone = np.sin(2 * np.pi * np.cumsum(f * spin) / SR)
    tone += 0.42 * np.sin(2 * np.pi * np.cumsum(f * 2.01 * spin) / SR)
    air = svf_bandpass(noise(dur), f * 3.1, 1.1) * 0.5
    chop = 0.72 + 0.28 * np.sin(2 * np.pi * 19 * t)  # blade chopping air
    amp = np.clip(k * 5.0, 0, 1) * (0.35 + 0.65 * k)
    return soft_clip((tone * 0.55 + air) * chop * amp, 1.5)


def catch_metal(dur=1.5):
    """The money sound: leather-glove slap transient into a long, resonant,
    inharmonic iron ring. Low partials decay slowly so it blooms after impact."""
    t = t_axis(dur)
    slap = svf_bandpass(noise(dur), 1250, 0.9) * np.exp(-58 * t) * 0.85
    leather = svf_lowpass(noise(dur), 520) * np.exp(-40 * t) * 0.5
    ring = modal(dur, [
        (327, 2.6, 1.00), (466, 3.1, 0.72), (694, 4.0, 0.55),
        (941, 5.2, 0.40), (1283, 6.8, 0.30), (1735, 9.0, 0.20),
        (2410, 12.0, 0.13), (3180, 16.0, 0.08),
    ])
    thump = np.sin(2 * np.pi * 88 * t) * np.exp(-24 * t) * 0.65
    return soft_clip(slap + leather + ring * 0.9 + thump, 1.35)


def grunt(dur=0.38, f0=118.0, drop=0.72, breath=0.3, seed_shift=0.0):
    """Player effort grunt via source-filter synthesis with a falling pitch."""
    t = t_axis(dur)
    k = t / dur
    f0c = f0 * (1.0 + 0.10 * np.sin(2 * np.pi * 5.5 * t)) * (1.0 - (1.0 - drop) * k)
    src = pulse_train(dur, f0c, duty=0.32)
    voiced = formants(src, [
        (620 + seed_shift, 7.0, 1.00),
        (1180 + seed_shift * 1.5, 9.0, 0.55),
        (2580, 11.0, 0.24),
    ])
    aspir = svf_bandpass(noise(dur), 1700, 1.0) * breath
    e = env_ad(dur, 0.018, dur * 0.42, curve=2.6)
    return soft_clip((voiced * 0.9 + aspir) * e, 1.8)


def draugr_roar(dur=1.25):
    """Undead roar: very low fundamental, subharmonic growl, heavy distortion,
    plus a rasping noise layer so it reads as inhuman."""
    t = t_axis(dur)
    k = t / dur
    f0 = 68.0 * (1.0 + 0.22 * np.sin(2 * np.pi * 3.1 * t)) * (1.0 - 0.18 * k)
    src = pulse_train(dur, f0, duty=0.44)
    sub = pulse_train(dur, f0 * 0.5, duty=0.5) * 0.55  # period doubling = growl
    growl = 0.78 + 0.22 * np.sin(2 * np.pi * 27 * t)   # amplitude modulation
    voiced = formants(src + sub, [
        (420, 5.5, 1.00), (900, 7.0, 0.62), (1950, 9.0, 0.28),
    ])
    rasp = svf_bandpass(noise(dur), np.linspace(900, 2400, n_samples(dur)), 0.9) * 0.42
    e = np.clip(k * 7.0, 0, 1) * np.exp(-1.5 * np.clip(k - 0.45, 0, None) * 3.2)
    return soft_clip((voiced * 0.85 + rasp) * growl * e, 3.0)


def footstep(dur=0.26, weight=1.0, grit_f=2400.0):
    """Heavy boot: sub thump, low-mid leather body, gravel scatter.

    Balanced so the step is still audible on speakers with no sub response -- a
    pure 70 Hz thump is physically correct but perceptually silent on a laptop.
    """
    t = t_axis(dur)
    sub = np.sin(2 * np.pi * (64 * weight) * t) * np.exp(-40 * t) * 0.55
    body = np.sin(2 * np.pi * (168 * weight) * t) * np.exp(-30 * t) * 0.42
    body += svf_bandpass(noise(dur), 330 * weight, 1.4) * np.exp(-28 * t) * 0.58
    knock = svf_bandpass(noise(dur), 780, 1.1) * np.exp(-48 * t) * 0.50
    grit = svf_bandpass(noise(dur), grit_f, 1.0) * np.exp(-40 * t) * 0.62
    scuff = svf_bandpass(noise(dur), grit_f * 1.9, 1.6) * np.exp(-20 * t) * 0.30
    return soft_clip(sub + body + knock + grit + scuff, 1.5)


def dodge_whoosh(dur=0.34):
    """Cloth/body roll - darker and softer than a blade swing."""
    t = t_axis(dur) / dur
    sweep = 380 + 900 * np.sin(np.pi * np.clip(t, 0, 1))
    x = svf_bandpass(noise(dur), sweep, 0.85)
    cloth = svf_bandpass(noise(dur), 3400, 1.3) * 0.25
    return soft_clip((x + cloth) * env_hump(dur, 0.45, 0.7), 1.3)


def stagger_hit(dur=0.5):
    """Enemy flinch: dull bone knock with a short dissonant ring."""
    t = t_axis(dur)
    knock = click(dur, bright=2400, decay=1600) * 0.8
    ring = modal(dur, [(240, 26, 0.6), (357, 33, 0.35), (533, 44, 0.2)])
    body = np.sin(2 * np.pi * 82 * t) * np.exp(-28 * t) * 0.7
    return soft_clip(knock + ring + body, 1.5)


def ui_click(dur=0.12):
    t = t_axis(dur)
    ring = modal(dur, [(880, 40, 0.7), (1320, 55, 0.35)])
    tick = click(dur, bright=5200, decay=2600) * 0.5
    return soft_clip(ring + tick, 1.2)


# ---------------------------------------------------------------------- main

def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "assets/audio"
    os.makedirs(outdir, exist_ok=True)
    print(f"Synthesizing SFX -> {outdir}")

    # --- axe swings: light is faster/brighter, heavy is slower/lower/meatier
    save("swing_light", swing(0.30, 260, 2600, 1.05, 0.45, 1.6, whump=0.22), 0.85, outdir)
    save("swing_light_alt", swing(0.27, 300, 3000, 1.20, 0.52, 1.6, whump=0.18), 0.85, outdir)
    save("swing_heavy", swing(0.52, 140, 1500, 0.80, 0.30, 2.2, whump=1.00), 1.00, outdir)
    save("throw_release", swing(0.36, 200, 2200, 0.95, 0.60, 1.9, whump=0.55), 0.95, outdir)

    # --- impacts
    save("hit_flesh", flesh_impact(0.34, wet=1.0), 1.00, outdir)
    save("hit_flesh_alt", flesh_impact(0.30, wet=0.8), 0.95, outdir)
    save("embed_stone", embed_stone(0.85), 1.00, outdir)
    save("embed_wood", embed_wood(0.70), 0.95, outdir)
    save("stagger", stagger_hit(0.5), 0.90, outdir)

    # --- the Leviathan recall pair
    save("recall_whistle", recall_whistle(1.10), 0.80, outdir)
    save("catch_metal", catch_metal(1.50), 1.00, outdir)

    # --- voice
    save("grunt_1", grunt(0.38, 118, 0.72, 0.30, 0.0), 0.80, outdir)
    save("grunt_2", grunt(0.33, 132, 0.66, 0.36, 40.0), 0.80, outdir)
    save("grunt_3", grunt(0.44, 104, 0.78, 0.26, -35.0), 0.80, outdir)
    save("hurt_player", grunt(0.46, 142, 0.60, 0.44, 70.0), 0.90, outdir)
    save("roar_draugr", draugr_roar(1.25), 0.92, outdir)
    save("roar_draugr_alt", draugr_roar(0.95), 0.88, outdir)
    save("death_draugr", draugr_roar(1.45), 0.85, outdir)

    # --- locomotion / misc
    save("step_1", footstep(0.26, 1.00, 2400), 0.55, outdir)
    save("step_2", footstep(0.24, 1.08, 2900), 0.55, outdir)
    save("step_3", footstep(0.28, 0.93, 2100), 0.55, outdir)
    save("dodge", dodge_whoosh(0.34), 0.70, outdir)
    save("ui_click", ui_click(0.12), 0.60, outdir)

    total = sum(os.path.getsize(os.path.join(outdir, f))
                for f in os.listdir(outdir) if f.endswith(".wav"))
    print(f"Done. {len(os.listdir(outdir))} files, {total/1024:.0f}KB total")


if __name__ == "__main__":
    main()
