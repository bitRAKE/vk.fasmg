# Import calls and zero-initialized storage

Use this policy when adding or changing Windows x64 assembly modules. The
runtime bootstrap and loader examples' shared console/instance/device helpers
apply it. Existing application modules can adopt it when they are changed.

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

## Storage

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
initialized portion and file alignment. Inspect both the object and linked PE to
verify that reserved storage adds virtual extent without serialized file
bytes beyond the initialized data and file alignment.
