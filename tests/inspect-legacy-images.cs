using System;
using System.Collections.Generic;
using System.IO;

namespace VkFasmgTests {
    // A complete, opaque, top-down BGRA export.
    public sealed class FractalImage {
        public readonly byte[] Pixels;
        public readonly int Width, Height, Colors;

        public FractalImage(string path) {
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
                if (Pixels[i + 3] != 255)
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
    }
}
