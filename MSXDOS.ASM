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
        EI
        LD    A, 92h
        OUT   (0ABh), A
        
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
        CALL  LB                  ; 改行
        LD    A, 'A'
        CALL  PRINT
        LD    A, '>'
        CALL  PRINT              ; プロンプト "A>" 表示

        CALL  READLINE           ; 1行入力処理を呼び出し

        ; --- ここに入力結果 (LINEBUF) の解析処理を記述 ---

        JR    MAIN_LOOP          ; 再びメインループの先頭へ戻る


; =========================================================
; 1行入力サブルーチン (READLINE)
; 入力: なし
; 出力: LINEBUF にNUL終端文字列が格納される
; =========================================================
READLINE:
        PUSH  AF
        PUSH  BC
        PUSH  DE
        PUSH  HL

        LD    HL, LINEBUF
        LD    B, 0               ; 文字数カウンタ

RL_LOOP:
        CALL  GETKEY_DIRECT      ; 1文字入力待ち (キーが押されるまでここでブロック)
        OR    A                  ; 0チェック
        JR    Z, RL_LOOP         ; 何も取得できなければ再試行

        CP    0Dh                ; Enterキー?
        JR    Z, RL_DONE

        CP    08h                ; BackSpaceキー?
        JR    Z, RL_BS

        CP    20h                ; 制御文字チェック (スペース未満は無視)
        JR    C, RL_LOOP

        ; --- バッファ溢れチェック ---
        LD    C, A
        LD    A, B
        CP    LINEBUF_LEN - 1
        JR    NC, RL_LOOP        ; 満杯なら無視

        ; --- バッファへ格納 & 画面表示 ---
        LD    A, C
        LD    (HL), A            ; バッファに書き込み
        INC   HL
        INC   B                  ; カウンタ +1

        CALL  PRINT              ; 画面へ1文字描画 (VRAM_POS更新含む)
        JR    RL_LOOP

RL_BS:
        ; --- バックスペース処理 ---
        LD    A, B
        OR    A
        JR    Z, RL_LOOP         ; 先頭なら無視

        DEC   HL
        DEC   B

        ; カーソルを1文字戻して空白で上書き
        CALL  DEC_CURSOR
        LD    A, ' '
        CALL  PRINT
        CALL  DEC_CURSOR
        JR    RL_LOOP

RL_DONE:
        LD    (HL), 0            ; NUL終端

        CALL  LB                 ; 入力完了後に改行

        POP   HL
        POP   DE
        POP   BC
        POP   AF
        RET


; =========================================================
; カーソル位置を1文字戻す (DEC_CURSOR)
; =========================================================
DEC_CURSOR:
        PUSH  HL
        LD    HL, (VRAM_POS)
        LD    A, H
        OR    L
        JR    Z, DC_END          ; 0なら戻さない
        DEC   HL
        LD    (VRAM_POS), HL
        CALL  SET_VRAM_ADDR      ; VDPへアドレス送信
DC_END:
        POP   HL
        RET
RL_RET:
            RET


PRINT_STRING:
            LD    A, (HL)               ; 文字を取得
            OR    A                     ; 0 (NUL終端) かチェック
            RET   Z                     ; 0 なら終了

            CALL  PRINT        ; 1文字描画 (VRAM_POSが自動で+1される)
            INC   HL                    ; 次の文字へ
            JR    PRINT_STRING
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

; =========================================================
; キー入力 動作確認用デバッグループ
; =========================================================
KEY_TEST:
        ; 画面に '?' を出して入力待ち状態であることを示す
        LD    A, '?'
        CALL  PRINT

KT_LOOP:
        CALL  GETKEY_DIRECT      ; キー入力を待つ
        
        ; 押されたキーのASCIIコードをそのまま描画
        ; (入力が成功していれば、押した文字が画面に出力されます)
        CALL  PRINT
        
        JR    KT_LOOP            ; 画面出力したら次の入力待ちへ
; PPI Portアドレス (MSX標準)
PPI_PORTA   EQU 0A8h    ; キー入力 (8ビット)
PPI_PORTC   EQU 0AAh    ; キー行選択 (Bit 0-3)

GETKEY_DIRECT:
        ; --- 1. キーが押されるまで待機 ---
GK_WAIT_PRESS:
        CALL    SCAN_KEYBOARD_HARD
        OR      A
        JR      Z, GK_WAIT_PRESS    ; 0なら押されていない

        PUSH    AF                  ; キーコードを保存

        ; --- 2. チャタリング防止ウェイト ---
        LD      BC, 1000
GK_DEBOUNCE:
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, GK_DEBOUNCE

        ; --- 3. キーが離されるまで待機 ---
GK_WAIT_RELEASE:
        CALL    SCAN_KEYBOARD_HARD
        OR      A
        JR      NZ, GK_WAIT_RELEASE

        POP     AF                  ; ASCIIコードを復元
        RET

; =========================================================
; キーマトリクス・スキャン
; 出力: A = ASCIIコード (未入力時は 0)
; =========================================================
SCAN_KEYBOARD_HARD:
        LD      C, 0                ; 行0からスタート
SKH_LOOP:
        CALL    READ_PPI_DIRECT
        CPL                         ; 押されたビットを1にする (0=押された -> 1=押された)
        OR      A
        JR      NZ, SKH_FOUND       ; 何か押されていれば解析へ

        INC     C
        LD      A, C
        CP      9                   ; 行0〜8までスキャン (必要に応じて拡張可)
        JR      C, SKH_LOOP

        XOR     A                   ; 何も押されていない
        RET

; キーが検出された場合の変換処理
SKH_FOUND:
        ; C = 行番号 (0-8), A = ビットパターン (1の位が押されたビット)
        LD      B, 0
SKH_BIT_SEARCH:
        RRCA                        ; 右シフトしてキャリーフラグへ
        JR      C, SKH_MATCH
        INC     B                   ; ビット位置 (0-7)
        JR      SKH_BIT_SEARCH

SKH_MATCH:
        ; 行(C) と ビット位置(B) からテーブルオフセットを計算
        ; オフセット = (行 * 8) + ビット位置
        LD      A, C
        ADD     A, A                ; * 2
        ADD     A, A                ; * 4
        ADD     A, A                ; * 8
        ADD     A, B                ; + ビット位置

        LD      E, A
        LD      D, 0
        LD      HL, KEY_MAPTABLE
        ADD     HL, DE
        LD      A, (HL)             ; テーブルからASCIIコードを取得
        RET

; =========================================================
; PPI直接読み出し
; 入力: C = 行番号 (0〜11)
; 出力: A = Port A データ
; =========================================================
READ_PPI_DIRECT:
        IN      A, (PPI_PORTC)
        AND     0F0h                ; 上位4ビットを維持
        OR      C                   ; 下位4ビットに行番号をセット
        OUT     (PPI_PORTC), A

        ; 応答遅延 (ウェイト)
        EX      (SP), HL
        EX      (SP), HL

        IN      A, (PPI_PORTA)      ; 押されたキーデータの取得
        RET

; =========================================================
; MSX標準キーマトリクス ASCII変換テーブル (行0〜行8)
; =========================================================
KEY_MAPTABLE:
    ; 行 0: 7, 6, 5, 4, 3, 2, 1, 0
    DB '7', '6', '5', '4', '3', '2', '1', '0'
    ; 行 1: ;, ], [, \, =, -, 9, 8
    DB ';', ']', '[', '\', '=', '-', '9', '8'
    ; 行 2: B, A,  ,  ,  , ., ,, `
    DB 'B', 'A',  0,  0,  0, '.', ',', '`'
    ; 行 3: J, I, H, G, F, E, D, C
    DB 'J', 'I', 'H', 'G', 'F', 'E', 'D', 'C'
    ; 行 4: R, Q, P, O, N, M, L, K
    DB 'R', 'Q', 'P', 'O', 'N', 'M', 'L', 'K'
    ; 行 5: Z, Y, X, W, V, U, T, S
    DB 'Z', 'Y', 'X', 'W', 'V', 'U', 'T', 'S'
    ; 行 6: F3, F2, F1, CODE, CAPS, GRAPH, CTRL, SHIFT
    DB  0,   0,   0,    0,    0,     0,    0,     0
    ; 行 7: RET, SELECT, BS, STOP, TAB, ESC, RIGHT, DOWN
    DB 0Dh,      0, 08h,    0,   0,   0,     0,    0
    ; 行 8: SPACE, HOME, INS, DEL, LEFT, UP, (NumPad...), ...
    DB ' ',      0,   0,   0,    0,    0,   0,    0
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