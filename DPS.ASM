; =========================================================
;  MSXDOS.SYS  --  独自ミニOS 本体
;
;  ファイル名は「MSXDOS.SYS」だが、中身は本物のMSX-DOSとは
;  無関係の独自実装(互換性なし)。
;
;  BOOT.ASM によってディスクから 0xD000 番地に読み込まれ、
;  ここへジャンプしてくる想定。
;
;  提供する機能:
;    ・起動メッセージ表示
;    ・簡易コマンドラインシェル (プロンプト "A>")
;    ・内蔵コマンド: DIR, TYPE, CLS, VER, HELP, (空Enter無視)
;    ・独自の超簡易ファイルシステム
;        - 論理セクタ 2 に「ボリューム管理テーブル(VMT)」を1つ配置
;        - VMTは固定長16バイトエントリ×任意個
;            +0  ファイル名 (8バイト, 空白パディング, 未使用エントリは先頭0)
;            +8  拡張子     (3バイト, 空白パディング)
;            +11 属性       (1バイト, 未使用)
;            +12 開始セクタ (2バイト, リトルエンディアン)
;            +14 セクタ数   (2バイト, リトルエンディアン)
;        - ファイルは連続セクタとして保存(断片化なし、
;          クラスタチェインなし)
;        - ディレクトリ階層なし(ルートのみ)
; =========================================================

            ORG   0100h

; ---- MSX標準BIOSコールベクタ ----
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

; =========================================================
;  エントリポイント
; =========================================================
START:
            DI
            LD    SP,0FF00h        ; 十分に余裕を見たスタック位置

            CALL  INITXT           ; 画面初期化(40桁テキストモード)

            LD    HL,MSG_TITLE
            CALL  PRINT
            EI

; ---------------------------------------------------------
; メインループ: プロンプト -> 1行入力 -> コマンド解釈 -> 実行
; ---------------------------------------------------------
MAIN_LOOP:
            LD    HL,MSG_PROMPT
            CALL  PRINT

            CALL  READLINE          ; LINEBUFに1行読み込む(0終端)

            LD    HL,LINEBUF
            CALL  SKIPSPACE
            LD    A,(HL)
            OR    A
            JR    Z,MAIN_LOOP       ; 空行なら何もせず再表示

            CALL  DISPATCH
            JR    MAIN_LOOP

; =========================================================
;  READLINE : 1行入力してLINEBUFへ0終端で格納。BackSpace対応。
;  Enter(0Dh)で確定。
; =========================================================
READLINE:
            LD    HL,LINEBUF
            LD    B,0                ; 現在の文字数
RL_LOOP:
            CALL  CHGET
            CP    0Dh                 ; Enter?
            JR    Z,RL_DONE
            CP    08h                 ; BackSpace?
            JR    Z,RL_BS
            CP    20h                 ; 制御文字は無視(表示可能文字のみ)
            JR    C,RL_LOOP
            LD    C,A
            LD    A,B
            CP    LINEBUF_LEN-1
            JR    NC,RL_LOOP          ; バッファ満杯なら無視
            LD    A,C
            LD    (HL),A
            INC   HL
            INC   B
            CALL  CHPUT                ; エコー表示
            JR    RL_LOOP
RL_BS:
            LD    A,B
            OR    A
            JR    Z,RL_LOOP            ; 先頭では無視
            DEC   HL
            DEC   B
            LD    A,08h
            CALL  CHPUT
            LD    A,' '
            CALL  CHPUT
            LD    A,08h
            CALL  CHPUT
            JR    RL_LOOP
RL_DONE:
            LD    (HL),0                ; 0終端
            LD    A,13
            CALL  CHPUT
            LD    A,10
            CALL  CHPUT
            RET

; =========================================================
;  DISPATCH : LINEBUF先頭のコマンド名を見て対応処理へ飛ぶ
; =========================================================
DISPATCH:
            LD    HL,LINEBUF
            LD    DE,CMD_DIR
            CALL  STRCMP_TOKEN
            JP    Z,CMD_DIR_EXEC

            LD    HL,LINEBUF
            LD    DE,CMD_TYPE
            CALL  STRCMP_TOKEN
            JP    Z,CMD_TYPE_EXEC

            LD    HL,LINEBUF
            LD    DE,CMD_CLS
            CALL  STRCMP_TOKEN
            JP    Z,CMD_CLS_EXEC

            LD    HL,LINEBUF
            LD    DE,CMD_VER
            CALL  STRCMP_TOKEN
            JP    Z,CMD_VER_EXEC

            LD    HL,LINEBUF
            LD    DE,CMD_HELP
            CALL  STRCMP_TOKEN
            JP    Z,CMD_HELP_EXEC

            ; 該当なし
            LD    HL,MSG_UNKNOWN
            CALL  PRINT
            RET

; ---------------------------------------------------------
; STRCMP_TOKEN : HLの先頭トークン(区切りは空白か0)が
;                DEの0終端文字列と一致するか(大小区別なし)
;                一致すればZ=1、HLはトークン直後(空白 or 0)を指す
; ---------------------------------------------------------
STRCMP_TOKEN:
            PUSH  HL
            PUSH  DE
STC_LOOP:
            LD    A,(DE)
            OR    A
            JR    Z,STC_ENDCHK
            LD    C,A
            LD    A,(HL)
            CALL  TOUPPER
            LD    B,A
            LD    A,C
            CALL  TOUPPER
            CP    B
            JR    NZ,STC_FAIL
            INC   HL
            INC   DE
            JR    STC_LOOP
STC_ENDCHK:
            LD    A,(HL)
            OR    A
            JR    Z,STC_OK
            CP    ' '
            JR    Z,STC_OK
STC_FAIL:
            POP   DE
            POP   HL
            OR    1                 ; Z解除
            RET
STC_OK:
            POP   DE
            POP   HL
            ; HLをトークン終端(空白 or 0)まで進める
STC_FINDEND:
            LD    A,(HL)
            OR    A
            JR    Z,STC_RETZ
            CP    ' '
            JR    Z,STC_RETZ
            INC   HL
            JR    STC_FINDEND
STC_RETZ:
            XOR   A                 ; Z=1を確定させて返す(呼び出し元がJP/JR Zで判定)
            RET

TOUPPER:
            CP    'a'
            RET   C
            CP    'z'+1
            RET   NC
            SUB   20h
            RET

SKIPSPACE:
            LD    A,(HL)
            CP    ' '
            RET   NZ
            INC   HL
            JR    SKIPSPACE

; =========================================================
;  各コマンド実装
; =========================================================

; ---------------------------------------------------------
; CLS : 画面クリア
; ---------------------------------------------------------
CMD_CLS_EXEC:
            CALL  INITXT
            RET

; ---------------------------------------------------------
; VER : バージョン表示
; ---------------------------------------------------------
CMD_VER_EXEC:
            LD    HL,MSG_VER
            CALL  PRINT
            RET

; ---------------------------------------------------------
; HELP : コマンド一覧表示
; ---------------------------------------------------------
CMD_HELP_EXEC:
            LD    HL,MSG_HELP
            CALL  PRINT
            RET

; ---------------------------------------------------------
; DIR : VMTを読み込み、有効なファイル一覧を表示
; ---------------------------------------------------------
CMD_DIR_EXEC:
            CALL  LOAD_VMT
            JR    C,DIR_IOERR

            LD    HL,MSG_DIRHDR
            CALL  PRINT

            LD    IX,VMT_BUFADR
            LD    B,VMT_ENTRIES
            LD    C,0               ; 表示件数カウンタ
DIR_LOOP:
            LD    A,(IX+0)
            OR    A
            JR    Z,DIR_SKIP        ; 名前先頭0=未使用エントリ

            ; ファイル名8バイト表示
            PUSH  BC
            PUSH  IX
            LD    B,8
DIR_NAME:
            LD    A,(IX+0)
            CALL  CHPUT
            INC   IX
            DJNZ  DIR_NAME
            LD    A,'.'
            CALL  CHPUT
            LD    B,3
DIR_EXT:
            LD    A,(IX+0)
            CALL  CHPUT
            INC   IX
            DJNZ  DIR_EXT
            POP   IX
            POP   BC

            LD    A,' '
            CALL  CHPUT
            CALL  CHPUT

            ; セクタ数を表示(簡易10進数、最大3桁想定)
            LD    L,(IX+14)
            LD    H,(IX+15)
            CALL  PRINT_DEC16
            LD    HL,MSG_SECTORS
            CALL  PRINT

            INC   C
DIR_SKIP:
            LD    DE,VMT_ENTSIZE
            ADD   IX,DE
            DJNZ  DIR_LOOP

            LD    A,C
            OR    A
            JR    NZ,DIR_DONE
            LD    HL,MSG_NOFILES
            CALL  PRINT
DIR_DONE:
            RET

DIR_IOERR:
            LD    HL,MSG_DISKERR
            CALL  PRINT
            RET

; ---------------------------------------------------------
; TYPE <filename.ext> : ファイル本文をテキスト表示
; ---------------------------------------------------------
CMD_TYPE_EXEC:
            ; LINEBUF先頭の"TYPE"トークンをスキップして
            ; 引数(ファイル名)開始位置を得る
            LD    HL,LINEBUF
            LD    DE,CMD_TYPE
            CALL  STRCMP_TOKEN      ; HLはトークン直後を指す(呼び出し前提でZのはず)
            CALL  SKIPSPACE

            LD    A,(HL)
            OR    A
            JR    NZ,TYPE_HAVEARG
            LD    HL,MSG_USAGE_TYPE
            CALL  PRINT
            RET

TYPE_HAVEARG:
            ; ファイル名(8.3形式)をパースして8+3バイトの
            ; 検索用バッファ(空白パディング)に変換
            CALL  PARSE_FILENAME     ; HL(入力)->NAMEBUF(11バイト)

            CALL  LOAD_VMT
            JR    C,TYPE_IOERR

            CALL  FIND_FILE          ; NAMEBUFで検索。見つかればIX=エントリ, NC
            JR    C,TYPE_NOTFOUND

            ; IXのエントリから開始セクタ・セクタ数を取得
            LD    E,(IX+12)
            LD    D,(IX+13)          ; DE = 開始セクタ
            LD    L,(IX+14)
            LD    H,(IX+15)          ; HL = セクタ数
            LD    (TYPE_REMAIN),HL
            LD    (TYPE_CURSEC),DE

TYPE_SECLOOP:
            LD    HL,(TYPE_REMAIN)
            LD    A,H
            OR    L
            JR    Z,TYPE_DONE

            XOR   A                  ; ドライブA、読み込み
            LD    B,1                ; 1セクタずつ
            LD    DE,(TYPE_CURSEC)
            LD    HL,FILEBUF
            CALL  DSKIO
            JR    C,TYPE_IOERR

            ; FILEBUF中の512バイトを、0(終端マーカー)が
            ; 出るまで、または512バイト分、画面へ出力
            LD    HL,FILEBUF
            LD    B,0                 ; 256回ループx2で512バイト回すためBCで管理
            LD    C,0
TYPE_OUT:
            LD    A,(HL)
            OR    A
            JR    Z,TYPE_DONE          ; ファイル終端マーカー(0バイト)で打ち切り
            CALL  CHPUT
            INC   HL
            INC   BC
            LD    A,B
            CP    2
            JR    NZ,TYPE_OUT
            LD    A,C
            CP    0
            JR    NZ,TYPE_OUT
            ; 512バイト出力し終えた

            LD    HL,(TYPE_CURSEC)
            INC   HL
            LD    (TYPE_CURSEC),HL
            LD    HL,(TYPE_REMAIN)
            DEC   HL
            LD    (TYPE_REMAIN),HL
            JR    TYPE_SECLOOP

TYPE_DONE:
            LD    A,13
            CALL  CHPUT
            LD    A,10
            CALL  CHPUT
            RET

TYPE_NOTFOUND:
            LD    HL,MSG_NOTFOUND
            CALL  PRINT
            RET

TYPE_IOERR:
            LD    HL,MSG_DISKERR
            CALL  PRINT
            RET

TYPE_REMAIN: DW   0
TYPE_CURSEC: DW   0

; =========================================================
;  ファイルシステム補助ルーチン
; =========================================================

; ---------------------------------------------------------
; LOAD_VMT : 論理セクタVMT_SECTORをVMT_BUFADRへ読み込む
;            Carry=1でエラー
; ---------------------------------------------------------
LOAD_VMT:
            XOR   A
            LD    B,1
            LD    DE,VMT_SECTOR
            LD    HL,VMT_BUFADR
            CALL  DSKIO
            RET

; ---------------------------------------------------------
; PARSE_FILENAME : HLが指す文字列(空白or0終端の1トークン)を
;   "NAME.EXT" として解釈し、NAMEBUF(11バイト、空白埋め)に格納
; ---------------------------------------------------------
PARSE_FILENAME:
            PUSH  HL
            LD    DE,NAMEBUF
            LD    B,11
PF_CLEAR:
            LD    A,' '
            LD    (DE),A
            INC   DE
            DJNZ  PF_CLEAR
            POP   HL

            LD    DE,NAMEBUF
            LD    B,8                ; 名前部 最大8文字
PF_NAME:
            LD    A,(HL)
            OR    A
            RET   Z
            CP    ' '
            RET   Z
            CP    '.'
            JR    Z,PF_EXTSTART
            CALL  TOUPPER
            LD    (DE),A
            INC   HL
            INC   DE
            DJNZ  PF_NAME
            ; 8文字使い切ったら'.'まで読み飛ばす
PF_SKIPTOEXT:
            LD    A,(HL)
            OR    A
            RET   Z
            CP    ' '
            RET   Z
            CP    '.'
            JR    Z,PF_EXTSTART
            INC   HL
            JR    PF_SKIPTOEXT

PF_EXTSTART:
            INC   HL                 ; '.'を読み飛ばす
            LD    DE,NAMEBUF+8
            LD    B,3
PF_EXT:
            LD    A,(HL)
            OR    A
            RET   Z
            CP    ' '
            RET   Z
            CALL  TOUPPER
            LD    (DE),A
            INC   HL
            INC   DE
            DJNZ  PF_EXT
            RET

NAMEBUF:    DS    11

; ---------------------------------------------------------
; FIND_FILE : NAMEBUF(11バイト)とVMT_BUFADR上の各エントリを
;   比較し、一致すればIX=そのエントリ先頭、Carry=0
;   見つからなければ Carry=1
; ---------------------------------------------------------
FIND_FILE:
            LD    IX,VMT_BUFADR
            LD    B,VMT_ENTRIES
FF_LOOP:
            LD    A,(IX+0)
            OR    A
            JR    Z,FF_NEXT

            PUSH  BC
            LD    HL,NAMEBUF
            PUSH  IX
            POP   DE                  ; DE = エントリ先頭アドレス
            LD    B,11
FF_CMP:
            LD    A,(DE)
            CP    (HL)
            JR    NZ,FF_CMPFAIL
            INC   HL
            INC   DE
            DJNZ  FF_CMP
            POP   BC
            OR    A                   ; Carry=0
            RET
FF_CMPFAIL:
            POP   BC
FF_NEXT:
            LD    DE,VMT_ENTSIZE
            ADD   IX,DE
            DJNZ  FF_LOOP
            SCF                        ; 見つからなかった
            RET

; =========================================================
;  汎用ユーティリティ
; =========================================================

; ---------------------------------------------------------
; PRINT : HLの指す0終端文字列を表示 (CR,LFはそのまま出力)
; ---------------------------------------------------------
PRINT:
            LD    A,(HL)
            OR    A
            RET   Z
            CALL  CHPUT
            INC   HL
            JR    PRINT

; ---------------------------------------------------------
; PRINT_DEC16 : HLの16bit値を10進数で表示(先頭ゼロ抑制)
; ---------------------------------------------------------
PRINT_DEC16:
            LD    DE,10000
            CALL  PD_DIGIT
            LD    DE,1000
            CALL  PD_DIGIT
            LD    DE,100
            CALL  PD_DIGIT
            LD    DE,10
            CALL  PD_DIGIT
            LD    A,L
            ADD   A,'0'
            CALL  CHPUT
            RET

PD_DIGIT:
            XOR   A
PD_SUB:
            OR    A
            SBC   HL,DE
            JR    C,PD_SUBBACK
            INC   A
            JR    PD_SUB
PD_SUBBACK:
            ADD   HL,DE
            OR    A
            JR    Z,PD_ZERO_CHECK
            ADD   A,'0'
            CALL  CHPUT
            RET
PD_ZERO_CHECK:
            RET

; =========================================================
;  文字列定数
; =========================================================
CMD_DIR:    DB    "DIR",0
CMD_TYPE:   DB    "TYPE",0
CMD_CLS:    DB    "CLS",0
CMD_VER:    DB    "VER",0
CMD_HELP:   DB    "HELP",0

MSG_TITLE:  DB    "MSXDOS.SYS - Minimal Original DOS  Ver 0.1",13,10
            DB    "(This is NOT compatible with real MSX-DOS)",13,10,13,10,0

MSG_PROMPT: DB    "A>",0

MSG_VER:    DB    "MSXDOS.SYS Minimal Edition  Ver 0.1",13,10,0

MSG_HELP:   DB    "Commands: DIR  TYPE <file>  CLS  VER  HELP",13,10,0

MSG_DIRHDR: DB    "Directory:",13,10,0

MSG_SECTORS: DB   " sector(s)",13,10,0

MSG_NOFILES: DB   "No files.",13,10,0

MSG_NOTFOUND: DB  "File not found.",13,10,0

MSG_DISKERR: DB   "Disk I/O error.",13,10,0

MSG_UNKNOWN: DB   "Unknown command. Type HELP.",13,10,0

MSG_USAGE_TYPE: DB "Usage: TYPE <filename.ext>",13,10,0

            END   START