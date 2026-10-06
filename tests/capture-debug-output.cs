// Launch only the test executable as a Windows debuggee and collect real
// OUTPUT_DEBUG_STRING_EVENT records. No debugger or SDK needs to be installed.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace VkFasmgTests {
    public static class DebugOutputCapture {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct StartupInfo {
            public int cb;
            public string reserved, desktop, title;
            public int x, y, xSize, ySize, xCountChars, yCountChars, fillAttribute, flags;
            public short showWindow, reservedBytes;
            public IntPtr reservedPointer, stdin, stdout, stderr;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct ProcessInfo {
            public IntPtr process, thread;
            public uint processId, threadId;
        }
        [StructLayout(LayoutKind.Sequential)]
        struct SecurityAttributes {
            public int length;
            public IntPtr descriptor;
            public int inherit;
        }
        // Windows x64 DEBUG_EVENT: 16-byte header followed by its 160-byte union.
        [StructLayout(LayoutKind.Explicit, Size = 176)]
        struct DebugEvent {
            [FieldOffset(0)] public uint code;
            [FieldOffset(4)] public uint processId;
            [FieldOffset(8)] public uint threadId;
            [FieldOffset(16)] public IntPtr dataPointer; // hFile or debug string
            [FieldOffset(16)] public uint exitOrExceptionCode;
            [FieldOffset(24)] public ushort unicode;
            [FieldOffset(26)] public ushort textLength;
        }
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern bool CreateProcessW(string app, StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes, bool inherit,
            uint flags, IntPtr environment, string directory,
            ref StartupInfo startup, out ProcessInfo process);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern IntPtr CreateFileW(string name, uint access, uint share,
            ref SecurityAttributes attributes, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool WaitForDebugEventEx(out DebugEvent data, uint milliseconds);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool ContinueDebugEvent(uint processId, uint threadId, uint status);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool ReadProcessMemory(IntPtr process, IntPtr address,
            byte[] buffer, UIntPtr count, out UIntPtr read);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        [DllImport("kernel32.dll")] static extern bool TerminateProcess(IntPtr process, uint code);

        public static string Run(string executable, string directory) {
            if (IntPtr.Size != 8) throw new InvalidOperationException("Use x64 PowerShell.");
            var startup = new StartupInfo();
            startup.cb = Marshal.SizeOf(typeof(StartupInfo));
            ProcessInfo process;
            // A hidden debuggee still receives valid standard handles. Discard
            // its stdout here; the ordinary run verifies the console contents.
            var attributes = new SecurityAttributes();
            attributes.length = Marshal.SizeOf(typeof(SecurityAttributes));
            attributes.inherit = 1;
            IntPtr nullHandle = CreateFileW("NUL", 0xC0000000, 3, ref attributes, 3, 0x80, IntPtr.Zero);
            if (nullHandle == new IntPtr(-1)) throw new Win32Exception(Marshal.GetLastWin32Error());
            try {
                startup.flags = 0x100; // STARTF_USESTDHANDLES.
                startup.stdin = startup.stdout = startup.stderr = nullHandle;
                // DEBUG_ONLY_THIS_PROCESS | CREATE_NO_WINDOW.
                if (!CreateProcessW(executable, null, IntPtr.Zero, IntPtr.Zero, true,
                        0x08000002, IntPtr.Zero, directory, ref startup, out process))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
            } finally { CloseHandle(nullHandle); }
            var output = new StringBuilder();
            var timer = Stopwatch.StartNew();
            bool exited = false, pending = false;
            DebugEvent current = new DebugEvent();
            try {
                while (timer.ElapsedMilliseconds < 30000) {
                    if (!WaitForDebugEventEx(out current, 1000)) {
                        int error = Marshal.GetLastWin32Error();
                        if (error == 121) continue; // ERROR_SEM_TIMEOUT.
                        throw new Win32Exception(error);
                    }
                    pending = true;
                    uint status = 0x00010002; // DBG_CONTINUE.
                    if (current.code == 3 || current.code == 6) { // CREATE_PROCESS / LOAD_DLL.
                        if (current.dataPointer != IntPtr.Zero) CloseHandle(current.dataPointer);
                    } else if (current.code == 8) { // OUTPUT_DEBUG_STRING_EVENT.
                        // nDebugStringLength is a byte count for both formats.
                        // https://learn.microsoft.com/windows/win32/api/minwinbase/ns-minwinbase-output_debug_string_info
                        int bytes = current.textLength;
                        if (bytes != 0) {
                            var buffer = new byte[bytes];
                            UIntPtr read;
                            if (!ReadProcessMemory(process.process, current.dataPointer,
                                    buffer, (UIntPtr)bytes, out read))
                                throw new Win32Exception(Marshal.GetLastWin32Error());
                            int length = checked((int)read.ToUInt64());
                            string text = (current.unicode != 0 ? Encoding.Unicode : Encoding.Default)
                                .GetString(buffer, 0, length);
                            // Exclude the terminating NUL from captured text.
                            int end = text.IndexOf('\0');
                            output.Append(end < 0 ? text : text.Substring(0, end));
                        }
                    } else if (current.code == 1) { // EXCEPTION_DEBUG_EVENT.
                        if (current.exitOrExceptionCode != 0x80000003 &&
                            current.exitOrExceptionCode != 0x80000004)
                            status = 0x80010001; // DBG_EXCEPTION_NOT_HANDLED.
                    }
                    if (!ContinueDebugEvent(current.processId, current.threadId, status))
                        throw new Win32Exception(Marshal.GetLastWin32Error());
                    pending = false;
                    if (current.code == 5) { // EXIT_PROCESS_DEBUG_EVENT.
                        exited = true;
                        if (current.exitOrExceptionCode != 0)
                            throw new InvalidOperationException("Debuggee exited with " +
                                current.exitOrExceptionCode + ":\n" + output);
                        return output.ToString();
                    }
                }
                throw new TimeoutException("Debug output capture exceeded 30 seconds.");
            } finally {
                if (!exited) {
                    TerminateProcess(process.process, 101);
                    if (pending) ContinueDebugEvent(current.processId, current.threadId, 0x00010002);
                }
                CloseHandle(process.thread);
                CloseHandle(process.process);
            }
        }
    }
}
