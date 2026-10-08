// Proof 08's pictures, read; and the same font's outlines from another hand,
// to hold them to.
//
// A picture of a page is ink on black, in sRGB, and every color the pages
// use has one channel full: how much of a pixel is ink is its brightest
// channel, put back into linear light. What a line's ink should come
// to is asked of GDI+, which reads the font for itself, lays the string out
// its own way and gives its outline as a path: the path is flattened and the
// area inside it found from its corners. Nothing of DirectWrite, of text.inc
// or of the device is in that number. And what layers a glyph of colors has
// is read from its font's file, table by table.
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.Runtime.InteropServices;

namespace Myhits
{
    public sealed class Ink
    {
        public readonly int Width, Height;
        readonly float[] covered;
        readonly int[] colors;

        public Ink(string path)
        {
            using (Bitmap bitmap = new Bitmap(path))
            {
                Width = bitmap.Width;
                Height = bitmap.Height;
                covered = new float[Width * Height];
                colors = new int[Width * Height];
                float[] linear = new float[256];
                for (int value = 0; value < 256; ++value)
                {
                    double encoded = value / 255.0;
                    linear[value] = (float)(encoded <= 0.04045 ? encoded / 12.92 : Math.Pow((encoded + 0.055) / 1.055, 2.4));
                }
                BitmapData data = bitmap.LockBits(new Rectangle(0, 0, Width, Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                int[] row = new int[Width];
                for (int y = 0; y < Height; ++y)
                {
                    Marshal.Copy(new IntPtr(data.Scan0.ToInt64() + (long)y * data.Stride), row, 0, Width);
                    for (int x = 0; x < Width; ++x)
                    {
                        covered[y * Width + x] = linear[Math.Max(Math.Max((row[x] >> 16) & 255, (row[x] >> 8) & 255), row[x] & 255)];
                        colors[y * Width + x] = row[x] & 0xffffff;
                    }
                }
                bitmap.UnlockBits(data);
            }
        }

        // The ink in a box of pixels, in pixels.
        public double Box(int left, int top, int right, int bottom)
        {
            double sum = 0;
            for (int y = Math.Max(top, 0); y < Math.Min(bottom, Height); ++y)
                for (int x = Math.Max(left, 0); x < Math.Min(right, Width); ++x) sum += covered[y * Width + x];
            return sum;
        }

        // How unlike a box of pixels is the box as far away as `across`: the
        // differences of their ink, added up, in pixels.
        public double Unlike(int left, int top, int right, int bottom, int across)
        {
            double sum = 0;
            for (int y = top; y < bottom; ++y)
                for (int x = left; x < right; ++x) sum += Math.Abs(covered[y * Width + x] - covered[y * Width + x + across]);
            return sum;
        }

        // How many pixels of a box are a color, within `slack` in each of red, green and blue.
        public int Count(int left, int top, int right, int bottom, int red, int green, int blue, int slack)
        {
            int count = 0;
            for (int y = top; y < bottom; ++y)
                for (int x = left; x < right; ++x)
                {
                    int color = colors[y * Width + x];
                    if (Math.Abs(((color >> 16) & 255) - red) <= slack && Math.Abs(((color >> 8) & 255) - green) <= slack && Math.Abs((color & 255) - blue) <= slack) ++count;
                }
            return count;
        }

        // The layers a font of colors gives a glyph, read from the font's own
        // file: its COLR table says which glyphs lie over one another to make
        // it and which of the font's colors each is, and its CPAL table what
        // those colors are. A line to a layer, as proof 08's program writes
        // them: its glyph, its color as a texel's bytes, and which color.
        public static string Layers(string path, int glyph)
        {
            byte[] font = System.IO.File.ReadAllBytes(path);
            int colr = 0, cpal = 0;
            for (int table = 0; table < Short(font, 4); ++table)
            {
                string tag = System.Text.Encoding.ASCII.GetString(font, 12 + table * 16, 4);
                if (tag == "COLR") colr = Long(font, 12 + table * 16 + 8);
                if (tag == "CPAL") cpal = Long(font, 12 + table * 16 + 8);
            }
            if (colr == 0 || cpal == 0) return "the font has no COLR or no CPAL";
            int bases = colr + Long(font, colr + 4), layers = colr + Long(font, colr + 8);
            int records = cpal + Long(font, cpal + 8), first = Short(font, cpal + 12);
            System.Text.StringBuilder said = new System.Text.StringBuilder();
            for (int each = 0; each < Short(font, colr + 2); ++each)
            {
                if (Short(font, bases + each * 6) != glyph) continue;
                int from = Short(font, bases + each * 6 + 2), count = Short(font, bases + each * 6 + 4);
                for (int layer = from; layer < from + count; ++layer)
                {
                    int palette = Short(font, layers + layer * 4 + 2), record = records + (first + palette) * 4;
                    // (Blue, green, red, and how much of them; a layer of no color of the font's takes the text's.)
                    uint texel = palette == 0xffff ? 0xffffffffu : (uint)(font[record + 2] | font[record + 1] << 8 | font[record] << 16) | (uint)font[record + 3] << 24;
                    if (texel >> 24 == 0) continue;     // a layer there is nothing of is not one
                    said.AppendFormat("{0} {1:X8} {2}\n", Short(font, layers + layer * 4), texel, palette);
                }
            }
            return said.ToString();
        }

        static int Short(byte[] bytes, int at) { return bytes[at] << 8 | bytes[at + 1]; }
        static int Long(byte[] bytes, int at) { return bytes[at] << 24 | bytes[at + 1] << 16 | bytes[at + 2] << 8 | bytes[at + 3]; }

        // The ink in a box that has been turned about a point: of every pixel
        // whose middle, turned back, lies in the box as it was before.
        public double Turned(double x, double y, double angle, double left, double top, double right, double bottom)
        {
            double cos = Math.Cos(angle), sin = Math.Sin(angle), sum = 0;
            for (int row = 0; row < Height; ++row)
                for (int column = 0; column < Width; ++column)
                {
                    float ink = covered[row * Width + column];
                    if (ink == 0) continue;
                    double dx = column + 0.5 - x, dy = row + 0.5 - y;
                    double along = dx * cos + dy * sin, down = dy * cos - dx * sin;
                    if (along >= left && along < right && down >= top && down < bottom) sum += ink;
                }
            return sum;
        }

        // The box of the ink in a box of pixels: where each of its edges
        // lies, to a part of a pixel, from how much of the first and the last
        // column and row with any ink in them is ink. (Where an outline is
        // furthest out it runs along the edge, and the pixel it is furthest
        // out in is covered by just as much as the outline is into it.)
        // "left top right bottom".
        public string Bounds(int left, int top, int right, int bottom)
        {
            double[] columns = new double[right - left], rows = new double[bottom - top];
            for (int y = top; y < bottom; ++y)
                for (int x = left; x < right; ++x)
                {
                    columns[x - left] = Math.Max(columns[x - left], covered[y * Width + x]);
                    rows[y - top] = Math.Max(rows[y - top], covered[y * Width + x]);
                }
            return String.Format(CultureInfo.InvariantCulture, "{0:0.000} {1:0.000} {2:0.000} {3:0.000}",
                left + Edge(columns, false), top + Edge(rows, false), left + Edge(columns, true), top + Edge(rows, true));
        }

        static double Edge(double[] most, bool far)
        {
            if (!far)
            {
                for (int each = 0; each < most.Length; ++each) if (most[each] > 0.02) return each + 1 - Math.Min(most[each], 1.0);
                return most.Length;
            }
            for (int each = most.Length - 1; each >= 0; --each) if (most[each] > 0.02) return each + Math.Min(most[each], 1.0);
            return 0;
        }

        // What GDI+ makes of a string in a font at a size: the area its
        // outline encloses, in pixels, and the box of the outline, from where
        // the string was set. "area left top right bottom".
        public static string Second(string family, bool bold, double size, string text)
        {
            using (GraphicsPath path = new GraphicsPath(FillMode.Winding))
            using (FontFamily font = new FontFamily(family))
            {
                path.AddString(text, font, (int)(bold ? FontStyle.Bold : FontStyle.Regular), (float)size, new PointF(0, 0), StringFormat.GenericTypographic);
                // Flattened fine, at eight times the size, so that what is lost in the corners is nothing.
                using (Matrix larger = new Matrix(8, 0, 0, 8, 0, 0)) path.Flatten(larger, 0.02f);
                PointF[] points = path.PathPoints;
                byte[] kinds = path.PathTypes;
                double area = 0, left = 1e30, top = 1e30, right = -1e30, bottom = -1e30;
                int first = 0;
                for (int each = 0; each < points.Length; ++each)
                {
                    if ((kinds[each] & 7) == 0) first = each;
                    bool last = each + 1 == points.Length || (kinds[each + 1] & 7) == 0;
                    PointF from = points[each], to = last ? points[first] : points[each + 1];
                    area += (double)from.X * to.Y - (double)to.X * from.Y;
                    left = Math.Min(left, from.X); right = Math.Max(right, from.X);
                    top = Math.Min(top, from.Y); bottom = Math.Max(bottom, from.Y);
                }
                return String.Format(CultureInfo.InvariantCulture, "{0:0.0} {1:0.000} {2:0.000} {3:0.000} {4:0.000}", Math.Abs(area) / 2 / 64, left / 8, top / 8, right / 8, bottom / 8);
            }
        }
    }
}
