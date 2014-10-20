        MOV      r0, #10
        MOV      r0, #0       ; Set up parameters
        MOV		 r1, #1
here:	ADDS      r3, r1, r2
		MOV		 r1,r2 
		MOV		 r2, r3
		BCC	here		;carry clear
		MOV      r7, #1 ;mem
		MOV      r7, #2	;alu
    	MOV      r7, #3	;mul
		MOV      r7, #4 ;r
		MOV      r7, #5	;f
		MOV      r7, #6
		MOV      r7, #7
		MOV      r7, #8
		MOV      r7, #9
		MOV      r7, #10
		MOV      r7, #11
		MOV      r7, #12