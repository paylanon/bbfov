;; nasm -f win64 -o hook.lib hook.asm
        
segment .data
global FOV_HOOK_SIGNATURE
global FOV_HOOK_SIGNATURE_END
global FOV_CAVE
global FOV_CAVE_END
global FOV_DEST
global _patch_returnaddr

;; https://www.nexusmods.com/bloodborne/mods/193
        
FOV_HOOK_SIGNATURE:
        vmovss [r13 + 0x50], xmm1
        vmovss xmm2, [r13 + 0x184]
FOV_HOOK_SIGNATURE_END:
        
FOV_CAVE:
        addss xmm1, dword [rel FOV_DEST]
        vmovss dword [r13+0x50], xmm1
        vmovss xmm2, dword [r13+0x184]
        jmp qword [rel _patch_returnaddr]
_patch_returnaddr:
        dq 0xDEADBEEFDEADBEEF
FOV_DEST:
        dd 0
FOV_CAVE_END:
