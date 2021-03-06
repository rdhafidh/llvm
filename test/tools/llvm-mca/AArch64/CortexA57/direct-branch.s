# RUN: llvm-mca -march=aarch64 -mcpu=cortex-a57 -iterations=600 -timeline < %s | FileCheck %s

   b  t

# CHECK:      Iterations:     600
# CHECK-NEXT: Instructions:   600
# CHECK-NEXT: Total Cycles:   603
# CHECK-NEXT: Dispatch Width: 3
# CHECK-NEXT: IPC:            1.00


# CHECK:      Instruction Info:
# CHECK-NEXT: [1]: #uOps
# CHECK-NEXT: [2]: Latency
# CHECK-NEXT: [3]: RThroughput
# CHECK-NEXT: [4]: MayLoad
# CHECK-NEXT: [5]: MayStore
# CHECK-NEXT: [6]: HasSideEffects

# CHECK:      [1]    [2]    [3]    [4]    [5]    [6]	Instructions:
# CHECK-NEXT:  1      1     1.00                    	b   t


# CHECK:      Resources:
# CHECK-NEXT: [0] - A57UnitB
# CHECK-NEXT: [1.0] - A57UnitI
# CHECK-NEXT: [1.1] - A57UnitI
# CHECK-NEXT: [2] - A57UnitL
# CHECK-NEXT: [3] - A57UnitM
# CHECK-NEXT: [4] - A57UnitS
# CHECK-NEXT: [5] - A57UnitW
# CHECK-NEXT: [6] - A57UnitX


# CHECK:      Resource pressure per iteration:
# CHECK-NEXT: [0]    [1.0]  [1.1]  [2]    [3]    [4]    [5]    [6]    
# CHECK-NEXT: 1.00    -      -      -      -      -      -      -     

# CHECK:      Resource pressure by instruction:
# CHECK-NEXT: [0]    [1.0]  [1.1]  [2]    [3]    [4]    [5]    [6]    	Instructions:
# CHECK-NEXT: 1.00    -      -      -      -      -      -      -     	b   t


# CHECK:      Timeline view:
# CHECK-NEXT:      	          012
# CHECK-NEXT: Index	0123456789   

# CHECK:      [0,0]	DeER .    . .	b	t
# CHECK:      [1,0]	D=eER.    . .	b	t
# CHECK:      [2,0]	D==eER    . .	b	t
# CHECK:      [3,0]	.D==eER   . .	b	t


# CHECK:      Average Wait times (based on the timeline view):
# CHECK-NEXT: [0]: Executions
# CHECK-NEXT: [1]: Average time spent waiting in a scheduler's queue
# CHECK-NEXT: [2]: Average time spent waiting in a scheduler's queue while ready
# CHECK-NEXT: [3]: Average time elapsed from WB until retire stage

# CHECK:            [0]    [1]    [2]    [3]
# CHECK-NEXT: 0.     10    4.3    4.3    0.0  	b   t
