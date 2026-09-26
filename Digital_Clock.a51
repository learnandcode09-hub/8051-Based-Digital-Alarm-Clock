; ============================================================
; AT89S52 DIGITAL ALARM CLOCK WITH TM1637 DISPLAY
; Crystal frequency: 11.0592 MHz
;
; CONNECTIONS
; ------------------------------------------------------------
; TM1637 CLK       -> P1.0
; TM1637 DIO       -> P1.1
;
; SET push-button  -> P3.2  (other terminal to GND)
; UP push-button   -> P3.3  (other terminal to GND)
; ALARM button     -> P3.4  (other terminal to GND)
;
; Active buzzer    -> P3.5  (other terminal to GND)
; Use a transistor driver if your buzzer needs more current.
;
; BUTTON OPERATION
; ------------------------------------------------------------
; SET once         : Set clock hour
; SET twice        : Set clock minute
; SET three times  : Set alarm hour
; SET four times   : Set alarm minute
; SET five times   : Return to normal clock display
;
; UP               : Increase the selected value
; ALARM            : Enable/disable alarm
; ALARM while ring : Silence buzzer
; ============================================================

CLK             BIT     P1.0
DIO             BIT     P1.1

SET_KEY         BIT     P3.2
UP_KEY          BIT     P3.3
ALARM_KEY       BIT     P3.4
BUZZER          BIT     P3.5

; ------------------------------------------------------------
; RAM LOCATIONS
; ------------------------------------------------------------
SEC             EQU     30H
MINUTE          EQU     31H
HOUR            EQU     32H
TICK50          EQU     33H

AL_HOUR         EQU     34H
AL_MINUTE       EQU     35H
ALARM_EN        EQU     36H
SET_MODE        EQU     37H
RINGING         EQU     38H
ALARM_LATCH     EQU     39H
BEEP_TICK       EQU     3AH

DISP_HOUR       EQU     3BH
DISP_MINUTE     EQU     3CH
DISP_SEC        EQU     3DH

; SET_MODE values:
; 00H = Normal display
; 01H = Set clock hour
; 02H = Set clock minute
; 03H = Set alarm hour
; 04H = Set alarm minute


; ============================================================
; RESET VECTOR
; ============================================================
                ORG     0000H
                LJMP    MAIN


; ============================================================
; TIMER 0 INTERRUPT VECTOR
; ============================================================
                ORG     000BH
                LJMP    TIMER0_ISR


; ============================================================
; MAIN PROGRAM
; ============================================================
                ORG     0030H

MAIN:
                MOV     SP,#5FH

; Initial clock time: 12:00:00
; Change these values if required.
                MOV     HOUR,#12D
                MOV     MINUTE,#00D
                MOV     SEC,#00D

; Initial alarm time: 06:30
                MOV     AL_HOUR,#06D
                MOV     AL_MINUTE,#30D

                MOV     TICK50,#00D
                MOV     ALARM_EN,#00H
                MOV     SET_MODE,#00H
                MOV     RINGING,#00H
                MOV     ALARM_LATCH,#00H
                MOV     BEEP_TICK,#00H

; Buttons are active LOW.
                SETB    SET_KEY
                SETB    UP_KEY
                SETB    ALARM_KEY

                CLR     BUZZER

; TM1637 idle state
                SETB    CLK
                SETB    DIO

; Timer 0 mode 1, 16-bit timer
; 4C00H gives 50 ms at 11.0592 MHz crystal.
                MOV     TMOD,#01H
                MOV     TH0,#4CH
                MOV     TL0,#00H
                CLR     TF0
                SETB    TR0

; Enable Timer 0 interrupt and global interrupt
                MOV     IE,#82H

                ACALL   TM_INIT

MAIN_LOOP:
                ACALL   CHECK_KEYS
                ACALL   CHECK_ALARM
                ACALL   SHOW_DISPLAY
                SJMP    MAIN_LOOP


; ============================================================
; TIMER 0 INTERRUPT
; Runs every 50 ms.
; 20 interrupts = 1 second.
; ============================================================
TIMER0_ISR:
                PUSH    ACC
                PUSH    PSW

                MOV     TH0,#4CH
                MOV     TL0,#00H

; Buzzer pattern:
; 0.5 second ON, 0.5 second OFF
                MOV     A,RINGING
                JZ      BUZZER_OFF

                INC     BEEP_TICK
                MOV     A,BEEP_TICK
                CJNE    A,#10D,CLOCK_TICK

                MOV     BEEP_TICK,#00H
                CPL     BUZZER
                SJMP    CLOCK_TICK

BUZZER_OFF:
                CLR     BUZZER
                MOV     BEEP_TICK,#00H

CLOCK_TICK:
                INC     TICK50
                MOV     A,TICK50
                CJNE    A,#20D,TIMER_EXIT

; One second completed
                MOV     TICK50,#00H
                INC     SEC

                MOV     A,SEC
                CJNE    A,#60D,TIMER_EXIT

                MOV     SEC,#00D
                INC     MINUTE

                MOV     A,MINUTE
                CJNE    A,#60D,TIMER_EXIT

                MOV     MINUTE,#00D
                INC     HOUR

                MOV     A,HOUR
                CJNE    A,#24D,TIMER_EXIT

                MOV     HOUR,#00D

TIMER_EXIT:
                POP     PSW
                POP     ACC
                RETI


; ============================================================
; ALARM CHECK
; Alarm triggers exactly when HH:MM:00 matches alarm time.
; ============================================================
CHECK_ALARM:
                MOV     A,ALARM_EN
                JNZ     ALARM_IS_ENABLED

                MOV     RINGING,#00H
                MOV     ALARM_LATCH,#00H
                CLR     BUZZER
                RET

ALARM_IS_ENABLED:
                MOV     A,HOUR
                CJNE    A,AL_HOUR,NOT_ALARM_TIME

                MOV     A,MINUTE
                CJNE    A,AL_MINUTE,NOT_ALARM_TIME

; Trigger only at second 00.
                MOV     A,SEC
                JNZ     ALARM_DONE

; Prevent multiple triggers at the same alarm time.
                MOV     A,ALARM_LATCH
                JNZ     ALARM_DONE

                MOV     ALARM_LATCH,#01H
                MOV     RINGING,#01H
                MOV     BEEP_TICK,#00H
                SETB    BUZZER
                RET

NOT_ALARM_TIME:
                MOV     ALARM_LATCH,#00H

ALARM_DONE:
                RET


; ============================================================
; BUTTON HANDLING
; ============================================================
CHECK_KEYS:
                JNB     ALARM_KEY,ALARM_PRESSED
                JNB     SET_KEY,SET_PRESSED
                JNB     UP_KEY,UP_PRESSED
                RET


; ALARM button:
; - Normal: enable or disable alarm
; - Ringing: silence the buzzer
ALARM_PRESSED:
                ACALL   DEBOUNCE
                JB      ALARM_KEY,KEY_DONE

                MOV     A,RINGING
                JZ      TOGGLE_ALARM

; Silence ringing alarm.
                MOV     RINGING,#00H
                CLR     BUZZER
                ACALL   WAIT_ALARM_RELEASE
                RET

TOGGLE_ALARM:
                MOV     A,ALARM_EN
                XRL     A,#01H
                MOV     ALARM_EN,A

                ACALL   WAIT_ALARM_RELEASE
                RET


; SET button cycles through five display/settings modes.
SET_PRESSED:
                ACALL   DEBOUNCE
                JB      SET_KEY,KEY_DONE

                INC     SET_MODE
                MOV     A,SET_MODE
                CJNE    A,#05D,SET_RELEASE

                MOV     SET_MODE,#00H

SET_RELEASE:
                ACALL   WAIT_SET_RELEASE
                RET


; UP button increases the currently selected value.
UP_PRESSED:
                ACALL   DEBOUNCE
                JB      UP_KEY,KEY_DONE

                MOV     A,SET_MODE
                JZ      UP_RELEASE

; Mode 1: Set current clock hour
                CJNE    A,#01D,TRY_CLOCK_MINUTE

INCREMENT_CLOCK_HOUR:
                CLR     ET0
                INC     HOUR
                MOV     A,HOUR
                CJNE    A,#24D,CLOCK_HOUR_DONE

                MOV     HOUR,#00D

CLOCK_HOUR_DONE:
                MOV     SEC,#00D
                SETB    ET0
                SJMP    UP_RELEASE


; Mode 2: Set current clock minute
TRY_CLOCK_MINUTE:
                CJNE    A,#02D,TRY_ALARM_HOUR

INCREMENT_CLOCK_MINUTE:
                CLR     ET0
                INC     MINUTE
                MOV     A,MINUTE
                CJNE    A,#60D,CLOCK_MINUTE_DONE

                MOV     MINUTE,#00D

CLOCK_MINUTE_DONE:
                MOV     SEC,#00D
                SETB    ET0
                SJMP    UP_RELEASE


; Mode 3: Set alarm hour
TRY_ALARM_HOUR:
                CJNE    A,#03D,INCREMENT_ALARM_MINUTE

INCREMENT_ALARM_HOUR:
                INC     AL_HOUR
                MOV     A,AL_HOUR
                CJNE    A,#24D,UP_RELEASE

                MOV     AL_HOUR,#00D
                SJMP    UP_RELEASE


; Mode 4: Set alarm minute
INCREMENT_ALARM_MINUTE:
                INC     AL_MINUTE
                MOV     A,AL_MINUTE
                CJNE    A,#60D,UP_RELEASE

                MOV     AL_MINUTE,#00D

UP_RELEASE:
                ACALL   WAIT_UP_RELEASE

KEY_DONE:
                RET


; ============================================================
; DISPLAY TIME ON TM1637
; ============================================================
SHOW_DISPLAY:
                MOV     A,SET_MODE
                JZ      SHOW_CURRENT_TIME

; SET_MODE 1 or 2: show current clock time.
                CJNE    A,#03D,TRY_ALARM_MINUTE_MODE
                SJMP    SHOW_ALARM_TIME

TRY_ALARM_MINUTE_MODE:
                CJNE    A,#04D,SHOW_CURRENT_TIME
                SJMP    SHOW_ALARM_TIME


SHOW_CURRENT_TIME:
                CLR     ET0
                MOV     A,HOUR
                MOV     DISP_HOUR,A

                MOV     A,MINUTE
                MOV     DISP_MINUTE,A

                MOV     A,SEC
                MOV     DISP_SEC,A
                SETB    ET0
                SJMP    DISPLAY_DIGITS


SHOW_ALARM_TIME:
                MOV     A,AL_HOUR
                MOV     DISP_HOUR,A

                MOV     A,AL_MINUTE
                MOV     DISP_MINUTE,A

                MOV     DISP_SEC,#00H


DISPLAY_DIGITS:
; TM1637 automatic address increment command
                ACALL   TM_START
                MOV     A,#40H
                ACALL   TM_WRITE_BYTE
                ACALL   TM_STOP

; Begin writing from first digit
                ACALL   TM_START
                MOV     A,#0C0H
                ACALL   TM_WRITE_BYTE

; First digit: hour tens
                MOV     A,DISP_HOUR
                MOV     B,#10D
                DIV     AB
                ACALL   DIGIT_TO_SEG
                ACALL   TM_WRITE_BYTE

; Second digit: hour units + colon
                MOV     A,B
                ACALL   DIGIT_TO_SEG
                MOV     R6,A

; Normal mode: colon blinks every second.
; Setting modes: colon stays ON.
                MOV     A,SET_MODE
                JNZ     COLON_ON

                MOV     A,DISP_SEC
                ANL     A,#01H
                JNZ     COLON_OFF

COLON_ON:
                MOV     A,R6
                ORL     A,#80H
                MOV     R6,A

COLON_OFF:
                MOV     A,R6
                ACALL   TM_WRITE_BYTE

; Third digit: minute tens
                MOV     A,DISP_MINUTE
                MOV     B,#10D
                DIV     AB
                ACALL   DIGIT_TO_SEG
                ACALL   TM_WRITE_BYTE

; Fourth digit: minute units
                MOV     A,B
                ACALL   DIGIT_TO_SEG
                ACALL   TM_WRITE_BYTE

                ACALL   TM_STOP

; Display ON, maximum brightness
                ACALL   TM_START
                MOV     A,#8FH
                ACALL   TM_WRITE_BYTE
                ACALL   TM_STOP
                RET


; ============================================================
; TM1637 ROUTINES
; ============================================================
TM_INIT:
                ACALL   TM_START
                MOV     A,#40H
                ACALL   TM_WRITE_BYTE
                ACALL   TM_STOP
                RET


TM_START:
                SETB    DIO
                SETB    CLK
                CLR     DIO
                CLR     CLK
                RET


TM_STOP:
                CLR     CLK
                CLR     DIO
                SETB    CLK
                SETB    DIO
                RET


; Send the byte in A, least-significant bit first.
TM_WRITE_BYTE:
                MOV     R7,#08D

WRITE_BIT:
                CLR     CLK
                RRC     A
                MOV     DIO,C
                SETB    CLK
                NOP
                CLR     CLK
                DJNZ    R7,WRITE_BIT

; Release DIO for acknowledge signal from TM1637.
                SETB    DIO
                SETB    CLK
                NOP
                CLR     CLK
                RET


; ============================================================
; BUTTON DEBOUNCE ROUTINES
; ============================================================
DEBOUNCE:
                MOV     R5,#30D

DEB_OUTER:
                MOV     R4,#200D

DEB_INNER:
                DJNZ    R4,DEB_INNER
                DJNZ    R5,DEB_OUTER
                RET


WAIT_SET_RELEASE:
                JNB     SET_KEY,WAIT_SET_RELEASE
                RET


WAIT_UP_RELEASE:
                JNB     UP_KEY,WAIT_UP_RELEASE
                RET


WAIT_ALARM_RELEASE:
                JNB     ALARM_KEY,WAIT_ALARM_RELEASE
                RET


; ============================================================
; SEVEN-SEGMENT DATA TABLE
; ============================================================
DIGIT_TO_SEG:
                MOV     DPTR,#SEGMENT_TABLE
                MOVC    A,@A+DPTR
                RET


SEGMENT_TABLE:
                DB      3FH             ; 0
                DB      06H             ; 1
                DB      5BH             ; 2
                DB      4FH             ; 3
                DB      66H             ; 4
                DB      6DH             ; 5
                DB      7DH             ; 6
                DB      07H             ; 7
                DB      7FH             ; 8
                DB      6FH             ; 9

                END