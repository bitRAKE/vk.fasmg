; Capability bits, and the build contract over them.
;
; CAP_MASK names the capabilities a build may select; CAP_REQUIRED, a subset,
; those it cannot do without. Device negotiation fails when a required one is
; unavailable. Code that depends on a capability sits in a `route` block, and
; what replaces it in an `alternate` block:
;
;	route CAP_SYNC,.legacy
;		vkCmdPipelineBarrier2 [command_buffer],addr dependency
;		ret
;	end route
;	alternate CAP_SYNC
;	.legacy:
;		vkCmdPipelineBarrier [command_buffer],...
;		ret
;	end alternate
;
; A route is assembled only if the contract can select it, an alternate only if
; the contract can decline it. The label says where execution goes when the
; block does not apply; the test of active_caps behind it is assembled only
; while both remain possible. Without a label there is no test: use that
; around data, and inside a block that has already decided.
;
; Blocks nest. A block takes one capability bit.
CAP_RENDER := 1
CAP_SYNC := 2
CAP_COPY := 4
CAP_INLINE := 8
CAP_TIMELINE := 16
CAP_FLOAT64 := 32

if ~ definite CAP_REQUIRED
	CAP_REQUIRED := 0
end if
assert CAP_REQUIRED and CAP_MASK = CAP_REQUIRED

; Unconditional, so that a block nested in one being skipped still pairs up;
; case-sensitive, so that Win32's ALTERNATE stays a constant.
macro route! bit*,otherwise
	if bit and CAP_MASK
		match label, otherwise
			if ~ bit and CAP_REQUIRED
				test [active_caps],bit
				jz label
			end if
		end match
end macro
macro end?.route!
	end if
end macro

macro alternate! bit*,otherwise
	if ~ bit and CAP_REQUIRED
		match label, otherwise
			if bit and CAP_MASK
				test [active_caps],bit
				jnz label
			end if
		end match
end macro
macro end?.alternate!
	end if
end macro
