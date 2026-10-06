using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace VkFasmgTests {
    public static class RangeAllocator {
        [DllImport("kernel32", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr LoadLibraryW(string path);
        [DllImport("vk_ranges_test")] static extern int range_test_create(ulong bytes);
        [DllImport("vk_ranges_test")] static extern IntPtr range_test_allocate(ulong bytes, ulong alignment);
        [DllImport("vk_ranges_test")] static extern ulong range_test_offset(IntPtr token);
        [DllImport("vk_ranges_test")] static extern void range_test_free(IntPtr token);
        [DllImport("vk_ranges_test")] static extern void range_test_destroy();
        [DllImport("vk_ranges_test")] static extern int range_test_capacity();
        sealed class Allocation { public IntPtr Token; public ulong Offset, Bytes; }
        static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
        public static string Check(string path) {
            Require(LoadLibraryW(path) != IntPtr.Zero, "Cannot load the native range allocator probe");
            const ulong heapBytes = 1024*1024;
            Require(range_test_create(heapBytes) != 0, "Cannot initialize range allocator");
            try {
                var active = new Allocation[128];
                var random = new Random(0x724816);
                int successful = 0;
                for (int operation=0; operation<100000; ++operation) {
                    int slot = random.Next(active.Length);
                    if (active[slot] != null) {
                        range_test_free(active[slot].Token);
                        active[slot] = null;
                    } else {
                        ulong bytes = (ulong)random.Next(1,32769);
                        ulong alignment = 1UL << random.Next(0,13);
                        IntPtr token = range_test_allocate(bytes,alignment);
                        if (token == IntPtr.Zero) continue;
                        ulong offset = range_test_offset(token);
                        Require(offset % alignment == 0 && offset+bytes <= heapBytes, "Misaligned or out-of-bounds allocation");
                        foreach (Allocation other in active) {
                            if (other != null) Require(offset+bytes <= other.Offset || other.Offset+other.Bytes <= offset, "Live allocations overlap");
                        }
                        active[slot] = new Allocation {Token=token,Offset=offset,Bytes=bytes};
                        ++successful;
                    }
                }
                Require(successful > 20000, "Allocator stopped making progress");
                foreach (Allocation allocation in active) if (allocation != null) range_test_free(allocation.Token);
                Require(range_test_allocate(0,1) == IntPtr.Zero && range_test_allocate(1,0) == IntPtr.Zero &&
                        range_test_allocate(1,3) == IntPtr.Zero && range_test_allocate(ulong.MaxValue,1) == IntPtr.Zero,
                        "Invalid requests must fail without changing the heap");
                IntPtr whole = range_test_allocate(heapBytes,4096);
                Require(whole != IntPtr.Zero && range_test_offset(whole) == 0, "Free ranges did not fully coalesce");
                Require(range_test_allocate(1,1) == IntPtr.Zero, "An exhausted heap returned overlapping memory");
                range_test_free(whole);
                var nodes = new List<IntPtr>();
                for (int i=0; i<range_test_capacity()-1; ++i) {
                    IntPtr token = range_test_allocate(1,1);
                    Require(token != IntPtr.Zero && range_test_offset(token) == (ulong)i, "Node inventory leaked or lost range order");
                    nodes.Add(token);
                }
                Require(range_test_allocate(1,1) == IntPtr.Zero, "Metadata exhaustion must fail cleanly");
                range_test_free(nodes[0]); range_test_free(nodes[1]);
                IntPtr joined = range_test_allocate(2,1);
                Require(joined != IntPtr.Zero && range_test_offset(joined) == 0, "Coalescing failed under metadata pressure");
                range_test_free(joined);
                for (int i=2; i<nodes.Count; ++i) range_test_free(nodes[i]);
                whole = range_test_allocate(heapBytes,1);
                Require(whole != IntPtr.Zero && range_test_offset(whole) == 0, "Metadata-pressure recovery lost storage");
                range_test_free(whole);
                return "[ranges] 100000 randomized operations: alignment, non-overlap, coalescing, overflow and metadata exhaustion passed";
            } finally { range_test_destroy(); }
        }
    }
}
