// The run as it sounded. The scripted run keeps what every frame asked of the
// voices and of the music; this plays that back into a file, with the bank
// the device rendered, the way audio.inc plays it: sixteen voices taken in
// turn, a sound's level by how many asked for it, its place between the
// speakers by where it happened, its pitch a little off and a different
// little each time, and the stems coming in and going out with how much is
// happening. So the game can be listened to without playing it.
//
// And it says how loud everything is, for an author who cannot hear it: each
// sound's level and peak, how far it stands from the rest, how often the run
// asked for it; and the whole mix's level, its peak, and how much of it would
// be cut off for being louder than a speaker goes.
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace Myhits {
    public static class Mix {
        const int Voices = 16, Loop = 192000;
        // audio.inc's numbers.
        const float Gain = 0.5f, Bass = 0.5f, Drums = 0.55f, DrumsFrom = 0.08f, DrumsSpan = 0.25f, Lead = 0.5f, LeadFrom = 0.4f, LeadSpan = 0.4f, Ease = 0.05f;

        class Play { public int Sound, Start, End; public float Ratio, Left, Right; }

        static double Decibels(double level) { return level <= 0 ? -200 : 20 * Math.Log10(level); }
        static float Unit(float x) { return x < 0 ? 0 : x > 1 ? 1 : x; }

        // heard: build\myhits_game.heard.bin. sounds, music: the bank's two parts,
        // as floats. tables: tables.inc, for the names and the lengths. Mixes
        // the first `frames` frames to `wav` and writes the table to `report`.
        // Returns what the proof runner holds it to, as name=value words.
        public static string Run(string heard, string sounds, string music, string tables, string wav, string report, int frames) {
            byte[] log = File.ReadAllBytes(heard);
            if (BitConverter.ToUInt32(log, 0) != 0x44524548) throw new InvalidDataException("Not what a run heard: " + heard);
            int logged = BitConverter.ToInt32(log, 4), ticks = BitConverter.ToInt32(log, 8), kinds = BitConverter.ToInt32(log, 12), record = BitConverter.ToInt32(log, 16);
            int tickRate = BitConverter.ToInt32(log, 20), rate = BitConverter.ToInt32(log, 24), count = BitConverter.ToInt32(log, 28);
            const int head = 32;
            if (frames > logged) frames = logged;
            int step = rate * ticks / tickRate;

            // The sounds, by name, where each is in the bank.
            List<string> names = new List<string>();
            List<int> first = new List<int>(), length = new List<int>();
            int place = 0;
            foreach (Match line in Regex.Matches(File.ReadAllText(tables), @"(?m)^\s*tone\s+(\w+),\s*([0-9.]+)")) {
                names.Add(line.Groups[1].Value);
                int samples = (int)(double.Parse(line.Groups[2].Value, CultureInfo.InvariantCulture) * rate + 0.5);
                first.Add(place); length.Add(samples);
                place += samples;
            }
            List<string> stems = new List<string>();
            foreach (Match line in Regex.Matches(File.ReadAllText(tables), @"(?m)^\s*stem\s+(\w+),")) stems.Add(line.Groups[1].Value);
            byte[] raw = File.ReadAllBytes(sounds);
            if (names.Count != count || place * 4 != raw.Length) throw new InvalidDataException("The bank is not the tables': " + names.Count + " sounds of " + place + " samples named, " + count + " of " + raw.Length / 4 + " rendered");
            float[] bank = new float[place];
            Buffer.BlockCopy(raw, 0, bank, 0, raw.Length);
            raw = File.ReadAllBytes(music);
            if (raw.Length != stems.Count * Loop * 4) throw new InvalidDataException("The music is not the tables' stems");
            float[] song = new float[stems.Count * Loop];
            Buffer.BlockCopy(raw, 0, song, 0, raw.Length);

            // Every frame's asking, in the order the voices were given it: the
            // events of a frame are in hand as the next begins.
            int total = (frames + 1) * step + rate * 2;
            List<Play> plays = new List<Play>();
            Play[] voice = new Play[Voices];
            uint seed = 2463534242u;
            int next = 0, asked = 0, askedAll = 0;
            int[] times = new int[count], sum = new int[count];
            float[][] levels = new float[stems.Count][];
            for (int which = 0; which < stems.Count; ++which) levels[which] = new float[frames + 1];
            float[] mixed = new float[stems.Count];
            for (int frame = 0; frame < logged; ++frame) {
                int at = head + frame * record;
                float intensity = BitConverter.ToSingle(log, at + 4);
                for (int sound = 0; sound < count; ++sound) {
                    int many = BitConverter.ToInt32(log, at + 8 + sound * 8), pan = BitConverter.ToInt32(log, at + 12 + sound * 8);
                    if (many == 0) continue;
                    ++askedAll;
                    if (frame >= frames) continue;
                    ++asked; ++times[sound]; sum[sound] += many;
                    float loud = Math.Min((many + 3) * 0.25f, 2f) * Gain;
                    double turn = Unit(((float)pan / many + 960f) / 1920f) * Math.PI / 2;
                    Play play = new Play();
                    play.Sound = sound; play.Start = (frame + 1) * step; play.End = total;
                    play.Left = (float)Math.Cos(turn) * loud; play.Right = (float)Math.Sin(turn) * loud;
                    seed = seed * 1664525u + 1013904223u;
                    play.Ratio = (seed >> 8) * 4.7683716e-9f + 0.96f;
                    // The voice it is given is taken from whatever had it.
                    int which = next++ & (Voices - 1);
                    if (voice[which] != null) voice[which].End = play.Start;
                    voice[which] = play;
                    plays.Add(play);
                }
                if (frame >= frames) continue;
                // The stems move a twentieth of the way to where they should be.
                float[] wanted = { Bass, Unit((intensity - DrumsFrom) / DrumsSpan) * Drums, Unit((intensity - LeadFrom) / LeadSpan) * Lead };
                for (int which = 0; which < stems.Count; ++which) {
                    mixed[which] += ((which < wanted.Length ? wanted[which] : 0) - mixed[which]) * Ease;
                    levels[which][frame + 1] = mixed[which];
                }
            }

            float[] left = new float[total], right = new float[total];
            foreach (Play play in plays) {
                int from = first[play.Sound], samples = length[play.Sound];
                for (int index = play.Start; index < play.End; ++index) {
                    double along = (index - play.Start) * (double)play.Ratio;
                    int whole = (int)along;
                    if (whole >= samples - 1) break;
                    float value = bank[from + whole] + (bank[from + whole + 1] - bank[from + whole]) * (float)(along - whole);
                    left[index] += value * play.Left;
                    right[index] += value * play.Right;
                }
            }
            for (int index = 0; index < total; ++index) {
                int frame = Math.Min(index / step, frames);
                float value = 0;
                for (int which = 0; which < stems.Count; ++which) value += song[which * Loop + index % Loop] * levels[which][frame];
                left[index] += value;
                right[index] += value;
            }

            // What it comes to; and the file, as a player will take it.
            double peak = 0, energy = 0;
            int clipped = 0, peakAt = 0;
            using (BinaryWriter writer = new BinaryWriter(File.Create(wav))) {
                writer.Write(new char[] { 'R', 'I', 'F', 'F' }); writer.Write(36 + total * 4);
                writer.Write(new char[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' }); writer.Write(16);
                writer.Write((short)1); writer.Write((short)2); writer.Write(rate); writer.Write(rate * 4); writer.Write((short)4); writer.Write((short)16);
                writer.Write(new char[] { 'd', 'a', 't', 'a' }); writer.Write(total * 4);
                for (int index = 0; index < total; ++index) {
                    foreach (float value in new float[] { left[index], right[index] }) {
                        double size = Math.Abs(value);
                        if (size > peak) { peak = size; peakAt = index; }
                        energy += (double)value * value;
                        if (size > 1) ++clipped;
                        writer.Write((short)Math.Round(Math.Max(-1f, Math.Min(1f, value)) * 32767f));
                    }
                }
            }
            double mixLevel = Math.Sqrt(energy / (total * 2.0));

            // Each sound as it is in the bank, and how far from the middle of them it stands.
            double[] level = new double[count], top = new double[count];
            for (int sound = 0; sound < count; ++sound) {
                double square = 0;
                for (int index = 0; index < length[sound]; ++index) {
                    double value = bank[first[sound] + index];
                    square += value * value;
                    top[sound] = Math.Max(top[sound], Math.Abs(value));
                }
                level[sound] = Decibels(Math.Sqrt(square / length[sound]));
            }
            double[] sorted = (double[])level.Clone();
            Array.Sort(sorted);
            double median = count % 2 == 1 ? sorted[count / 2] : (sorted[count / 2 - 1] + sorted[count / 2]) / 2;
            int furthest = 0;
            for (int sound = 1; sound < count; ++sound) if (Math.Abs(level[sound] - median) > Math.Abs(level[furthest] - median)) furthest = sound;

            StringBuilder text = new StringBuilder();
            text.AppendLine("# The run, as it sounded");
            text.AppendLine();
            text.AppendFormat(CultureInfo.InvariantCulture, "`{0}`: {1:0.0} seconds of the scripted run's first {2} frames, as the game asked for it: {3} sounds on {4} voices, and {5} stems.\n\n",
                Path.GetFileName(wav), total / (double)rate, frames, asked, Voices, stems.Count);
            text.AppendFormat(CultureInfo.InvariantCulture, "The mix's level is {0:0.0} dB and its peak {1:0.0} dB, of all a speaker goes to; the peak is {2:0.00} seconds in. {3} of its {4} samples are louder than a speaker goes, and are cut off.\n\n",
                Decibels(mixLevel), Decibels(peak), peakAt / (double)rate, clipped, total * 2);
            text.AppendLine("| Sound | Seconds | Level, dB | Peak, dB | From the middle of them | Frames that asked | Asked in all |");
            text.AppendLine("| --- | --- | --- | --- | --- | --- | --- |");
            for (int sound = 0; sound < count; ++sound)
                text.AppendFormat(CultureInfo.InvariantCulture, "| {0} | {1:0.00} | {2:0.0} | {3:0.0} | {4:+0.0;-0.0} | {5} | {6} |\n",
                    names[sound], length[sound] / (double)rate, level[sound], Decibels(top[sound]), level[sound] - median, times[sound], sum[sound]);
            text.AppendLine();
            text.AppendLine("A sound's level is of the sound as the device rendered it, whole. A voice plays it at half that, between the speakers, and louder the more asked for it at once, up to twice.");
            text.AppendLine();
            text.AppendLine("| Stem | Level, dB | Peak, dB | Loudest it was let be |");
            text.AppendLine("| --- | --- | --- | --- |");
            for (int which = 0; which < stems.Count; ++which) {
                double square = 0, most = 0, let = 0;
                for (int index = 0; index < Loop; ++index) { double value = song[which * Loop + index]; square += value * value; most = Math.Max(most, Math.Abs(value)); }
                for (int frame = 0; frame <= frames; ++frame) let = Math.Max(let, levels[which][frame]);
                text.AppendFormat(CultureInfo.InvariantCulture, "| {0} | {1:0.0} | {2:0.0} | {3:0.00} |\n", stems[which], Decibels(Math.Sqrt(square / Loop)), Decibels(most), let);
            }
            File.WriteAllText(report, text.ToString());
            return string.Format(CultureInfo.InvariantCulture, "seconds={0:0.0} asked={1} asked_all={2} level={3:0.0} peak={4:0.0} peak_at={5:0.00} clipped={6} samples={7} furthest={8} apart={9:0.0}",
                total / (double)rate, asked, askedAll, Decibels(mixLevel), Decibels(peak), peakAt / (double)rate, clipped, total * 2, names[furthest], level[furthest] - median);
        }
    }
}
