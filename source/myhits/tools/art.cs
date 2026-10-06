// Art for myhits, in two steps.
//
// Cut:  lift one sprite out of a sheet of ideas: find the panel it sits on,
//       remove that panel, keep the sprite, clean its edge for alpha blending,
//       trim, size. Writes a PNG with straight alpha. This is authoring.
// Pack: turn the manifest into what the build embeds: one block of texels for
//       the cut pictures, and the table of every frame, whatever its source.
//
// Plain C# 5: Windows PowerShell compiles this with Add-Type.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace Myhits {
    public static class Art {
        static int[] Read(Bitmap bitmap, Rectangle area) {
            BitmapData data = bitmap.LockBits(area, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            int[] pixels = new int[area.Width * area.Height];
            for (int y = 0; y < area.Height; ++y)
                Marshal.Copy(new IntPtr(data.Scan0.ToInt64() + (long)y * data.Stride), pixels, y * area.Width, area.Width);
            bitmap.UnlockBits(data);
            return pixels;
        }
        static Bitmap Write(int[] pixels, int width, int height) {
            Bitmap bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            BitmapData data = bitmap.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            for (int y = 0; y < height; ++y)
                Marshal.Copy(pixels, y * width, new IntPtr(data.Scan0.ToInt64() + (long)y * data.Stride), width);
            bitmap.UnlockBits(data);
            return bitmap;
        }
        static double Distance(int pixel, double r, double g, double b) {
            double dr = ((pixel >> 16) & 255) - r, dg = ((pixel >> 8) & 255) - g, db = (pixel & 255) - b;
            return Math.Sqrt(dr * dr + dg * dg + db * db);
        }
        static int Clamp(double value) { return value < 0 ? 0 : value > 255 ? 255 : (int)(value + 0.5); }

        // (x, y, width, height) is roughly the sprite's cell in the sheet; it may
        // take in the cell's frame and gutter. `size` is the longer side of the
        // result in texels, or 0 to keep the sheet's own. `glow` is for light
        // rather than matter: nothing is cut away, and alpha is how far a pixel
        // stands out from the panel.
        public static string Cut(string source, int x, int y, int width, int height, int size, bool flip, bool glow, string output) {
            int[] cell;
            using (Bitmap sheet = new Bitmap(source)) {
                Rectangle area = Rectangle.Intersect(new Rectangle(x, y, width, height), new Rectangle(0, 0, sheet.Width, sheet.Height));
                width = area.Width; height = area.Height;
                cell = Read(sheet, area);
            }
            int count = width * height;

            // The panel is the commonest color in the cell.
            Dictionary<int, int> histogram = new Dictionary<int, int>();
            foreach (int pixel in cell) {
                int key = ((pixel >> 19) & 31) << 10 | ((pixel >> 11) & 31) << 5 | ((pixel >> 3) & 31);
                int seen; histogram.TryGetValue(key, out seen); histogram[key] = seen + 1;
            }
            int mode = 0, most = 0;
            foreach (KeyValuePair<int, int> entry in histogram) if (entry.Value > most) { most = entry.Value; mode = entry.Key; }
            double pr = ((mode >> 10) & 31) * 8 + 4, pg = ((mode >> 5) & 31) * 8 + 4, pb = (mode & 31) * 8 + 4;
            double sr = 0, sg = 0, sb = 0; int near = 0;
            foreach (int pixel in cell) if (Distance(pixel, pr, pg, pb) < 20) { sr += (pixel >> 16) & 255; sg += (pixel >> 8) & 255; sb += pixel & 255; ++near; }
            pr = sr / near; pg = sg / near; pb = sb / near;
            const double Tolerance = 34;

            // Step in from each side, past gutter and frame, to where the panel
            // itself begins, and work inside that. A sprite drawn right up to
            // its frame is then no longer joined to it.
            int[] inset = new int[4];
            for (int side = 0; side < 4; ++side) {
                bool across = side < 2;                     // left, right, then top, bottom
                int reach = (across ? width : height) / 4, span = across ? height : width, best = reach;
                for (int tenth = 1; tenth <= 9; ++tenth) {
                    int at = span * tenth / 10, run = 0;
                    for (int depth = 0; depth < reach; ++depth) {
                        int px = across ? (side == 0 ? depth : width - 1 - depth) : at, py = across ? at : (side == 2 ? depth : height - 1 - depth);
                        run = Distance(cell[py * width + px], pr, pg, pb) < Tolerance ? run + 1 : 0;
                        if (run == 4) { if (depth - 3 < best) best = depth - 3; break; }
                    }
                }
                inset[side] = best == reach ? 0 : best;
            }
            {
                int innerWidth = width - inset[0] - inset[1], innerHeight = height - inset[2] - inset[3];
                int[] inner = new int[innerWidth * innerHeight];
                for (int iy = 0; iy < innerHeight; ++iy) Array.Copy(cell, (iy + inset[2]) * width + inset[0], inner, iy * innerWidth, innerWidth);
                cell = inner; width = innerWidth; height = innerHeight; count = width * height;
            }

            // Background is panel. For matter, only panel reached from near the
            // cell's edge: panel-colored areas a sprite encloses stay with it.
            // For light, whatever does not stand out from the panel.
            bool[] background = new bool[count];
            Stack<int> pending = new Stack<int>();
            if (glow) {
                for (int i = 0; i < count; ++i) background[i] = Distance(cell[i], pr, pg, pb) < 40;     // above the haze a panel wears around its light
            } else {
                int band = Math.Max(3, Math.Min(width, height) / 8);
                for (int i = 0; i < count; ++i) {
                    int px = i % width, py = i / width;
                    if ((px < band || py < band || px >= width - band || py >= height - band) && Distance(cell[i], pr, pg, pb) < Tolerance) { background[i] = true; pending.Push(i); }
                }
                int[] step = { -1, 1, -width, width };
                while (pending.Count > 0) {
                    int i = pending.Pop(), px = i % width;
                    for (int s = 0; s < 4; ++s) {
                        int j = i + step[s];
                        if (j < 0 || j >= count || background[j]) continue;
                        if (s == 0 && px == 0) continue;
                        if (s == 1 && px == width - 1) continue;
                        if (Distance(cell[j], pr, pg, pb) < Tolerance) { background[j] = true; pending.Push(j); }
                    }
                }
            }

            // What is left falls into pieces. The largest is the sprite. Of the
            // rest, anything that reaches the edge is a sliver of the frame, a
            // tab between cells or a neighbor; and for matter anything small is
            // noise, where for light it is a spark.
            int[] label = new int[count];
            List<int> areas = new List<int>(); List<bool> edge = new List<bool>();
            areas.Add(0); edge.Add(true);
            for (int start = 0; start < count; ++start) {
                if (background[start] || label[start] != 0) continue;
                int id = areas.Count, area = 0; bool touches = false;
                label[start] = id; pending.Push(start);
                while (pending.Count > 0) {
                    int i = pending.Pop(), px = i % width, py = i / width; ++area;
                    if (px == 0 || py == 0 || px == width - 1 || py == height - 1) touches = true;
                    for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
                        int nx = px + dx, ny = py + dy;
                        if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
                        int j = ny * width + nx;
                        if (!background[j] && label[j] == 0) { label[j] = id; pending.Push(j); }
                    }
                }
                areas.Add(area); edge.Add(touches);
            }
            int largest = 0, sprite = 0;
            for (int id = 1; id < areas.Count; ++id) if (areas[id] > largest) { largest = areas[id]; sprite = id; }
            if (largest == 0) throw new InvalidDataException("Nothing inside the cell: " + output);
            bool[] solid = new bool[count], rim = new bool[count];
            int left = width, top = height, right = -1, bottom = -1, kept = 0;
            for (int i = 0; i < count; ++i) {
                int id = label[i];
                if (id == 0 || (id != sprite && (edge[id] || (!glow && areas[id] * 25 < largest)))) continue;
                solid[i] = true; ++kept;
                int px = i % width, py = i / width;
                if (px < left) left = px; if (px > right) right = px; if (py < top) top = py; if (py > bottom) bottom = py;
            }
            for (int i = 0; i < count; ++i) {
                if (!solid[i]) continue;
                int px = i % width, py = i / width;
                rim[i] = px == 0 || py == 0 || px == width - 1 || py == height - 1 || !solid[i - 1] || !solid[i + 1] || !solid[i - width] || !solid[i + width];
            }

            int[] result = new int[count];
            for (int i = 0; i < count; ++i) {
                if (!solid[i]) continue;
                double alpha = 1, r = (cell[i] >> 16) & 255, g = (cell[i] >> 8) & 255, b = cell[i] & 255;
                if (glow) {
                    // Light: alpha is how far the pixel stands out from the panel.
                    alpha = Math.Max(0.06, Math.Min(1.0, (Distance(cell[i], pr, pg, pb) - 32.0) / 80.0));
                } else if (rim[i]) {
                    // Matter: only a rim pixel is part panel. Where it lies between
                    // the panel's color and that of the sprite just inside it, its
                    // place on that line is its alpha; where it does not (an
                    // outline, of another color than what it encloses), its
                    // distance from the panel is.
                    int px = i % width, py = i / width, inside = 0; double fr = 0, fg = 0, fb = 0;
                    for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
                        int nx = px + dx, ny = py + dy;
                        if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
                        int j = ny * width + nx;
                        if (solid[j] && !rim[j]) { fr += (cell[j] >> 16) & 255; fg += (cell[j] >> 8) & 255; fb += cell[j] & 255; ++inside; }
                    }
                    alpha = Distance(cell[i], pr, pg, pb) / 60.0;
                    if (inside > 0) {
                        double vr = fr / inside - pr, vg = fg / inside - pg, vb = fb / inside - pb, length = vr * vr + vg * vg + vb * vb;
                        if (length > 900) {
                            double along = Math.Max(0.0, Math.Min(1.0, ((r - pr) * vr + (g - pg) * vg + (b - pb) * vb) / length));
                            double er = r - pr - along * vr, eg = g - pg - along * vg, eb = b - pb - along * vb;
                            if (Math.Sqrt(er * er + eg * eg + eb * eb) < 30) alpha = along;
                        }
                    }
                    alpha = Math.Max(0.3, Math.Min(1.0, alpha));
                }
                // Over the panel again, this alpha and color give back the pixel:
                // the panel's share is taken out, so none of it reaches the screen.
                r = (r - (1 - alpha) * pr) / alpha; g = (g - (1 - alpha) * pg) / alpha; b = (b - (1 - alpha) * pb) / alpha;
                result[i] = (int)(alpha * 255 + 0.5) << 24 | Clamp(r) << 16 | Clamp(g) << 8 | Clamp(b);
            }

            // Trim, size, and save. Resampling happens on premultiplied color, so
            // transparent texels lend no color to their neighbors.
            int cw = right - left + 1, ch = bottom - top + 1;
            int[] trimmed = new int[cw * ch];
            for (int ty = 0; ty < ch; ++ty) for (int tx = 0; tx < cw; ++tx)
                trimmed[ty * cw + tx] = result[(top + ty) * width + left + (flip ? cw - 1 - tx : tx)];
            int ow = cw, oh = ch;
            using (Bitmap cut = Write(trimmed, cw, ch)) {
                if (size == 0 || size == Math.Max(cw, ch)) cut.Save(output, ImageFormat.Png);
                else {
                    double scale = (double)size / Math.Max(cw, ch);
                    ow = Math.Max(1, (int)Math.Round(cw * scale)); oh = Math.Max(1, (int)Math.Round(ch * scale));
                    using (Bitmap sized = new Bitmap(ow, oh, PixelFormat.Format32bppPArgb))
                    using (Graphics graphics = Graphics.FromImage(sized)) {
                        graphics.CompositingMode = CompositingMode.SourceCopy;
                        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        graphics.PixelOffsetMode = PixelOffsetMode.Half;
                        using (ImageAttributes wrap = new ImageAttributes()) {
                            wrap.SetWrapMode(WrapMode.TileFlipXY);
                            graphics.DrawImage(cut, new Rectangle(0, 0, ow, oh), 0, 0, cw, ch, GraphicsUnit.Pixel, wrap);
                        }
                        using (Bitmap final = sized.Clone(new Rectangle(0, 0, ow, oh), PixelFormat.Format32bppArgb)) final.Save(output, ImageFormat.Png);
                    }
                }
            }
            return string.Format("{0} x {1}, from {2} x {3}; panel ({4:0},{5:0},{6:0}); {7} texels kept of {8}", ow, oh, cw, ch, pr, pg, pb, kept, count);
        }

        // A plane of normals from a sprite's own shape: its alpha is inflated
        // into a dome, as if the picture were the top of something round. A
        // texel is (x, y, z) with x and y around 128; y points down the picture.
        static uint[] Normals(int[] pixels, int width, int height) {
            int count = width * height;
            float[] depth = new float[count];
            for (int i = 0; i < count; ++i) depth[i] = ((pixels[i] >> 24) & 255) >= 128 ? 1e9f : 0f;
            for (int pass = 0; pass < 2; ++pass)        // a chamfer distance to the edge, there and back
                for (int n = 0; n < count; ++n) {
                    int i = pass == 0 ? n : count - 1 - n, px = i % width, py = i / width, d = pass == 0 ? -1 : 1;
                    float best = depth[i];
                    if (best == 0f) continue;
                    if (px + d < 0 || px + d >= width || py + d < 0 || py + d >= height) best = Math.Min(best, 1f);
                    if (px + d >= 0 && px + d < width) best = Math.Min(best, depth[i + d] + 1f);
                    if (py + d >= 0 && py + d < height) {
                        best = Math.Min(best, depth[i + d * width] + 1f);
                        if (px + d >= 0 && px + d < width) best = Math.Min(best, depth[i + d * width + d] + 1.41f);
                        if (px - d >= 0 && px - d < width) best = Math.Min(best, depth[i + d * width - d] + 1.41f);
                    }
                    depth[i] = best;
                }
            float deepest = 1f;
            foreach (float value in depth) if (value < 1e8f && value > deepest) deepest = value;
            float[] dome = new float[count];
            for (int i = 0; i < count; ++i) { float t = Math.Min(1f, depth[i] / deepest); dome[i] = (float)Math.Sqrt(1 - (1 - t) * (1 - t)) * deepest * 0.8f; }
            for (int pass = 0; pass < 3; ++pass) {      // soften the creases the chamfer leaves along the middle
                float[] smooth = new float[count];
                for (int i = 0; i < count; ++i) {
                    int px = i % width, py = i / width; float sum = 0; int taken = 0;
                    for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
                        int nx = px + dx, ny = py + dy;
                        sum += nx < 0 || ny < 0 || nx >= width || ny >= height ? 0f : dome[ny * width + nx]; ++taken;
                    }
                    smooth[i] = sum / taken;
                }
                dome = smooth;
            }
            uint[] normals = new uint[count];
            for (int i = 0; i < count; ++i) {
                int px = i % width, py = i / width;
                float gx = (dome[py * width + Math.Min(width - 1, px + 1)] - dome[py * width + Math.Max(0, px - 1)]) * 0.5f;
                float gy = (dome[Math.Min(height - 1, py + 1) * width + px] - dome[Math.Max(0, py - 1) * width + px]) * 0.5f;
                float length = (float)Math.Sqrt(gx * gx + gy * gy + 1);
                normals[i] = 0xff000000u | (uint)Clamp(255.0 / length) << 16 | (uint)Clamp(128 - 127.0 * gy / length) << 8 | (uint)Clamp(128 - 127.0 * gx / length);
            }
            return normals;
        }

        static double Linear(double c) { return c <= 0.04045 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4); }
        static double Encoded(double l) { return l <= 0.0031308 ? l * 12.92 : 1.055 * Math.Pow(l, 1 / 2.4) - 0.055; }

        class Frame {
            public string Name, Kind; public int Width, Height, Flags, Recipe, Argument, Solid, Texels, Mask; public uint Checksum;
            public List<double[]> Strokes = new List<double[]>();
        }
        const int Light = 1, Glow = 2, Symmetric = 4;
        static string Number(double value) { return value.ToString("0.0###", CultureInfo.InvariantCulture); }
        static double Value(string text) { return double.Parse(text, CultureInfo.InvariantCulture); }

        // What a drawn frame's strokes cover at a point, by the same rule as
        // `drawn` in pictures.slang; only its alpha, which is all a mask needs.
        static double Coverage(Frame frame, double x, double y) {
            double alpha = 0;
            foreach (double[] s in frame.Strokes) {
                double bx = s[2] - s[0], by = s[3] - s[1], px = x - s[0], py = y - s[1], span = bx * bx + by * by;
                double along = span > 0 ? Math.Max(0.0, Math.Min(1.0, (px * bx + py * by) / span)) : 0;
                double dx = px - along * bx, dy = py - along * by, distance = Math.Sqrt(dx * dx + dy * dy) - s[4];
                if (s[5] > 0) distance = Math.Abs(distance) - s[5];
                double cover = Math.Max(0.0, Math.Min(1.0, 0.5 - distance)) * (((uint)s[6] >> 24) / 255.0);
                alpha = cover + alpha * (1 - cover);
            }
            return alpha;
        }

        // The manifest's lines are described in art.txt. Cut frames come first
        // in the table, in the manifest's order, then the made and the drawn.
        // A texel is premultiplied in linear light and encoded again, R G B A.
        public static string Pack(string manifest, string directory, string blob, string include, string header) {
            List<Frame> cut = new List<Frame>(), rest = new List<Frame>();
            List<string> generators = new List<string>();
            Frame last = null;
            foreach (string raw in File.ReadAllLines(manifest)) {
                string line = raw.Trim();
                if (line.Length == 0 || line[0] == ';') continue;
                string[] part = line.Split(new char[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries);
                int options = 0;
                switch (part[0]) {
                    case "sheet": continue;
                    case "cut": options = 8; break;
                    case "made": options = 5; break;
                    case "drawn": options = 4; break;
                    case "line": last.Strokes.Add(new double[] { Value(part[1]), Value(part[2]), Value(part[3]), Value(part[4]), Value(part[5]), 0, Convert.ToUInt32(part[6], 16) }); continue;
                    case "disc": last.Strokes.Add(new double[] { Value(part[1]), Value(part[2]), Value(part[1]), Value(part[2]), Value(part[3]), 0, Convert.ToUInt32(part[4], 16) }); continue;
                    case "ring": last.Strokes.Add(new double[] { Value(part[1]), Value(part[2]), Value(part[1]), Value(part[2]), Value(part[3]), Value(part[4]) / 2, Convert.ToUInt32(part[5], 16) }); continue;
                    default: throw new InvalidDataException("Not a line of the manifest: " + line);
                }
                Frame frame = new Frame(); frame.Name = part[1]; frame.Kind = part[0];
                for (int i = options; i < part.Length; ++i) frame.Flags |= part[i] == "light" ? Light : part[i] == "glow" ? Glow : part[i] == "symmetric" ? Symmetric : 0;
                if (part[0] == "cut") cut.Add(frame);
                else {
                    int at = part[0] == "made" ? 3 : 2;
                    frame.Width = int.Parse(part[at]); frame.Height = int.Parse(part[at + 1]); frame.Recipe = part[0] == "made" ? 1 : 2;
                    if (part[0] == "made") {
                        if (!generators.Contains(part[2])) generators.Add(part[2]);
                        frame.Argument = generators.IndexOf(part[2]) + 1;
                    }
                    frame.Flags &= ~Light;
                    rest.Add(frame); last = frame;
                }
            }

            int texels = 0, words = 0, strokes = 0; long bakedSolid = 0;
            StringBuilder table = new StringBuilder(), lines = new StringBuilder(), constants = new StringBuilder();
            using (BinaryWriter writer = new BinaryWriter(File.Create(blob))) {
                foreach (Frame frame in cut) {
                    int[] pixels;
                    using (Bitmap bitmap = new Bitmap(Path.Combine(directory, frame.Name + ".png"))) {
                        frame.Width = bitmap.Width; frame.Height = bitmap.Height;
                        pixels = Read(bitmap, new Rectangle(0, 0, frame.Width, frame.Height));
                    }
                    frame.Texels = texels; frame.Mask = words;
                    for (int i = 0; i < pixels.Length; ++i) {
                        uint argb = (uint)pixels[i], alpha = argb >> 24, texel = 0;
                        if (alpha != 0) {
                            double a = alpha / 255.0;
                            texel = alpha << 24 | (uint)Clamp(255 * Encoded(Linear((argb & 255) / 255.0) * a)) << 16
                                | (uint)Clamp(255 * Encoded(Linear(((argb >> 8) & 255) / 255.0) * a)) << 8 | (uint)Clamp(255 * Encoded(Linear(((argb >> 16) & 255) / 255.0) * a));
                        }
                        writer.Write(texel);
                        if (alpha >= 128) ++frame.Solid;
                        frame.Checksum += texel ^ ((uint)(texels + i) * 2654435761u);
                    }
                    texels += pixels.Length;
                    if ((frame.Flags & Light) != 0) {
                        foreach (uint normal in Normals(pixels, frame.Width, frame.Height)) writer.Write(normal);
                        texels += pixels.Length;
                    }
                    words += frame.Height * ((frame.Width + 31) / 32);
                    bakedSolid += frame.Solid;
                }
            }
            int bakedTexels = texels;
            foreach (Frame frame in rest) {
                frame.Texels = texels; frame.Mask = words;
                texels += frame.Width * frame.Height; words += frame.Height * ((frame.Width + 31) / 32);
                if (frame.Recipe != 2) continue;
                frame.Argument = strokes | frame.Strokes.Count << 16;
                strokes += frame.Strokes.Count;
                foreach (double[] s in frame.Strokes)
                    lines.AppendLine(string.Format("\tart_stroke {0},{1},{2},{3},{4},{5},{6}", Number(s[0]), Number(s[1]), Number(s[2]), Number(s[3]), Number(s[4]), Number(s[5]), (uint)s[6]));
                // What the device should find, near enough: its arithmetic is not this one's.
                for (int y = 0; y < frame.Height; ++y) for (int x = 0; x < frame.Width; ++x)
                    if ((int)(Coverage(frame, x + 0.5, y + 0.5) * 255 + 0.5) >= 128) ++frame.Solid;
            }

            table.AppendLine("; Written by source\\myhits\\tools\\art.cs from art.txt. Do not edit.");
            table.AppendLine("; art_frame name, first texel, first mask word, width, height, flags, recipe, argument, solid texels, checksum");
            table.AppendLine("macro art_frames");
            constants.AppendLine("// Written by source\\myhits\\tools\\art.cs from art.txt. Do not edit.");
            int index = 0;
            List<Frame> all = new List<Frame>(cut); all.AddRange(rest);
            StringBuilder names = new StringBuilder();
            foreach (Frame frame in all) {
                table.AppendLine(string.Format("\tart_frame {0},{1},{2},{3},{4},{5},{6},{7},{8},{9}", frame.Name, frame.Texels, frame.Mask, frame.Width, frame.Height, frame.Flags, frame.Recipe, frame.Argument, frame.Solid, frame.Checksum));
                names.AppendLine(string.Format("FRAME_{0} := {1}", frame.Name.ToUpperInvariant(), index));
                constants.AppendLine(string.Format("static const uint FRAME_{0} = {1};", frame.Name.ToUpperInvariant(), index));
                ++index;
            }
            table.AppendLine("end macro");
            table.AppendLine("; art_stroke from x, y, to x, y, radius, half the width of its outline or 0 when filled, color");
            table.AppendLine("macro art_strokes");
            table.Append(lines);
            table.AppendLine("end macro");
            table.Append(names);
            string[] totals = { "ART_FRAMES", all.Count.ToString(), "ART_BAKED_FRAMES", cut.Count.ToString(), "ART_TEXELS", texels.ToString(), "ART_BAKED_TEXELS", bakedTexels.ToString(),
                "ART_MASK_WORDS", words.ToString(), "ART_STROKES", strokes.ToString(), "ART_BAKED_SOLID", bakedSolid.ToString() };
            for (int i = 0; i < totals.Length; i += 2) {
                table.AppendLine(totals[i] + " := " + totals[i + 1]);
                constants.AppendLine("static const uint " + totals[i] + " = " + totals[i + 1] + ";");
            }
            for (int i = 0; i < generators.Count; ++i) constants.AppendLine(string.Format("static const uint MADE_{0} = {1};", generators[i].ToUpperInvariant(), i + 1));
            File.WriteAllText(include, table.ToString());
            File.WriteAllText(header, constants.ToString());
            return string.Format("{0} frames ({1} cut, {2} made or drawn), {3} texels ({4} KB embedded), {5} mask words, {6} strokes", all.Count, cut.Count, rest.Count, texels, bakedTexels * 4 / 1024, words, strokes);
        }
    }
}
