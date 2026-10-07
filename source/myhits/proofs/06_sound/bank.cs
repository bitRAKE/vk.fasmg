// The sound bank a second time: each recipe of tables.inc synthesized in
// double precision, with the sweep's phase summed finely rather than by the
// device's 32 intervals, and the curves from curves.cs rather than
// ease.slang. Proof 06 holds what the device rendered to this, and writes
// the device's bank as a WAV so it can be listened to.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;

namespace Myhits {
    public static class Bank {
        const int Rate = 48000;
        static readonly string[] Waves = { "SINE", "SQUARE", "SAW", "TRIANGLE" };
        class Tone { public string Name; public int Samples, Wave, PitchCurve, FallCurve; public double From, To, Attack, Noise, Gain; }

        static List<Tone> Read(string tables) {
            List<Tone> tones = new List<Tone>();
            foreach (Match line in Regex.Matches(File.ReadAllText(tables), @"(?m)^\s*tone\s+(\w+),([^;\r\n]+)")) {
                string[] part = line.Groups[2].Value.Split(',');
                Tone tone = new Tone();
                tone.Name = line.Groups[1].Value;
                tone.Samples = (int)(double.Parse(part[0], CultureInfo.InvariantCulture) * Rate + 0.5);
                tone.Wave = Array.IndexOf(Waves, part[1].Trim());
                tone.From = double.Parse(part[2], CultureInfo.InvariantCulture);
                tone.To = double.Parse(part[3], CultureInfo.InvariantCulture);
                tone.PitchCurve = Array.IndexOf(Curves.Names, part[4].Trim());
                tone.Attack = double.Parse(part[5], CultureInfo.InvariantCulture);
                tone.FallCurve = Array.IndexOf(Curves.Names, part[6].Trim());
                tone.Noise = double.Parse(part[7], CultureInfo.InvariantCulture);
                tone.Gain = double.Parse(part[8], CultureInfo.InvariantCulture);
                if (tone.Wave < 0 || tone.PitchCurve < 0 || tone.FallCurve < 0) throw new InvalidDataException("Not a tone this reads: " + line.Value);
                tones.Add(tone);
            }
            return tones;
        }
        static uint Hash(uint x) { x ^= x >> 16; x *= 0x7feb352dU; x ^= x >> 15; x *= 0x846ca68bU; x ^= x >> 16; return x; }

        // How many of the device's samples differ from these by more than a
        // five-hundredth of full scale, of how many, and the worst sound. A
        // square or a saw has edges, and a sample that falls on one may land
        // either side in single precision: those few are allowed for.
        public static string Compare(string dump, string tables) {
            List<Tone> tones = Read(tables);
            byte[] bytes = File.ReadAllBytes(dump);
            int total = 0; foreach (Tone tone in tones) total += tone.Samples;
            if (bytes.Length != total * 4) throw new InvalidDataException("The device's bank is " + bytes.Length / 4 + " samples; the recipes make " + total);
            int first = 0, apart = 0, worstCount = -1; string worst = "none"; double rms = 0;
            for (int sound = 0; sound < tones.Count; ++sound) {
                Tone tone = tones[sound];
                double seconds = (double)tone.Samples / Rate, area = 0, before = Curves.Ease(tone.PitchCurve, 0);
                int here = 0;
                for (int index = 0; index < tone.Samples; ++index) {
                    double along = (double)index / tone.Samples;
                    if (index > 0) {
                        // The area under the curve so far: sixteen trapezoids a sample.
                        double start = (double)(index - 1) / tone.Samples;
                        for (int k = 1; k <= 16; ++k) {
                            double now = Curves.Ease(tone.PitchCurve, start + (along - start) * k / 16);
                            area += (before + now) * 0.5 * (along - start) / 16;
                            before = now;
                        }
                    }
                    double cycles = seconds * (tone.From * along + (tone.To - tone.From) * area);
                    double part = cycles - Math.Floor(cycles), wave;
                    switch (tone.Wave) {
                        case 1: wave = part < 0.5 ? 1 : -1; break;
                        case 2: wave = 2 * part - 1; break;
                        case 3: wave = 1 - 4 * Math.Abs(part - 0.5); break;
                        default: wave = Math.Sin(part * 2 * Math.PI); break;
                    }
                    double level = Math.Min(along * seconds / Math.Max(tone.Attack, 1e-6), 1.0) * (1 - Curves.Ease(tone.FallCurve, along));
                    double hiss = (Hash((uint)index ^ ((uint)sound * 0x9e3779b9U + 0x85ebca6bU)) >> 8) * (1.0 / 16777216.0) * 2 - 1;
                    double mine = tone.Gain * level * (wave + (hiss - wave) * tone.Noise);
                    double off = BitConverter.ToSingle(bytes, (first + index) * 4) - mine;
                    rms += off * off;
                    if (Math.Abs(off) > 0.002 || double.IsNaN(off)) ++here;
                }
                if (here > worstCount) { worstCount = here; worst = tone.Name; }
                apart += here; first += tone.Samples;
            }
            return string.Format(CultureInfo.InvariantCulture, "{0} {1} {2} {3:e2} {4}", apart, total, worst, Math.Sqrt(rms / total), tones.Count);
        }

        // The music the same way: each stem of tables.inc, its thirty-two
        // notes struck one after another, against what the device rendered
        // (the game's dump of the bank after the sounds). Returns how many
        // samples differ by more than the allowance, of how many, and how
        // many stems there are.
        public static string CompareMusic(string dump, string tables) {
            const int Step = 6000, Steps = 32, Loop = Step * Steps;
            string text = File.ReadAllText(tables);
            MatchCollection stems = Regex.Matches(text, @"(?m)^\s*stem\s+(\w+),(\w+),([\d.]+),(\w+)\s*\r?\n\s*notes\s+([^\r\n;]+)");
            byte[] bytes = File.ReadAllBytes(dump);
            if (bytes.Length != stems.Count * Loop * 4) throw new InvalidDataException("The device's music is " + bytes.Length / 4 + " samples; " + stems.Count + " stems make " + stems.Count * Loop);
            int apart = 0;
            for (int which = 0; which < stems.Count; ++which) {
                string shape = stems[which].Groups[2].Value;
                double gain = double.Parse(stems[which].Groups[3].Value, CultureInfo.InvariantCulture);
                int fall = Array.IndexOf(Curves.Names, stems[which].Groups[4].Value);
                string[] written = stems[which].Groups[5].Value.Split(',');
                if (written.Length != Steps || fall < 0) throw new InvalidDataException("Not a stem this reads: " + stems[which].Groups[1].Value);
                for (int index = 0; index < Loop; ++index) {
                    int note = int.Parse(written[index / Step].Trim()), within = index % Step;
                    double mine = 0;
                    if (note != 0) {
                        double seconds = within / (double)Rate, along = within / (double)Step;
                        double level = Math.Min(seconds / 0.004, 1.0) * (1 - Curves.Ease(fall, along));
                        if (shape == "DRUM") {
                            if (note == 1) mine = gain * level * Math.Sin(2 * Math.PI * (48.0 * seconds + 2.2 * (1 - Math.Pow(2, -seconds * 60))));
                            else {
                                double hiss = (Hash((uint)index * 2654435761U + (uint)which * 977U) >> 8) * (1.0 / 16777216.0) * 2 - 1;
                                mine = gain * level * hiss * (note == 2 ? 0.9 : 0.4 * Math.Max(0.0, Math.Min(1.0, 1 - along * 5)));
                            }
                        } else {
                            double cycles = 440.0 * Math.Pow(2, (note - 69) / 12.0) * seconds, part = cycles - Math.Floor(cycles);
                            double wave = shape == "SQUARE" ? (part < 0.5 ? 1 : -1) : shape == "SAW" ? 2 * part - 1 : shape == "TRIANGLE" ? 1 - 4 * Math.Abs(part - 0.5) : Math.Sin(part * 2 * Math.PI);
                            mine = gain * level * wave;
                        }
                    }
                    double off = BitConverter.ToSingle(bytes, (which * Loop + index) * 4) - mine;
                    if (Math.Abs(off) > 0.002 || double.IsNaN(off)) ++apart;
                }
            }
            return string.Format(CultureInfo.InvariantCulture, "{0} {1} {2}", apart, stems.Count * Loop, stems.Count);
        }

        // The stems together, as they sound with everything happening: for a player.
        public static void WriteMix(string dump, string wav, int stems) {
            byte[] bytes = File.ReadAllBytes(dump);
            int loop = bytes.Length / 4 / stems;
            byte[] mixed = new byte[loop * 2 * 4];
            for (int index = 0; index < loop * 2; ++index) {
                float sum = 0;
                for (int which = 0; which < stems; ++which) sum += BitConverter.ToSingle(bytes, (which * loop + index % loop) * 4);
                Buffer.BlockCopy(BitConverter.GetBytes(sum * 0.6f), 0, mixed, index * 4, 4);
            }
            string raw = wav + ".raw";
            File.WriteAllBytes(raw, mixed);
            WriteWav(raw, wav);
            File.Delete(raw);
        }

        // The device's bank as it stands, for a player: 32-bit float, mono.
        public static void WriteWav(string dump, string wav) {
            byte[] samples = File.ReadAllBytes(dump);
            using (BinaryWriter writer = new BinaryWriter(File.Create(wav))) {
                writer.Write(new char[] { 'R', 'I', 'F', 'F' }); writer.Write(36 + samples.Length);
                writer.Write(new char[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' }); writer.Write(16);
                writer.Write((short)3); writer.Write((short)1); writer.Write(Rate); writer.Write(Rate * 4); writer.Write((short)4); writer.Write((short)32);
                writer.Write(new char[] { 'd', 'a', 't', 'a' }); writer.Write(samples.Length); writer.Write(samples);
            }
        }
    }
}
