using System;
using System.IO;

namespace VkFasmgTests {
    public static class CubeImage {
        // Checks raw top-down BGRA exports without relying on an image library.
        public static int Check(string path, int width, int height) {
            byte[] image = File.ReadAllBytes(path);
            if (image.Length != 54 + width*height*4 || image[0] != 'B' || image[1] != 'M' ||
                BitConverter.ToInt32(image,18) != width || BitConverter.ToInt32(image,22) != -height ||
                BitConverter.ToInt32(image,10) != 54 || BitConverter.ToInt16(image,28) != 32)
                throw new InvalidDataException("Incomplete cube export: " + path);
            int colored = 0, cube = 0;
            for (int i=54; i<image.Length; i+=4) {
                if (image[i+3] != 255) throw new InvalidDataException("Unrendered cube pixel");
                if (image[i] > image[i+2] + 5 || image[i+1] > image[i+2] + 5) ++colored;
                if (Math.Abs(image[i]-image[54]) > 5 || Math.Abs(image[i+1]-image[55]) > 5 ||
                    Math.Abs(image[i+2]-image[56]) > 5) ++cube;
            }
            if (colored < width*height/200 || cube < width*height/10 || cube > width*height*3/4)
                throw new InvalidDataException("Textured, lit cube is missing or clipped: " + path);
            return cube;
        }

        public static int Compare(string first, string second, int tolerance) {
            byte[] a = File.ReadAllBytes(first), b = File.ReadAllBytes(second);
            if (a.Length != b.Length || BitConverter.ToInt32(a,18) != BitConverter.ToInt32(b,18) ||
                BitConverter.ToInt32(a,22) != BitConverter.ToInt32(b,22))
                throw new InvalidDataException("Cube image dimensions differ");
            int different=0;
            for (int i=54; i<a.Length; i+=4)
                if (Math.Abs(a[i]-b[i]) > tolerance || Math.Abs(a[i+1]-b[i+1]) > tolerance ||
                    Math.Abs(a[i+2]-b[i+2]) > tolerance) ++different;
            return different;
        }
    }
}
