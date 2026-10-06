// The easing curves a second time, written the long way: each of the thirty
// as easings.net gives it, one formula a curve, in double precision. Proof 04
// holds what the device sampled (build\myhits_motion.curves.bin) to these.
// ease.slang builds the same curves as families, so the two share no code
// and no structure.
using System;
using System.IO;

namespace Myhits {
    public static class Curves {
        const double C1 = 1.70158, C2 = C1 * 1.525, C3 = C1 + 1, C4 = 2 * Math.PI / 3, C5 = 2 * Math.PI / 4.5;
        static double OutBounce(double x) {
            const double n = 7.5625, d = 2.75;
            if (x < 1 / d) return n * x * x;
            if (x < 2 / d) return n * (x -= 1.5 / d) * x + 0.75;
            if (x < 2.5 / d) return n * (x -= 2.25 / d) * x + 0.9375;
            return n * (x -= 2.625 / d) * x + 0.984375;
        }
        public static readonly string[] Names = { "LINEAR",
            "IN_QUAD", "OUT_QUAD", "INOUT_QUAD", "IN_CUBIC", "OUT_CUBIC", "INOUT_CUBIC", "IN_QUART", "OUT_QUART", "INOUT_QUART", "IN_QUINT", "OUT_QUINT", "INOUT_QUINT",
            "IN_SINE", "OUT_SINE", "INOUT_SINE", "IN_EXPO", "OUT_EXPO", "INOUT_EXPO", "IN_CIRC", "OUT_CIRC", "INOUT_CIRC",
            "IN_BACK", "OUT_BACK", "INOUT_BACK", "IN_ELASTIC", "OUT_ELASTIC", "INOUT_ELASTIC", "IN_BOUNCE", "OUT_BOUNCE", "INOUT_BOUNCE" };
        public static double Ease(int curve, double x) {
            switch (curve) {
                case 0: return x;
                case 1: return x * x;
                case 2: return 1 - (1 - x) * (1 - x);
                case 3: return x < 0.5 ? 2 * x * x : 1 - Math.Pow(-2 * x + 2, 2) / 2;
                case 4: return x * x * x;
                case 5: return 1 - Math.Pow(1 - x, 3);
                case 6: return x < 0.5 ? 4 * x * x * x : 1 - Math.Pow(-2 * x + 2, 3) / 2;
                case 7: return x * x * x * x;
                case 8: return 1 - Math.Pow(1 - x, 4);
                case 9: return x < 0.5 ? 8 * x * x * x * x : 1 - Math.Pow(-2 * x + 2, 4) / 2;
                case 10: return x * x * x * x * x;
                case 11: return 1 - Math.Pow(1 - x, 5);
                case 12: return x < 0.5 ? 16 * x * x * x * x * x : 1 - Math.Pow(-2 * x + 2, 5) / 2;
                case 13: return 1 - Math.Cos(x * Math.PI / 2);
                case 14: return Math.Sin(x * Math.PI / 2);
                case 15: return -(Math.Cos(Math.PI * x) - 1) / 2;
                case 16: return x == 0 ? 0 : Math.Pow(2, 10 * x - 10);
                case 17: return x == 1 ? 1 : 1 - Math.Pow(2, -10 * x);
                case 18: return x == 0 ? 0 : x == 1 ? 1 : x < 0.5 ? Math.Pow(2, 20 * x - 10) / 2 : (2 - Math.Pow(2, -20 * x + 10)) / 2;
                case 19: return 1 - Math.Sqrt(1 - x * x);
                case 20: return Math.Sqrt(1 - (x - 1) * (x - 1));
                case 21: return x < 0.5 ? (1 - Math.Sqrt(1 - 4 * x * x)) / 2 : (Math.Sqrt(1 - Math.Pow(-2 * x + 2, 2)) + 1) / 2;
                case 22: return C3 * x * x * x - C1 * x * x;
                case 23: return 1 + C3 * Math.Pow(x - 1, 3) + C1 * Math.Pow(x - 1, 2);
                case 24: return x < 0.5 ? Math.Pow(2 * x, 2) * ((C2 + 1) * 2 * x - C2) / 2 : (Math.Pow(2 * x - 2, 2) * ((C2 + 1) * (x * 2 - 2) + C2) + 2) / 2;
                case 25: return x == 0 ? 0 : x == 1 ? 1 : -Math.Pow(2, 10 * x - 10) * Math.Sin((x * 10 - 10.75) * C4);
                case 26: return x == 0 ? 0 : x == 1 ? 1 : Math.Pow(2, -10 * x) * Math.Sin((x * 10 - 0.75) * C4) + 1;
                case 27: return x == 0 ? 0 : x == 1 ? 1 : x < 0.5 ? -(Math.Pow(2, 20 * x - 10) * Math.Sin((20 * x - 11.125) * C5)) / 2 : Math.Pow(2, -20 * x + 10) * Math.Sin((20 * x - 11.125) * C5) / 2 + 1;
                case 28: return 1 - OutBounce(1 - x);
                case 29: return OutBounce(x);
                default: return x < 0.5 ? (1 - OutBounce(1 - 2 * x)) / 2 : (1 + OutBounce(2 * x - 1)) / 2;
            }
        }
        // The largest difference between the device's samples and these, and where.
        public static string Compare(string dump, int samples) {
            byte[] bytes = File.ReadAllBytes(dump);
            if (bytes.Length != Names.Length * samples * 4) throw new InvalidDataException("The device's curves are not " + Names.Length + " by " + samples + " samples");
            double worst = 0; int at = 0;
            for (int i = 0; i < Names.Length * samples; ++i) {
                double apart = Math.Abs(BitConverter.ToSingle(bytes, i * 4) - Ease(i / samples, (i % samples) / (double)(samples - 1)));
                if (apart > worst || double.IsNaN(apart)) { worst = apart; at = i; }
            }
            return string.Format(System.Globalization.CultureInfo.InvariantCulture, "{0:e2} {1} {2}", worst, Names[at / samples], at % samples);
        }
    }
}
