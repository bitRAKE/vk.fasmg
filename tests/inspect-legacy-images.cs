using System;
using System.Collections.Generic;
using System.IO;

namespace VkFasmgTests {
    public sealed class FractalImage {
        public readonly byte[] Pixels;
        public readonly int Width, Height, Colors;

        public FractalImage(string path, bool requireOpaque) {
            byte[] file = File.ReadAllBytes(path);
            if (file.Length < 54 || file[0] != 'B' || file[1] != 'M' ||
                BitConverter.ToInt32(file, 2) != file.Length ||
                BitConverter.ToInt32(file, 10) != 54 ||
                BitConverter.ToInt32(file, 14) != 40 ||
                BitConverter.ToInt16(file, 26) != 1 ||
                BitConverter.ToInt16(file, 28) != 32 ||
                BitConverter.ToInt32(file, 30) != 0)
                throw new InvalidDataException("Invalid top-down BGRA bitmap: " + path);
            Width = BitConverter.ToInt32(file, 18);
            Height = -BitConverter.ToInt32(file, 22);
            if (Width <= 0 || Height <= 0 ||
                checked(Width * Height * 4 + 54) != file.Length)
                throw new InvalidDataException("Incomplete image: " + path);
            Pixels = new byte[file.Length - 54];
            Buffer.BlockCopy(file, 54, Pixels, 0, Pixels.Length);
            var colors = new HashSet<uint>();
            for (int i = 0; i < Pixels.Length; i += 4) {
                if (requireOpaque && Pixels[i + 3] != 255)
                    throw new InvalidDataException("Unrendered pixel: " + path);
                colors.Add(BitConverter.ToUInt32(Pixels, i) & 0xffffff);
            }
            Colors = colors.Count;
        }

        public int DifferentPixels(FractalImage other) {
            if (Width != other.Width || Height != other.Height)
                throw new InvalidDataException("Image dimensions differ");
            int count = 0;
            for (int i = 0; i < Pixels.Length; i += 4)
                if (Pixels[i] != other.Pixels[i] || Pixels[i+1] != other.Pixels[i+1] ||
                    Pixels[i+2] != other.Pixels[i+2]) ++count;
            return count;
        }

        public void CheckLayout(FractalImage render, int canvasTop, int footerTop, int footerBottom) {
            if (render.Width != Width || canvasTop < 0 ||
                canvasTop + render.Height != footerTop - 12 ||
                footerTop < 0 || footerBottom != Height - 12 || footerTop >= footerBottom)
                throw new InvalidDataException("Render does not fill client width or footer is not anchored");
            for (int y = 0; y < render.Height; ++y)
                for (int x = 0; x < Width; ++x) {
                    int a = ((y + canvasTop) * Width + x) * 4;
                    int b = (y * Width + x) * 4;
                    if (Pixels[a] != render.Pixels[b] || Pixels[a+1] != render.Pixels[b+1] ||
                        Pixels[a+2] != render.Pixels[b+2])
                        throw new InvalidDataException("Canvas was cropped, stretched, or painted with sidebars");
                }
            int textPixels = 0;
            for (int y = footerTop; y < footerBottom; ++y)
                for (int x = 16; x < Width - 16; ++x) {
                    int i = (y * Width + x) * 4;
                    // Dark background is RGB(10, 15, 26); footer text is brighter.
                    if (Pixels[i] > 40 || Pixels[i+1] > 40 || Pixels[i+2] > 40) ++textPixels;
                }
            if (textPixels < 50) throw new InvalidDataException("Footer text is missing or clipped");
        }
    }
}
