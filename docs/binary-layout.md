# Import calls, storage lifetime, and stack frames

Use this policy when adding or changing Windows x64 assembly modules. The
compute recipes and their runtime/console helpers apply it, as do the loader
examples' shared instance/device code. Existing application modules can adopt
it when they are changed.

## Win32 calls

The default is a direct call through the import address table:

```asm
extrn '__imp_ExitProcess' as ExitProcess:qword
fastcall [ExitProcess],0
```

Local procedures retain named calls, such as `fastcall console_initialize`.
Runtime-resolved functions retain their pointer calls. Choosing a Vulkan
loader is an explicit binding decision; `thunk.inc` demonstrates named Vulkan
imports deliberately.

A named Win32 import is an explicit exception:

```asm
extrn ExitProcess:qword
fastcall ExitProcess,0
```

Document its purpose at the declaration or in the module's guide: a measured
size/locality benefit or an intentionally shared patch point. Include every
call site and distinct imported function in the comparison. For x64 call/jump
encodings, a direct IAT call occupies six bytes, a relative call five, and
each shared linker import thunk six. With `C` call sites and `F` functions,
named thunks change the call/thunk total by `6*F-C` bytes, before alignment.
Runtime invocation frequency does not change the number of emitted sites.
Timing or locality claims require measurements; redirected IAT entries already
provide a shared target with direct IAT calls.

The recipes have nine Win32 call sites across nine imported functions. Named
thunks would add 45 bytes to that call/thunk total before alignment. Their
default therefore uses direct IAT calls.

## Storage

Choose storage by lifetime before choosing a section. Query records,
enumeration arrays, allocation requirements, timestamps, and synchronous
formatting buffers belong to the procedure that consumes them. Declare the
types and buffers directly in `locals`; a one-use wrapper structure adds no
useful ownership boundary:

```asm
proc create_buffers
        locals
                memory_properties VkPhysicalDeviceMemoryProperties2
        endl
        mov [memory_properties.sType],VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2
        mov [memory_properties.pNext],0
        vkGetPhysicalDeviceMemoryProperties2 [physical_device],addr memory_properties
        ; Pass this address to the allocation helpers while this frame exists.
        ; Do not retain it after returning.
        ret
endp
```

Output payloads need no blanket zeroing when the successful query fills them.
Set required headers and terminate query chains before calling Vulkan; inspect
the result before consuming an output. Reserved locals have unspecified initial
contents. The toolkit emits stores for initialized locals, so keep large
reserved buffers separate from initialized declarations.

Keep handles, callback flags, and state shared with later work or cleanup alive
for that work. Small creation/submission records shared across procedures can
remain global in these single-threaded recipes. A future concurrent context
would need its own records. A recurring string buffer warrants persistent
storage only when its contents or allocation must survive the consuming call;
the recipes' formatting helper consumes each local line synchronously.

Put every wholly zero-initialized persistent object in a reserved BSS group,
using `?`, `rb`, `rw`, `rd`, or `rq`:

```asm
section '.bss$app' readable writeable align 16
device dq ?
validation_failed dd ?
```

Windows supplies the initial BSS zero values. Custom structures intended for BSS
must also use reserved defaults (`dq ?`, etc.). Generated Vulkan structures
already reserve unspecified fields. Query records can therefore be declared
wholly reserved; initialize required `sType` and `pNext` headers before the
query, whether local or persistent. Keep their type and field names rather
than replacing them with untyped byte offsets.

Use `.data` for writable records containing nonzero initial constants or
relocated pointers. Use `.rdata` for immutable bytes. Zeros inside such mixed
records and alignment padding remain part of their record layout; do not split
individual zero fields away from their ABI structure.

In this repository's NEWCOFF format, moving reserved bytes to the end of a
mixed initialized section still serializes them: `coffms.inc` pads that tail
with zeros. A separate wholly reserved section is required. Merely naming a
section `.bss` also does not suffice: `dq 0` emits initialized bytes. Inspect
the produced object for `IMAGE_SCN_CNT_UNINITIALIZED_DATA` and zero
`PointerToRawData`. NEWCOFF's BSS `SizeOfRawData` field records its logical
extent, so that field alone is not a file-byte count.

The linker may merge BSS into the zero-filled tail of the PE `.data` section.
Its virtual size includes this storage; its raw size should include only the
initialized portion and file alignment. `check-recipes` checks these object
and PE properties plus actual Win32 IAT call instructions. It also checks the
recipe's results and error paths, so moving storage cannot silently change
the required initial state. Each recipe's persistent BSS group must fit within
one page; large startup scratch must remain scoped.

## Stack growth

`newcoff.inc` exposes `PAGE_SIZE = 1000h`, `TeStackLimit = 0010h`, and
`__chkstk`. The probe reads the current committed stack limit from the x64 TEB
and touches each lower page down to the already-adjusted RSP. It emits 24 bytes,
clobbers RAX and flags, and preserves RCX, RDX, R8, and R9.

The application's existing static-RSP prologue invokes the probe automatically
when its calculated allocation exceeds `PAGE_SIZE`, before initialized locals
or the procedure body touch the frame. It retains the toolkit's register saves,
alignment, outgoing argument area, and matching epilogue. Smaller frames incur
no probe code. Explicit allocations must invoke the macro after lowering RSP
and before using that storage:

```asm
sub rsp,1 shl 20
__chkstk
; Use the buffer, then restore RSP before the procedure epilogue.
```

`build.cmd check-stack` links a probe with a one-page initial stack commitment.
It exercises an automatic 128 KiB local allocation and explicit 192 KiB
allocation, checks incoming arguments and local initialization, and checks the
emitted sequence plus the absence of a probe in a small frame. Both
`check-api` and the recipe checks include it.
