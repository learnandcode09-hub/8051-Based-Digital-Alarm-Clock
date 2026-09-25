; ============================================================
; AT89S52 Alarm Clock with TM1637 4-digit display
; Crystal: 11.0592 MHz
;
; P1.0 = TM1637 CLK
; P1.1 = TM1637 DIO
; P3.2 = SET button, active LOW
; P3.3 = UP button, active LOW
; P3.4 = ALARM enable / silence button, active LOW
; P3.5 = Active buzzer output, active HIGH
; ============================================================

CLK             BIT     P1.0
DIO             BIT     P1.1

SET_KEY         BIT     P3.2
UP_KEY          BIT     P3.3
ALARM_KEY       BIT     P3.4
BUZZER          BIT     P3.5

SEC             EQU     30H
MINUTE          EQU     31H
HOUR            EQU     32H
TICK50          EQU     33H

AL_HOUR         EQU     34H
AL_MINUTE       EQU     35H
ALARM_EN        EQU     36H
SET_MODE        EQU     37H    ; 0=clock, 1=set alarm hour, 2=set alarm minute
RINGING         EQU     38H
ALARM_LATCH     EQU     39H
BEEP_TICK       EQU     3AH

DISP_HOUR       EQU     3BH
DISP_MINUTE     EQU     3CH
DISP_SEC        EQU     3DH

                ORG     0000H
                LJMP    MAIN

                ORG     000BH
                LJMP    TIMER0_ISR

                ORG     0030H

MAIN:
                MOV     SP,#5FH

; Clock initial time: 12:00:00
                MOV     HOUR,#12D
                MOV     MINUTE,#00D
                MOV     SEC,#00D
                MOV     TICK50,#00D

; Default alarm: 06:30, initially disabled
                MOV     AL_HOUR,#06D
                MOV     AL_MINUTE,#30D
                MOV     ALARM_EN,#00H
                MOV     SET_MODE,#00H
                MOV     RINGING,#00H
                MOV     ALARM_LATCH,#00H
                MOV     BEEP_TICK,#00H

; Set input pins high: buttons connect pin to GND when pressed
                SETB    SET_KEY
                SETB    UP_KEY
                SETB    ALARM_KEY
                CLR     BUZZER

                SETB    CLK
                SETB    DIO

; Timer 0, mode 1
; Reload 4C00H = nominal 50 ms at 11.0592 MHz
                MOV     TMOD,#01H
                MOV     TH0,#4CH
                MOV     TL0,#00H
                CLR     TF0
                SETB    TR0
                MOV     IE,#82H         ; Enable Timer0 interrupt

                ACALL   TM_INIT

MAIN_LOOP:
                ACALL   CHECK_KEYS
                ACALL   CHECK_ALARM
                ACALL   SHOW_DISPLAY
                SJMP    MAIN_LOOP


; ============================================================
; Timer0 interrupt: approximately every 50 ms
; ============================================================
TIMER0_ISR:
                PUSH    ACC
                PUSH    PSW

                MOV     TH0,#4CH
                MOV     TL0,#00H

; Make alarm sound: 0.5 second ON, 0.5 second OFF
                MOV     A,RINGING
                JNZ     ALARM_SOUND

                CLR     BUZZER
                MOV     BEEP_TICK,#00H
                SJMP    CLOCK_TICK

ALARM_SOUND:
                INC     BEEP_TICK
                MOV     A,BEEP_TICK
                CJNE    A,#10D,CLOCK_TICK

                MOV     BEEP_TICK,#00H
                CPL     BUZZER

CLOCK_TICK:
                INC     TICK50
                MOV     A,TICK50
                CJNE    A,#20D,TIMER_EXIT

; 20 × 50 ms = 1 second
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
; Alarm comparison and trigger
; ============================================================
CHECK_ALARM:
                MOV     A,ALARM_EN
                JNZ     ALARM_ENABLED

                MOV     RINGING,#00H
                MOV     ALARM_LATCH,#00H
                CLR     BUZZER
                RET

ALARM_ENABLED:
                MOV     A,HOUR
                CJNE    A,AL_HOUR,NOT_ALARM_TIME

                MOV     A,MINUTE
                CJNE    A,AL_MINUTE,NOT_ALARM_TIME

; Prevent repeated triggering during the same alarm minute
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
; Button handling
; SET: choose alarm-hour -> alarm-minute -> clock display
; UP: increase selected alarm value
; ALARM: enable/disable alarm, or silence ringing alarm
; ============================================================
CHECK_KEYS:
                JNB     ALARM_KEY,ALARM_PRESSED
                JNB     SET_KEY,SET_PRESSED
                JNB     UP_KEY,UP_PRESSED
                RET

ALARM_PRESSED:
                ACALL   DEBOUNCE
                JB      ALARM_KEY,KEY_DONE

                MOV     A,RINGING
                JZ      TOGGLE_ALARM

; If alarm is ringing, this button silences it.
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

SET_PRESSED:
                ACALL   DEBOUNCE
                JB      SET_KEY,KEY_DONE

                INC     SET_MODE
                MOV     A,SET_MODE
                CJNE    A,#03D,SET_RELEASE

                MOV     SET_MODE,#00H

SET_RELEASE:
                ACALL   WAIT_SET_RELEASE
                RET

UP_PRESSED:
                ACALL   DEBOUNCE
                JB      UP_KEY,KEY_DONE

                MOV     A,SET_MODE
                JZ      UP_RELEASE

                CJNE    A,#01H,INCREMENT_ALARM_MINUTE

INCREMENT_ALARM_HOUR:
                INC     AL_HOUR
                MOV     A,AL_HOUR
                CJNE    A,#24D,UP_RELEASE
                MOV     AL_HOUR,#00D
                SJMP    UP_RELEASE

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
; Display: normal mode shows current time.
; Setting mode shows alarm time.
; ============================================================
SHOW_DISPLAY:
                MOV     A,SET_MODE
                JNZ     SHOW_ALARM_TIME

; Take safe copy of current time
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
; TM1637 auto-increment command
                ACALL   TM_START
                MOV     A,#40H
                ACALL   TM_WRITE_BYTE
                ACALL   TM_STOP

; Start at display address zero
                ACALL   TM_START
                MOV     A,#0C0H
                ACALL   TM_WRITE_BYTE

; Hour tens
                MOV     A,DISP_HOUR
                MOV     B,#10D
                DIV     AB
                ACALL   DIGIT_TO_SEG
                ACALL   TM_WRITE_BYTE

; Hour units and colon
                MOV     A,B
                ACALL   DIGIT_TO_SEG
                MOV     R6,A

; Colon blinks in normal display and remains ON while setting alarm.
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

; Minute tens
                MOV     A,DISP_MINUTE
                MOV     B,#10D
                DIV     AB
                ACALL   DIGIT_TO_SEG
                ACALL   TM_WRITE_BYTE

; Minute units
                MOV     A,B
                ACALL   DIGIT_TO_SEG
                ACALL   TM_WRITE_BYTE

                ACALL   TM_STOP

; Display ON, brightness maximum
                ACALL   TM_START
                MOV     A,#8FH
                ACALL   TM_WRITE_BYTE
                ACALL   TM_STOP
                RET


; ============================================================
; TM1637 communication routines
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

; Send byte in A, least-significant bit first
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

; Ignore acknowledge but release DIO correctly
                SETB    DIO
                SETB    CLK
                NOP
                CLR     CLK
                RET


; ============================================================
; Button debounce and release routines
; ============================================================
DEBOUNCE:
                MOV     R5,#30D
DEB1:
                MOV     R4,#200D
DEB2:
                DJNZ    R4,DEB2
                DJNZ    R5,DEB1
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
; Seven-segment patterns
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