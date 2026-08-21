        ORG 0100h


VDP_DATA    EQU 0x98       
VDP_ADDR    EQU 0x99        

ENTRY:
        DI                 
        LD   SP, STACK_TOP  

        LD   A, 0x20        ; 文字色:7(黄), 背景色:0(黒)
        OUT  (VDP_ADDR), A
        LD   A, 0x87
        OUT  (VDP_ADDR), A

        ; ----------------------------------------------------
        ; 2. VRAMの書き込み開始アドレスを設定 (Text Mode: 0x0000)
        ; ----------------------------------------------------
        LD   A, 0x00        ; アドレス下位 8bit
        OUT  (VDP_ADDR), A
        LD   A, 0x40        ; アドレス上位 6bit + 書き込みモード (Bit 6を立てる)
        OUT  (VDP_ADDR), A

        
        LD   A, 'O'
        OUT  (VDP_DATA), A   
        LD   A, 'H'
        OUT  (VDP_DATA), A
        LD   A, 'A'
        OUT  (VDP_DATA), A
        LD   A, 'I'
        OUT  (VDP_DATA), A   
        LD   A, 'O'
        OUT  (VDP_DATA), A


HALT_LOOP:
        EI                  ; 割り込み許可
        HALT                ; CPUを停止して待機
        JR   HALT_LOOP

; --- スタック領域の確保 ---
        DS   64             ; スタック用に64バイト確保
STACK_TOP: