        ORG 0100h

CHPUT       EQU   00A2h     ; 1文字画面出力 (A=文字)
CHGET       EQU   009Fh     ; 1文字キー入力 (待つ。A=文字)
CHSNS       EQU   009Ch     ; キー入力有無チェック (Z=なし)
DSKIO       EQU   0F37Dh    ; ディスクセクタ入出力(BIOS)
INITXT      EQU   006Ch     ; テキストモード(40桁)初期化 (画面クリア含む)

; ---- 独自ファイルシステムのレイアウト定数 ----
VMT_SECTOR  EQU   50        ; ボリューム管理テーブルがある論理セクタ
                             ; (build_disk.py の VMT_SECTOR と必ず一致させること)
VMT_ENTRIES EQU   32        ; 最大ファイル数
VMT_ENTSIZE EQU   16        ; 1エントリのバイト数
VMT_BUFADR  EQU   0F000h    ; VMTをメモリに読み込むバッファ

FILEBUF     EQU   0F400h    ; TYPEコマンドでファイル本文を読むバッファ
                             ; (1セクタ=512バイトずつ処理)

SEC_SIZE    EQU   512

; ---- ワーク領域 ----
LINEBUF     EQU   0FE00h     ; コマンド入力バッファ(64バイト)
LINEBUF_LEN EQU   64
ARGPTR      EQU   0FE40h     ; コマンド名以降の引数開始位置(2バイト)

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
PPI_PORTA EQU 0A8h
PPI_PORTC EQU 0AAh

ENTRY:
        DI                 
        LD   SP, STACK_TOP  

        LD   A, 0xF1       
        OUT  (VDP_ADDR), A
        LD   A, 0x87
        OUT  (VDP_ADDR), A


        LD   A, 0x00       
        OUT  (VDP_ADDR), A
        LD   A, 0x40       
        OUT  (VDP_ADDR), A
        CALL SET_VRAM_ADDR
        
        LD    HL, VER
        CALL  PRINT_STRING

        CALL LB
        CALL LB
        LD    HL, COPYRIGHT
        CALL  PRINT_STRING
        CALL LB
        
        

MAIN_LOOP:
        CALL LB
        LD   A, 'A'
        CALL PRINT
        LD   A, '>'
        CALL PRINT
        CALL LB
        LD   A, ' '
        LD    HL, 80                ; 3行目 (40 * 2行分)
        LD    (VDP_ADDR), HL
        CALL  READLINE
READLINE:
            LD    HL, LINEBUF
            LD    B, 0                  ; 文字数カウンタ
RL_LOOP:
            CALL  GETKEY_DIRECT         
            
            CP    0Dh                   ; Enter?
            JR    Z, RL_DONE
            CP    08h                   ; BackSpace?
            JR    Z, RL_BS
            CP    20h                   ; 制御文字チェック (20h未満は無視)
            JR    C, RL_LOOP

            ; バッファ判定
            LD    C, A
            LD    A, B
            CP    LINEBUF_LEN-1
            JR    NC, RL_LOOP           ; 満杯なら無視

            ; バッファ書き込み
            LD    A, C
            LD    (HL), A
            INC   HL
            INC   B

            ; 画面へ1文字直接出力 & カーソル進める
            CALL  PUTCHAR_DIRECT
            JR    RL_LOOP

PRINT_STRING:
            LD    A, (HL)               ; 文字を取得
            OR    A                     ; 0 (NUL終端) かチェック
            RET   Z                     ; 0 なら終了

            CALL  PRINT        ; 1文字描画 (VRAM_POSが自動で+1される)
            INC   HL                    ; 次の文字へ
            JR    PRINT_STRING

RL_BS:
            LD    A, B
            OR    A
            JR    Z, RL_LOOP            ; 先頭なら無視

            DEC   HL
            DEC   B

            ; 画面のカーソルを1文字戻して空白で消去
            CALL  DEC_CURSOR
            LD    A, ' '
            CALL  PUTCHAR_DIRECT
            CALL  DEC_CURSOR            ; 空白描画で進んだカーソルを再度戻す
            JR    RL_LOOP

RL_DONE:
            LD    (HL), 0               ; NUL終端

            ; 改行処理 (次の行の先頭へ移動)
            ; 現在のVRAMアドレスを 40 で割って1行（40文字）進める
            LD    HL, (VDP_ADDR)
            LD    DE, 40
            ADD   HL, DE
            
            ; 40の倍数（行頭）に切り下げ処理
            ; HL / 40 の端数を計算して引く、または簡易的に行頭計算
            ; ここでは単純に次の行の行頭へセット
            CALL  ALIGN_NEXT_LINE
            JR    RL_RET

RL_RET:
            RET


PUTCHAR_DIRECT:
            PUSH  AF
            PUSH  HL
            LD    HL, (VDP_ADDR)
            CALL PRINT
            ; VRAM_POS を +1
            PUSH  HL
            LD    HL, (VDP_ADDR)
            INC   HL
            LD    (VDP_ADDR), HL
            POP   HL
            RET

; カーソル（VRAM位置）を1文字戻す
DEC_CURSOR:
            PUSH  HL
            LD    HL, (VDP_ADDR)
            DEC   HL
            LD    (VDP_ADDR), HL
            POP   HL
            RET

; 次の行の先頭アドレス（40の倍数）へ整列
ALIGN_NEXT_LINE:
            ; VRAM_POS = (VRAM_POS / 40) * 40
            ; 簡易的に現在の位置を40で割った余りを引いて行頭にし、+40する処理
            PUSH  HL
            PUSH  BC
            LD    HL, (VDP_ADDR)
            
            ; 簡易計算：40で割った余りを求める
            LD    BC, 40
            ; 行頭アドレスへ調整
            ; (実装簡略化のため、開始行を固定化またはループ減算で調整)
            LD    DE, 0
ALIGN_LOOP:
            LD    A, H
            OR    L
            JR    Z, ALIGN_SET
            INC   E
            SBC   HL, BC
            JR    NC, ALIGN_LOOP
            ADD   HL, BC
ALIGN_SET:
            ; E 行目 * 40 を求める
            LD    A, E
            LD    L, 0
            LD    H, 0
            OR    A
            JR    Z, ALIGN_END
ALIGN_MULT:
            ADD   HL, BC
            DEC   A
            JR    NZ, ALIGN_MULT
ALIGN_END:
            LD    (VDP_ADDR), HL
            POP   BC
            POP   HL
            RET


GETKEY_DIRECT:
            ; 1. PPI Port C (0AAh) の下位4bitにマトリクス行番号をセット
            ; 2. PPI Port A (0A8h) から8bitのキー状態を読み込む (0=押されている)
            ; 3. キーリリースを待ってから復調したASCII文字をAに返す
            
            ; (※実用コードではマトリクスとASCIIの変換テーブルが必要です)
            ; 処理簡略化の概念フロー:
WAIT_KEY:
            ; キーマトリクス全スキャン
            ; 押されたキーの行/列から ASCII コードを割り出し
            ; 押しっぱなし防止のウェイト処理
            ; LD A, [変換されたASCII]
            ; RET
            
            ; ※完全自作する場合はマトリクス走査+チャタリング防止+ASCIIコード変換表が必要です。
            RET

; --- ワークエリア ---
VRAM_POS:    DW    0x0050               ; 画面描画のVRAM書き込み位置
LINEBUF:     DS    64
LINEBUF_LEN  EQU   64

; =========================================================
; VRAM書き込みアドレス設定
; VRAM_POS の値を VDP (0x99) へ出力します
; =========================================================
SET_VRAM_ADDR:
        PUSH AF
        PUSH HL
        LD   HL, (VRAM_POS)
        LD   A, L
        OUT  (VDP_ADDR), A      ; 下位8ビットを出力
        LD   A, H
        OR   40h                ; 書き込みモード指定 (bit 6 = 1)
        OUT  (VDP_ADDR), A      ; 上位8ビットを出力
        POP  HL
        POP  AF
        RET

HALT_LOOP:
        EI                  ; 割り込み許可
        HALT                ; CPUを停止して待機
        JR   HALT_LOOP

PRINT:
        PUSH HL
        OUT  (VDP_DATA), A      ; VRAMへ文字書き込み

        ; VRAM_POS を +1 してワーク領域を更新
        LD   HL, (VRAM_POS)
        INC  HL
        LD   (VRAM_POS), HL
        POP  HL
        RET

; =========================================================
; 改行サブルーチン (LB) - エラー修正版
; 現在の VRAM_POS を次の行の先頭（40の倍数）へ進めます
; Destroy: なし
; =========================================================
; =========================================================
; 改行サブルーチン (LB)
; =========================================================
LB:
        PUSH AF
        PUSH BC
        PUSH DE
        PUSH HL

        ; --- 1. 現在の 40 で割った余りを計算 ---
        LD   HL, (VRAM_POS)
        LD   BC, 40
        LD   DE, 0
LB_DIV_LOOP:
        LD   A, H
        OR   L
        JR   Z, LB_ALIGN_DONE
        OR   A                  ; キャリークリア
        SBC  HL, BC
        JR   C, LB_DIV_UNDER
        INC  DE
        JR   LB_DIV_LOOP

LB_DIV_UNDER:
        ADD  HL, BC             ; HL = 余り (列位置)

LB_ALIGN_DONE:
        ; --- 2. 次の行頭アドレスを計算 (VRAM_POS - 余り + 40) ---
        LD   E, L
        LD   D, H
        LD   HL, (VRAM_POS)
        OR   A
        SBC  HL, DE             ; 現在行の先頭
        ADD  HL, BC             ; 次の行の先頭 (+40)

        ; --- 3. 画面最下段 (960バイト) チェック ---
        LD   DE, 960
        OR   A
        SBC  HL, DE
        JR   C, LB_NOT_OVER
        LD   HL, 0              ; 溢れたら最上段へ
        JR   LB_SET_POS

LB_NOT_OVER:
        ADD  HL, DE             ; 位置を戻す

LB_SET_POS:
        LD   (VRAM_POS), HL     ; ワーク領域を更新

        ; --- 4. VDPへ新しい書き込みVRAMアドレスを設定 ---
        CALL SET_VRAM_ADDR

        POP  HL
        POP  DE
        POP  BC
        POP  AF
        RET

VER:     DB    "MSX-CPM v0.1", 0
COPYRIGHT:     DB    "Copyright 2026 by keita", 0

        DS   64             ; スタック用に64バイト確保
STACK_TOP: