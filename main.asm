; ============================================================
;   OS for MSX (Z80)
;   Build: sjasmplus main.asm
;   Run:  Load at 0100h and JP 0100h
; ============================================================

                ORG 0100h

; ============================================================
; CCP (Command Console Processor)
; ============================================================

CCP_START:
                LD DE,PromptStr
                LD C,9
                CALL BDOS_ENTRY

                LD DE,CmdBuf
READ_LOOP:
                LD C,1
                CALL BDOS_ENTRY        ; CONIN → A
                CP 0Dh                ; CR?
                JR Z,PARSE_CMD
                LD (DE),A
                INC DE
                JR READ_LOOP

PARSE_CMD:
                LD DE,CmdBuf
                LD HL,HelloCmd
                CALL STRCMP
                JR Z,DO_HELLO

                LD DE,UnknownStr
                LD C,9
                CALL BDOS_ENTRY
                JR CCP_START

DO_HELLO:
                LD DE,HelloStr
                LD C,9
                CALL BDOS_ENTRY
                JR CCP_START

; ============================================================
; BDOS (Minimal)
; ============================================================

BDOS_ENTRY:
                LD A,C
                CP 1
                JR Z,BDOS_CONIN
                CP 2
                JR Z,BDOS_CONOUT
                CP 9
                JR Z,BDOS_CONSTR
                RET

BDOS_CONIN:
                CALL J_CONIN
                RET

BDOS_CONOUT:
                LD A,E
                CALL J_CONOUT
                RET

BDOS_CONSTR:
                CALL J_CONSTR
                RET

; ============================================================
; BIOS (Minimal)
; ============================================================

                ORG 0800h

J_CONIN:        JP BIOS_CONIN
J_CONOUT:       JP BIOS_CONOUT
J_CONSTR:       JP BIOS_CONSTR

BIOS_CONIN:
                CALL 0x009F        ; CHGET
                RET

BIOS_CONOUT:
                PUSH AF
                CALL 0x00A2        ; CHPUT
                POP AF
                RET

BIOS_CONSTR:
                LD A,(DE)
                CP '$'
                RET Z
                CALL BIOS_CONOUT
                INC DE
                JR BIOS_CONSTR

; ============================================================
; Utility: STRCMP (DE = input, HL = command)
; SjASMPlus 対応版（(DE) を使わない）
; ============================================================

STRCMP:
        ; DE = input string
        ; HL = command string

CMP_LOOP:
        LD A,(HL)        
        LD C,A           

        LD A,D           
        LD H,A
        LD A,E
        LD L,A

        LD A,(HL)      
        CP C             
        JR NZ,CMP_FAIL

        CP 0             ; 終端？
        JR Z,CMP_OK

        INC HL           ; コマンド側
        INC DE           ; 入力側
        JR CMP_LOOP

CMP_FAIL:
        LD A,1
        RET

CMP_OK:
        XOR A
        RET



; ============================================================
; Data
; ============================================================

PromptStr:      DB 'A>$'
UnknownStr:     DB 'UNKNOWN COMMAND$',0
HelloStr:       DB 'HELLO FROM MSX CPM$',0
HelloCmd:       DB 'HELLO',0
CmdBuf:         DS 32

; ============================================================
; END
; ============================================================
