        ORG 0100h

BDOS    EQU     0005h
C_RAWIO EQU     06h             ; 直接コンソール I/O
C_STROUT EQU    09h             ; 文字列出力 ($で終端)
CALSLT  EQU     001Ch           ; インタースロットコール (IX=呼び出しアドレス, IY=スロットID)
EXPTBL  EQU     0FCC1h          ; メインROMのスロットIDテーブル

; --- ディスクBIOSルーチンのオフセット (スロット内相対アドレス) ---
D_PHYDIO EQU    04000h          ; 物理セクタ I/O
D_DRVTBL EQU    04003h          ; ドライブテーブル取得
D_INIHRD EQU    04006h          ; ハードウェア初期化
D_DRVOFF EQU    04009h          ; モーターオフ
D_DSKCST EQU    0400Ch          ; ディスク変更チェック
VDP_DATA    EQU 0x98       
VDP_ADDR    EQU 0x99        

ENTRY:
        DI                 
        LD   SP, STACK_TOP  

        LD   A, 0x20       
        OUT  (VDP_ADDR), A
        LD   A, 0x87
        OUT  (VDP_ADDR), A


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
        LD   A, 'W'
        CALL PRINT
        LD   A, 'O'
        CALL PRINT
        LD   A, 'R'
        CALL PRINT
        LD   A, 'L'
        CALL PRINT
        LD   A, 'D'
        CALL PRINT

HALT_LOOP:
        EI                  ; 割り込み許可
        HALT                ; CPUを停止して待機
        JR   HALT_LOOP

PRINT:  
        OUT  (VDP_DATA), A
        RET


; --- スタック領域の確保 ---
        DS   64             ; スタック用に64バイト確保
STACK_TOP: