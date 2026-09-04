#!/usr/bin/env python3
"""Render the original 32-second Neon Overdrive promo score.

Night City Link is synthesized entirely from oscillators and deterministically
seeded noise.  It uses no samples or third-party recordings and requires only
the Python standard library.
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import wave
from array import array
from pathlib import Path


SAMPLE_RATE = 48_000
DURATION = 32.0
FRAME_COUNT = int(SAMPLE_RATE * DURATION)
BPM = 120.0
BEAT = 60.0 / BPM
BAR = 4.0 * BEAT
SEED = 0x4E454F4E  # "NEON"


def midi_hz(note: int) -> float:
    return 440.0 * (2.0 ** ((note - 69) / 12.0))


def stereo_gains(pan: float) -> tuple[float, float]:
    """Return constant-power gains for a pan value in [-1, 1]."""
    angle = (max(-1.0, min(1.0, pan)) + 1.0) * math.pi / 4.0
    return math.cos(angle), math.sin(angle)


def adsr(
    elapsed: float,
    gate: float,
    attack: float,
    decay: float,
    sustain: float,
    release: float,
) -> float:
    if elapsed < 0.0:
        return 0.0
    if attack > 0.0 and elapsed < attack:
        return elapsed / attack
    if decay > 0.0 and elapsed < attack + decay:
        return 1.0 - (1.0 - sustain) * ((elapsed - attack) / decay)
    if elapsed < gate:
        return sustain
    if release > 0.0 and elapsed < gate + release:
        tail = 1.0 - ((elapsed - gate) / release)
        return sustain * tail * tail
    return 0.0


def saw(phase: float) -> float:
    return 2.0 * phase - 1.0


def triangle(phase: float) -> float:
    return 1.0 - 4.0 * abs(phase - 0.5)


class Score:
    def __init__(self) -> None:
        self.left = array("f", [0.0]) * FRAME_COUNT
        self.right = array("f", [0.0]) * FRAME_COUNT
        self.rng = random.Random(SEED)

    @staticmethod
    def frame(seconds: float) -> int:
        return max(0, min(FRAME_COUNT, int(round(seconds * SAMPLE_RATE))))

    @staticmethod
    def duck(seconds: float, amount: float = 1.0) -> float:
        """Synthetic sidechain envelope for the main four-on-the-floor section."""
        if seconds < 4.0 or seconds >= 30.0:
            return 1.0
        beat_phase = seconds % BEAT
        if beat_phase >= 0.19:
            return 1.0
        recovered = (beat_phase / 0.19) ** 0.62
        return 1.0 - amount * 0.48 * (1.0 - recovered)

    def add_pad_note(
        self,
        start: float,
        gate: float,
        midi: int,
        amplitude: float,
        pan: float,
        cutoff: float,
    ) -> None:
        release = 0.42
        begin = self.frame(start)
        end = self.frame(min(DURATION, start + gate + release))
        if end <= begin:
            return

        frequency = midi_hz(midi)
        increment_a = frequency * (2.0 ** (-6.0 / 1200.0)) / SAMPLE_RATE
        increment_b = frequency * (2.0 ** (6.0 / 1200.0)) / SAMPLE_RATE
        increment_tri = frequency * 0.5 / SAMPLE_RATE
        phase_a = ((midi * 0.173) + start * 0.031) % 1.0
        phase_b = ((midi * 0.317) + start * 0.047) % 1.0
        phase_tri = ((midi * 0.113) + start * 0.019) % 1.0
        alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / SAMPLE_RATE)
        filtered = 0.0
        gain_l, gain_r = stereo_gains(pan)

        for index in range(begin, end):
            elapsed = (index - begin) / SAMPLE_RATE
            phase_a = (phase_a + increment_a) % 1.0
            phase_b = (phase_b + increment_b) % 1.0
            phase_tri = (phase_tri + increment_tri) % 1.0
            raw = 0.38 * saw(phase_a) + 0.38 * saw(phase_b) + 0.24 * triangle(phase_tri)
            filtered += alpha * (raw - filtered)
            envelope = adsr(elapsed, gate, 0.065, 0.24, 0.72, release)
            value = filtered * envelope * amplitude * self.duck(index / SAMPLE_RATE, 0.70)
            self.left[index] += value * gain_l
            self.right[index] += value * gain_r

    def add_bass_note(self, start: float, midi: int, amplitude: float = 0.22) -> None:
        gate = 0.185
        release = 0.065
        begin = self.frame(start)
        end = self.frame(min(DURATION, start + gate + release))
        frequency = midi_hz(midi)
        increment = frequency / SAMPLE_RATE
        phase = (midi * 0.097 + start * 0.013) % 1.0
        low = 0.0
        alpha = 1.0 - math.exp(-2.0 * math.pi * 720.0 / SAMPLE_RATE)

        for index in range(begin, end):
            elapsed = (index - begin) / SAMPLE_RATE
            phase = (phase + increment) % 1.0
            raw = 0.72 * math.sin(2.0 * math.pi * phase) + 0.28 * saw(phase)
            low += alpha * (raw - low)
            envelope = adsr(elapsed, gate, 0.004, 0.045, 0.64, release)
            value = low * envelope * amplitude * self.duck(index / SAMPLE_RATE, 0.36)
            self.left[index] += value * 0.707
            self.right[index] += value * 0.707

    def add_arp_note(
        self,
        start: float,
        midi: int,
        amplitude: float,
        pan: float,
    ) -> None:
        gate = 0.092
        release = 0.085
        begin = self.frame(start)
        end = self.frame(min(DURATION, start + gate + release))
        frequency = midi_hz(midi)
        increment = frequency / SAMPLE_RATE
        phase = (midi * 0.137 + start * 0.071) % 1.0
        gain_l, gain_r = stereo_gains(pan)
        echo_l, echo_r = stereo_gains(-pan)
        delay_one = self.frame(0.375)
        delay_two = self.frame(0.750)

        for index in range(begin, end):
            elapsed = (index - begin) / SAMPLE_RATE
            phase = (phase + increment) % 1.0
            pulse = 1.0 if phase < 0.25 else -1.0
            raw = 0.58 * pulse + 0.42 * triangle(phase)
            envelope = adsr(elapsed, gate, 0.003, 0.028, 0.40, release)
            value = raw * envelope * amplitude * self.duck(index / SAMPLE_RATE, 0.58)
            self.left[index] += value * gain_l
            self.right[index] += value * gain_r

            delayed = index + delay_one
            if delayed < FRAME_COUNT:
                self.left[delayed] += value * echo_l * 0.27
                self.right[delayed] += value * echo_r * 0.27
            delayed = index + delay_two
            if delayed < FRAME_COUNT:
                self.left[delayed] += value * gain_l * 0.11
                self.right[delayed] += value * gain_r * 0.11

    def add_lead_note(
        self,
        start: float,
        beats: float,
        midi: int,
        amplitude: float = 0.105,
        pan: float = 0.0,
    ) -> None:
        gate = max(0.05, beats * BEAT * 0.84)
        release = 0.17
        begin = self.frame(start)
        end = self.frame(min(DURATION, start + gate + release))
        frequency = midi_hz(midi)
        phase_a = (midi * 0.193) % 1.0
        phase_b = (midi * 0.271) % 1.0
        filtered = 0.0
        alpha = 1.0 - math.exp(-2.0 * math.pi * 4_600.0 / SAMPLE_RATE)
        gain_l, gain_r = stereo_gains(pan)
        echo_l, echo_r = stereo_gains(-0.65 if pan >= 0.0 else 0.65)
        echo_delay = self.frame(0.375)

        for index in range(begin, end):
            elapsed = (index - begin) / SAMPLE_RATE
            vibrato = 1.0 + 0.0021 * math.sin(2.0 * math.pi * 5.15 * elapsed)
            phase_a = (phase_a + frequency * vibrato * (2.0 ** (-4.0 / 1200.0)) / SAMPLE_RATE) % 1.0
            phase_b = (phase_b + frequency * vibrato * (2.0 ** (4.0 / 1200.0)) / SAMPLE_RATE) % 1.0
            pulse_a = 1.0 if phase_a < 0.38 else -1.0
            raw = 0.48 * pulse_a + 0.30 * triangle(phase_b) + 0.22 * math.sin(2.0 * math.pi * phase_a)
            filtered += alpha * (raw - filtered)
            envelope = adsr(elapsed, gate, 0.012, 0.075, 0.73, release)
            value = filtered * envelope * amplitude * self.duck(index / SAMPLE_RATE, 0.40)
            self.left[index] += value * gain_l
            self.right[index] += value * gain_r

            delayed = index + echo_delay
            if delayed < FRAME_COUNT:
                self.left[delayed] += value * echo_l * 0.16
                self.right[delayed] += value * echo_r * 0.16

    def add_kick(self, start: float, amplitude: float = 0.62) -> None:
        duration = 0.285
        begin = self.frame(start)
        end = self.frame(min(DURATION, start + duration))
        phase = 0.0

        for index in range(begin, end):
            elapsed = (index - begin) / SAMPLE_RATE
            frequency = 48.0 + 118.0 * math.exp(-elapsed * 25.0)
            phase = (phase + frequency / SAMPLE_RATE) % 1.0
            body = math.sin(2.0 * math.pi * phase) * math.exp(-elapsed * 16.0)
            click = 0.0
            if elapsed < 0.008:
                click = self.rng.uniform(-1.0, 1.0) * ((0.008 - elapsed) / 0.008)
            value = amplitude * (0.94 * body + 0.06 * click)
            self.left[index] += value * 0.707
            self.right[index] += value * 0.707

    def add_snare(self, start: float, amplitude: float = 0.28) -> None:
        duration = 0.235
        begin = self.frame(start)
        end = self.frame(min(DURATION, start + duration))
        low = 0.0
        hp_alpha = 1.0 - math.exp(-2.0 * math.pi * 1_750.0 / SAMPLE_RATE)

        for index in range(begin, end):
            elapsed = (index - begin) / SAMPLE_RATE
            noise = self.rng.uniform(-1.0, 1.0)
            low += hp_alpha * (noise - low)
            high = noise - low
            burst = math.exp(-elapsed * 15.5)
            if elapsed >= 0.018:
                burst += 0.42 * math.exp(-(elapsed - 0.018) * 42.0)
            if elapsed >= 0.036:
                burst += 0.27 * math.exp(-(elapsed - 0.036) * 48.0)
            tone = math.sin(2.0 * math.pi * 184.0 * elapsed) * math.exp(-elapsed * 22.0)
            value = amplitude * (0.72 * high * burst + 0.28 * tone)
            self.left[index] += value * 0.69
            self.right[index] += value * 0.73

    def add_hat(self, start: float, amplitude: float = 0.075, opened: bool = False) -> None:
        duration = 0.215 if opened else 0.060
        decay = 13.0 if opened else 54.0
        begin = self.frame(start)
        end = self.frame(min(DURATION, start + duration))
        low = 0.0
        hp_alpha = 1.0 - math.exp(-2.0 * math.pi * 6_800.0 / SAMPLE_RATE)
        pan = -0.28 if int(start / (BEAT / 2.0)) % 2 == 0 else 0.28
        gain_l, gain_r = stereo_gains(pan)

        for index in range(begin, end):
            elapsed = (index - begin) / SAMPLE_RATE
            noise = self.rng.uniform(-1.0, 1.0)
            low += hp_alpha * (noise - low)
            value = (noise - low) * math.exp(-elapsed * decay) * amplitude
            self.left[index] += value * gain_l
            self.right[index] += value * gain_r

    def add_riser(self, end_time: float, duration: float = 0.58, amplitude: float = 0.055) -> None:
        start = max(0.0, end_time - duration)
        begin = self.frame(start)
        end = self.frame(end_time)
        low = 0.0

        for index in range(begin, end):
            position = (index - begin) / max(1, end - begin - 1)
            noise = self.rng.uniform(-1.0, 1.0)
            cutoff = 350.0 + 7_000.0 * position * position
            alpha = 1.0 - math.exp(-2.0 * math.pi * cutoff / SAMPLE_RATE)
            low += alpha * (noise - low)
            envelope = position * position * (1.0 - 0.18 * position)
            pan = -0.75 + 1.5 * position
            gain_l, gain_r = stereo_gains(pan)
            value = low * envelope * amplitude
            self.left[index] += value * gain_l
            self.right[index] += value * gain_r

    def add_impact(self, start: float, amplitude: float = 0.34) -> None:
        duration = 0.78
        begin = self.frame(start)
        end = self.frame(min(DURATION, start + duration))
        phase = 0.0
        slow_noise = 0.0

        for index in range(begin, end):
            elapsed = (index - begin) / SAMPLE_RATE
            frequency = 42.0 + 54.0 * math.exp(-elapsed * 7.0)
            phase = (phase + frequency / SAMPLE_RATE) % 1.0
            noise = self.rng.uniform(-1.0, 1.0)
            slow_noise += 0.15 * (noise - slow_noise)
            sub = math.sin(2.0 * math.pi * phase) * math.exp(-elapsed * 5.2)
            air = (noise - slow_noise) * math.exp(-elapsed * 11.0)
            value = amplitude * (0.78 * sub + 0.22 * air)
            self.left[index] += value * 0.707
            self.right[index] += value * 0.707

    def add_vhs_hiss(self) -> None:
        begin = self.frame(16.0)
        end = self.frame(20.0)
        low = 0.0
        alpha = 1.0 - math.exp(-2.0 * math.pi * 5_000.0 / SAMPLE_RATE)
        for index in range(begin, end):
            elapsed = index / SAMPLE_RATE
            noise = self.rng.uniform(-1.0, 1.0)
            low += alpha * (noise - low)
            hiss = (noise - low) * 0.0105
            flutter = 0.94 + 0.035 * math.sin(2.0 * math.pi * 0.72 * elapsed)
            flutter += 0.018 * math.sin(2.0 * math.pi * 5.3 * elapsed)
            if 19.46 <= elapsed < 19.49 or 19.62 <= elapsed < 19.655:
                flutter *= 0.20
            self.left[index] = self.left[index] * flutter + hiss * 0.72
            self.right[index] = self.right[index] * flutter + hiss

    def compose_harmony(self) -> None:
        chords: list[tuple[list[int], list[int] | None, float]] = [
            ([54, 57, 61, 64, 68], None, 980.0),
            ([50, 54, 57, 61, 64], None, 1_650.0),
            ([45, 52, 59, 61, 64], None, 3_350.0),
            ([52, 56, 59, 61], None, 3_700.0),
            ([54, 57, 61, 64, 68], None, 4_250.0),
            ([50, 54, 57, 61, 64], None, 4_500.0),
            ([47, 50, 54, 57, 64], None, 5_200.0),
            ([49, 54, 56, 59], [49, 53, 56, 59], 4_500.0),
            ([54, 57, 61, 64, 68], None, 1_550.0),
            ([50, 54, 57, 61, 64], None, 1_800.0),
            ([45, 52, 59, 61, 64], None, 3_700.0),
            ([52, 56, 59, 61], None, 4_100.0),
            ([47, 50, 54, 57, 64], None, 5_400.0),
            ([50, 54, 57, 61, 64], None, 5_700.0),
            ([49, 54, 56, 59], [49, 53, 56, 59], 5_000.0),
            ([54, 57, 61, 64, 68], None, 2_900.0),
        ]
        arp_pattern = [0, 2, 1, 3, 2, 4, 3, 1, 0, 2, 1, 4, 3, 2, 1, 3]

        for bar_index, (first, second, cutoff) in enumerate(chords):
            bar_start = bar_index * BAR
            sections = [(bar_start, 2.02, first)]
            if second is not None:
                sections = [(bar_start, 1.02, first), (bar_start + 1.0, 1.02, second)]
            for section_start, section_gate, notes in sections:
                per_note_amp = 0.041 if bar_index < 2 else 0.047
                if 8 <= bar_index <= 9:
                    per_note_amp = 0.039
                if 12 <= bar_index <= 14:
                    per_note_amp = 0.051
                if bar_index == 15:
                    per_note_amp = 0.057
                for note_index, note in enumerate(notes):
                    pan = -0.58 + (1.16 * note_index / max(1, len(notes) - 1))
                    self.add_pad_note(section_start, section_gate, note, per_note_amp, pan, cutoff)

            if bar_index == 15:
                continue
            chord_for_step = first
            for step in range(16):
                if bar_index == 0 and step % 2:
                    continue
                if second is not None and step >= 8:
                    chord_for_step = second
                note = chord_for_step[arp_pattern[step] % len(chord_for_step)] + 12
                arp_amp = 0.026 if bar_index == 0 else 0.038
                if 2 <= bar_index <= 5:
                    arp_amp = 0.048
                if 6 <= bar_index <= 7:
                    arp_amp = 0.062
                if 8 <= bar_index <= 9:
                    arp_amp = 0.034
                if 10 <= bar_index <= 11:
                    arp_amp = 0.052
                if 12 <= bar_index <= 14:
                    arp_amp = 0.067
                pan = -0.58 if step % 2 == 0 else 0.58
                self.add_arp_note(bar_start + step * (BEAT / 4.0), note, arp_amp, pan)

    def compose_rhythm(self) -> None:
        roots = [42, 38, 45, 40, 42, 38, 35, 37, 42, 38, 45, 40, 35, 38, 37, 42]
        bass_steps = [0, 0, 12, 0, 7, 0, 12, 7]

        self.add_kick(0.04, 0.29)
        self.add_kick(1.04, 0.25)
        self.add_kick(2.02, 0.34)
        self.add_kick(3.02, 0.39)
        for tick in (3.25, 3.50, 3.75):
            self.add_hat(tick, 0.045)

        for bar_index in range(2, 15):
            bar_start = bar_index * BAR
            for beat_index in range(4):
                kick_amp = 0.67 if beat_index == 0 else 0.58
                if 8 <= bar_index <= 9:
                    kick_amp *= 0.84
                if 12 <= bar_index <= 14:
                    kick_amp *= 1.08
                self.add_kick(bar_start + beat_index * BEAT, kick_amp)
            self.add_snare(bar_start + BEAT, 0.29 if bar_index < 12 else 0.32)
            self.add_snare(bar_start + 3.0 * BEAT, 0.30 if bar_index < 12 else 0.34)
            for eighth in range(8):
                opened = eighth == 7 and bar_index not in (8, 9)
                hat_amp = 0.072 if eighth % 2 == 0 else 0.058
                if 6 <= bar_index <= 7 or 12 <= bar_index <= 14:
                    hat_amp *= 1.22
                self.add_hat(bar_start + eighth * (BEAT / 2.0), hat_amp, opened)

            for eighth, offset in enumerate(bass_steps):
                bass_amp = 0.205
                if 8 <= bar_index <= 9:
                    bass_amp = 0.178
                if 12 <= bar_index <= 14:
                    bass_amp = 0.228
                self.add_bass_note(bar_start + eighth * (BEAT / 2.0), roots[bar_index] + offset, bass_amp)

        for hit, level in ((29.56, 0.16), (29.72, 0.20), (29.84, 0.24)):
            self.add_snare(hit, level)
        self.add_impact(20.0, 0.31)
        self.add_impact(24.0, 0.38)
        self.add_impact(30.0, 0.43)
        self.add_bass_note(30.0, roots[15], 0.30)

    def compose_lead(self) -> None:
        motif = [
            (8.0, 1.0, 73),
            (8.5, 0.5, 76),
            (8.75, 0.5, 78),
            (9.0, 1.0, 81),
            (9.5, 1.0, 80),
            (10.0, 1.0, 78),
            (10.5, 1.0, 76),
            (11.0, 2.0, 73),
            (12.0, 0.5, 71),
            (12.25, 0.5, 73),
            (12.5, 1.0, 74),
            (13.0, 1.0, 78),
            (13.5, 1.0, 76),
            (14.0, 1.0, 73),
            (14.5, 0.5, 71),
            (14.75, 0.5, 68),
            (15.0, 2.0, 73),
        ]
        for event_index, (start, beats, note) in enumerate(motif):
            pan = -0.16 if event_index % 2 == 0 else 0.16
            self.add_lead_note(start, beats, note, 0.104, pan)

        reprise = [
            (24.0, 1.0, 73),
            (24.5, 0.5, 76),
            (24.75, 0.5, 78),
            (25.0, 1.0, 81),
            (25.5, 1.0, 80),
            (26.0, 1.0, 78),
            (26.5, 1.0, 76),
            (27.0, 2.0, 73),
            (28.0, 0.5, 68),
            (28.25, 0.5, 71),
            (28.5, 1.0, 73),
            (29.0, 1.0, 77),
            (29.5, 1.0, 80),
        ]
        for event_index, (start, beats, note) in enumerate(reprise):
            pan = -0.22 if event_index % 2 == 0 else 0.22
            self.add_lead_note(start, beats, note, 0.122, pan)
            if start < 28.0:
                self.add_lead_note(start, beats, note - 5, 0.037, -pan)

    def compose_transitions(self) -> None:
        for transition in (4.0, 8.0, 12.0, 16.0, 20.0, 24.0, 28.0, 30.0):
            strength = 0.071 if transition in (20.0, 24.0, 30.0) else 0.050
            self.add_riser(transition, 0.60, strength)

    def master_in_place(self) -> float:
        """Remove DC, apply a gentle fade and soft clip; return pre-scale peak."""
        dc_l = 0.0
        dc_r = 0.0
        previous_l = 0.0
        previous_r = 0.0
        peak = 0.0
        dc_coefficient = 0.995
        fade_in = self.frame(0.035)
        fade_out_start = self.frame(31.32)

        for index in range(FRAME_COUNT):
            source_l = self.left[index]
            source_r = self.right[index]
            filtered_l = source_l - previous_l + dc_coefficient * dc_l
            filtered_r = source_r - previous_r + dc_coefficient * dc_r
            previous_l = source_l
            previous_r = source_r
            dc_l = filtered_l
            dc_r = filtered_r

            fade = 1.0
            if index < fade_in:
                fade = index / max(1, fade_in)
            elif index >= fade_out_start:
                fade = max(0.0, (FRAME_COUNT - 1 - index) / max(1, FRAME_COUNT - fade_out_start))

            output_l = math.tanh(filtered_l * 1.10) * fade
            output_r = math.tanh(filtered_r * 1.10) * fade
            self.left[index] = output_l
            self.right[index] = output_r
            peak = max(peak, abs(output_l), abs(output_r))

        scale = 0.91 / peak if peak > 0.91 else 1.0
        if scale != 1.0:
            for index in range(FRAME_COUNT):
                self.left[index] *= scale
                self.right[index] *= scale
        return peak

    def render(self) -> float:
        self.compose_harmony()
        self.compose_rhythm()
        self.compose_lead()
        self.compose_transitions()
        self.add_vhs_hiss()
        return self.master_in_place()

    def write_wav(self, output: Path) -> None:
        output.parent.mkdir(parents=True, exist_ok=True)
        chunk_frames = 8_192
        with wave.open(str(output), "wb") as wav:
            wav.setnchannels(2)
            wav.setsampwidth(2)
            wav.setframerate(SAMPLE_RATE)
            for start in range(0, FRAME_COUNT, chunk_frames):
                end = min(FRAME_COUNT, start + chunk_frames)
                payload = bytearray((end - start) * 4)
                offset = 0
                for index in range(start, end):
                    left = max(-1.0, min(1.0, self.left[index]))
                    right = max(-1.0, min(1.0, self.right[index]))
                    struct.pack_into("<hh", payload, offset, int(round(left * 32_767)), int(round(right * 32_767)))
                    offset += 4
                wav.writeframesraw(payload)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=Path("promo/work/night-city-link-raw.wav"),
        help="destination WAV (default: %(default)s)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    score = Score()
    peak = score.render()
    score.write_wav(args.output)
    print(f"rendered={args.output}")
    print(f"sample_rate={SAMPLE_RATE}")
    print(f"frames={FRAME_COUNT}")
    print(f"duration={DURATION:.3f}")
    print(f"seed=0x{SEED:08X}")
    print(f"pre_scale_peak={peak:.6f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
