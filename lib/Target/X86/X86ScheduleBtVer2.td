//=- X86ScheduleBtVer2.td - X86 BtVer2 (Jaguar) Scheduling ---*- tablegen -*-=//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file defines the machine model for AMD btver2 (Jaguar) to support
// instruction scheduling and other instruction cost heuristics. Based off AMD Software
// Optimization Guide for AMD Family 16h Processors & Instruction Latency appendix.
//
//===----------------------------------------------------------------------===//

def BtVer2Model : SchedMachineModel {
  // All x86 instructions are modeled as a single micro-op, and btver2 can
  // decode 2 instructions per cycle.
  let IssueWidth = 2;
  let MicroOpBufferSize = 64; // Retire Control Unit
  let LoadLatency = 5; // FPU latency (worse case cf Integer 3 cycle latency)
  let HighLatency = 25;
  let MispredictPenalty = 14; // Minimum branch misdirection penalty
  let PostRAScheduler = 1;

  // FIXME: SSE4/AVX is unimplemented. This flag is set to allow
  // the scheduler to assign a default model to unrecognized opcodes.
  let CompleteModel = 0;
}

let SchedModel = BtVer2Model in {

// Jaguar can issue up to 6 micro-ops in one cycle
def JALU0 : ProcResource<1>; // Integer Pipe0: integer ALU0 (also handle FP->INT jam)
def JALU1 : ProcResource<1>; // Integer Pipe1: integer ALU1/MUL/DIV
def JLAGU : ProcResource<1>; // Integer Pipe2: LAGU
def JSAGU : ProcResource<1>; // Integer Pipe3: SAGU (also handles 3-operand LEA)
def JFPU0 : ProcResource<1>; // Vector/FPU Pipe0: VALU0/VIMUL/FPA
def JFPU1 : ProcResource<1>; // Vector/FPU Pipe1: VALU1/STC/FPM

// Any pipe - FIXME we need this until we can discriminate between int/fpu load/store/moves properly
def JAny : ProcResGroup<[JALU0, JALU1, JLAGU, JSAGU, JFPU0, JFPU1]>;

// Integer Pipe Scheduler
def JALU01 : ProcResGroup<[JALU0, JALU1]> {
  let BufferSize=20;
}

// AGU Pipe Scheduler
def JLSAGU : ProcResGroup<[JLAGU, JSAGU]> {
  let BufferSize=12;
}

// Fpu Pipe Scheduler
def JFPU01 : ProcResGroup<[JFPU0, JFPU1]> {
  let BufferSize=18;
}

def JDiv    : ProcResource<1>; // integer division
def JMul    : ProcResource<1>; // integer multiplication
def JVALU0  : ProcResource<1>; // vector integer
def JVALU1  : ProcResource<1>; // vector integer
def JVIMUL  : ProcResource<1>; // vector integer multiplication
def JSTC    : ProcResource<1>; // vector store/convert
def JFPM    : ProcResource<1>; // FP multiplication
def JFPA    : ProcResource<1>; // FP addition

// Integer loads are 3 cycles, so ReadAfterLd registers needn't be available until 3
// cycles after the memory operand.
def : ReadAdvance<ReadAfterLd, 3>;

// Many SchedWrites are defined in pairs with and without a folded load.
// Instructions with folded loads are usually micro-fused, so they only appear
// as two micro-ops when dispatched by the schedulers.
// This multiclass defines the resource usage for variants with and without
// folded loads.
multiclass JWriteResIntPair<X86FoldableSchedWrite SchedRW,
                            ProcResourceKind ExePort,
                            int Lat> {
  // Register variant is using a single cycle on ExePort.
  def : WriteRes<SchedRW, [ExePort]> { let Latency = Lat; }

  // Memory variant also uses a cycle on JLAGU and adds 3 cycles to the
  // latency.
  def : WriteRes<SchedRW.Folded, [JLAGU, ExePort]> {
    let Latency = !add(Lat, 3);
  }
}

multiclass JWriteResFpuPair<X86FoldableSchedWrite SchedRW,
                            ProcResourceKind ExePort,
                            int Lat, int Res = 1, int UOps = 1> {
  // Register variant is using a single cycle on ExePort.
  def : WriteRes<SchedRW, [ExePort]> {
    let Latency = Lat;
    let ResourceCycles = [Res];
    let NumMicroOps = UOps;
  }

  // Memory variant also uses a cycle on JLAGU and adds 5 cycles to the
  // latency.
  def : WriteRes<SchedRW.Folded, [JLAGU, ExePort]> {
    let Latency = !add(Lat, 5);
    let ResourceCycles = [1, Res];
    let NumMicroOps = UOps;
  }
}

// A folded store needs a cycle on the SAGU for the store data.
def : WriteRes<WriteRMW, [JSAGU]>;

////////////////////////////////////////////////////////////////////////////////
// Arithmetic.
////////////////////////////////////////////////////////////////////////////////

defm : JWriteResIntPair<WriteALU,   JALU01, 1>;
defm : JWriteResIntPair<WriteIMul,  JALU1,  3>;

def  : WriteRes<WriteIMulH, [JALU1]> {
  let Latency = 6;
  let ResourceCycles = [4];
}

// FIXME 8/16 bit divisions
def : WriteRes<WriteIDiv, [JALU1, JDiv]> {
  let Latency = 25;
  let ResourceCycles = [1, 25];
}
def : WriteRes<WriteIDivLd, [JALU1, JLAGU, JDiv]> {
  let Latency = 41;
  let ResourceCycles = [1, 1, 25];
}

// This is for simple LEAs with one or two input operands.
// FIXME: SAGU 3-operand LEA
def : WriteRes<WriteLEA, [JALU01]>;

////////////////////////////////////////////////////////////////////////////////
// Integer shifts and rotates.
////////////////////////////////////////////////////////////////////////////////

defm : JWriteResIntPair<WriteShift, JALU01, 1>;

def JWriteSHLDrri : SchedWriteRes<[JALU01]> {
  let Latency = 3;
  let ResourceCycles = [6];
  let NumMicroOps = 6;
}
def: InstRW<[JWriteSHLDrri], (instrs SHLD16rri8, SHLD32rri8, SHLD64rri8,
                                     SHRD16rri8, SHRD32rri8, SHRD64rri8)>;

def JWriteSHLDrrCL : SchedWriteRes<[JALU01]> {
  let Latency = 4;
  let ResourceCycles = [8];
  let NumMicroOps = 7;
}
def: InstRW<[JWriteSHLDrrCL], (instrs SHLD16rrCL, SHLD32rrCL, SHLD64rrCL,
                                      SHRD16rrCL, SHRD32rrCL, SHRD64rrCL)>;

def JWriteSHLDm : SchedWriteRes<[JLAGU, JALU01]> {
  let Latency = 9;
  let ResourceCycles = [1, 22];
  let NumMicroOps = 8;
}
def: InstRW<[JWriteSHLDm],(instrs SHLD16mri8, SHLD32mri8, SHLD64mri8,
                                  SHLD16mrCL, SHLD32mrCL, SHLD64mrCL,
                                  SHRD16mri8, SHRD32mri8, SHRD64mri8,
                                  SHRD16mrCL, SHRD32mrCL, SHRD64mrCL)>;

////////////////////////////////////////////////////////////////////////////////
// Loads, stores, and moves, not folded with other operations.
// FIXME: Split x86 and SSE load/store/moves
////////////////////////////////////////////////////////////////////////////////

def : WriteRes<WriteLoad,  [JLAGU]> { let Latency = 5; }
def : WriteRes<WriteStore, [JSAGU]>;
def : WriteRes<WriteMove,  [JALU01]>;

// Treat misc copies as a move.
def : InstRW<[WriteMove], (instrs COPY)>;

////////////////////////////////////////////////////////////////////////////////
// Idioms that clear a register, like xorps %xmm0, %xmm0.
// These can often bypass execution ports completely.
////////////////////////////////////////////////////////////////////////////////

def : WriteRes<WriteZero,  []>;

////////////////////////////////////////////////////////////////////////////////
// Branches don't produce values, so they have no latency, but they still
// consume resources. Indirect branches can fold loads.
////////////////////////////////////////////////////////////////////////////////

defm : JWriteResIntPair<WriteJump,  JALU01, 1>;

////////////////////////////////////////////////////////////////////////////////
// Special case scheduling classes.
// FIXME: pipe for system/microcode?
////////////////////////////////////////////////////////////////////////////////

def : WriteRes<WriteSystem,     [JAny]> { let Latency = 100; }
def : WriteRes<WriteMicrocoded, [JAny]> { let Latency = 100; }
def : WriteRes<WriteFence,  [JSAGU]>;
def : WriteRes<WriteNop, []>;

////////////////////////////////////////////////////////////////////////////////
// Floating point. This covers both scalar and vector operations.
// FIXME: should we bother splitting JFPU pipe + unit stages for fast instructions?
// FIXME: Double precision latencies
// FIXME: SS vs PS latencies
////////////////////////////////////////////////////////////////////////////////

defm : JWriteResFpuPair<WriteFAdd,        JFPU0,  3>;
defm : JWriteResFpuPair<WriteFMul,        JFPU1,  2>;
defm : JWriteResFpuPair<WriteFMA,         JFPU1,  2>; // NOTE: Doesn't exist on Jaguar.
defm : JWriteResFpuPair<WriteFRcp,        JFPU1,  2>;
defm : JWriteResFpuPair<WriteFRsqrt,      JFPU1,  2>;
defm : JWriteResFpuPair<WriteFShuffle,   JFPU01,  1>;
defm : JWriteResFpuPair<WriteFBlend,     JFPU01,  1>;
defm : JWriteResFpuPair<WriteFVarBlend,  JFPU01,  2, 4, 3>;
defm : JWriteResFpuPair<WriteFShuffle256, JFPU01, 1>;

def : WriteRes<WriteFSqrt, [JFPU1, JFPM]> {
  let Latency = 21;
  let ResourceCycles = [1, 21];
}
def : WriteRes<WriteFSqrtLd, [JFPU1, JLAGU, JFPM]> {
  let Latency = 26;
  let ResourceCycles = [1, 1, 21];
}

def : WriteRes<WriteFDiv, [JFPU1, JFPM]> {
  let Latency = 19;
  let ResourceCycles = [1, 19];
}
def : WriteRes<WriteFDivLd, [JFPU1, JLAGU, JFPM]> {
  let Latency = 24;
  let ResourceCycles = [1, 1, 19];
}

////////////////////////////////////////////////////////////////////////////////
// Conversions.
// FIXME: integer pipes
////////////////////////////////////////////////////////////////////////////////

defm : JWriteResFpuPair<WriteCvtF2I,    JFPU1,  3>; // Float -> Integer.
defm : JWriteResFpuPair<WriteCvtI2F,    JFPU1,  3>; // Integer -> Float.
defm : JWriteResFpuPair<WriteCvtF2F,    JFPU1,  3>; // Float -> Float size conversion.

////////////////////////////////////////////////////////////////////////////////
// Vector integer operations.
////////////////////////////////////////////////////////////////////////////////

defm : JWriteResFpuPair<WriteVecALU,      JFPU01, 1>;
defm : JWriteResFpuPair<WriteVecShift,    JFPU01, 1>;
defm : JWriteResFpuPair<WriteVecIMul,     JFPU0,  2>;
defm : JWriteResFpuPair<WriteMPSAD,       JFPU0,  3, 2>;
defm : JWriteResFpuPair<WriteShuffle,     JFPU01, 1>;
defm : JWriteResFpuPair<WriteBlend,       JFPU01, 1>;
defm : JWriteResFpuPair<WriteVarBlend,    JFPU01, 2, 4, 3>;
defm : JWriteResFpuPair<WriteVecLogic,    JFPU01, 1>;
defm : JWriteResFpuPair<WriteShuffle256,  JFPU01, 1>;
defm : JWriteResFpuPair<WriteVarVecShift, JFPU01, 1>; // NOTE: Doesn't exist on Jaguar.

////////////////////////////////////////////////////////////////////////////////
// String instructions.
// Packed Compare Implicit Length Strings, Return Mask
// FIXME: approximate latencies + pipe dependencies
////////////////////////////////////////////////////////////////////////////////

def : WriteRes<WritePCmpIStrM, [JFPU1,JFPU0]> {
  let Latency = 8;
  let ResourceCycles = [2, 2];
  let NumMicroOps = 3;
}
def : WriteRes<WritePCmpIStrMLd, [JLAGU, JFPU1, JFPU0]> {
  let Latency = 13;
  let ResourceCycles = [1, 2, 2];
  let NumMicroOps = 3;
}

// Packed Compare Explicit Length Strings, Return Mask
def : WriteRes<WritePCmpEStrM, [JFPU1, JLAGU, JFPU01,JFPU1, JFPU0]> {
  let Latency = 14;
  let ResourceCycles = [5, 5, 5, 5, 5];
  let NumMicroOps = 9;
}
def : WriteRes<WritePCmpEStrMLd, [JLAGU, JFPU1, JLAGU, JFPU01,JFPU1, JFPU0]> {
  let Latency = 19;
  let ResourceCycles = [1, 5, 5, 5, 5, 5];
  let NumMicroOps = 9;
}

// Packed Compare Implicit Length Strings, Return Index
def : WriteRes<WritePCmpIStrI, [JFPU1, JFPU0]> {
  let Latency = 7;
  let ResourceCycles = [2, 2];
}
def : WriteRes<WritePCmpIStrILd, [JLAGU, JFPU1, JFPU0]> {
  let Latency = 12;
  let ResourceCycles = [1, 2, 2];
}

// Packed Compare Explicit Length Strings, Return Index
def : WriteRes<WritePCmpEStrI, [JFPU1, JLAGU, JFPU01,JFPU1, JFPU0]> {
  let Latency = 14;
  let ResourceCycles = [5, 5, 5, 5, 5];
  let NumMicroOps = 9;
}
def : WriteRes<WritePCmpEStrILd, [JLAGU, JFPU1, JLAGU, JFPU01,JFPU1, JFPU0]> {
  let Latency = 19;
  let ResourceCycles = [1, 5, 5, 5, 5, 5];
  let NumMicroOps = 9;
}

////////////////////////////////////////////////////////////////////////////////
// AES Instructions.
////////////////////////////////////////////////////////////////////////////////

defm : JWriteResFpuPair<WriteAESIMC,    JVIMUL, 2>;
defm : JWriteResFpuPair<WriteAESKeyGen, JVIMUL, 2>;
defm : JWriteResFpuPair<WriteAESDecEnc, JVIMUL, 3>;

////////////////////////////////////////////////////////////////////////////////
// Horizontal add/sub  instructions.
////////////////////////////////////////////////////////////////////////////////

defm : JWriteResFpuPair<WriteFHAdd,   JFPU0,  3>;
defm : JWriteResFpuPair<WritePHAdd,   JFPU01, 1>;

def JWriteFHAddY: SchedWriteRes<[JFPU0]> {
  let Latency = 3;
  let ResourceCycles = [2];
}
def : InstRW<[JWriteFHAddY], (instrs VHADDPDYrr, VHADDPSYrr, VHSUBPDYrr, VHSUBPSYrr)>;

def JWriteFHAddYLd: SchedWriteRes<[JLAGU, JFPU0]> {
  let Latency = 8;
  let ResourceCycles = [1, 2];
}
def : InstRW<[JWriteFHAddYLd], (instrs VHADDPDYrm, VHADDPSYrm, VHSUBPDYrm, VHSUBPSYrm)>;

////////////////////////////////////////////////////////////////////////////////
// Carry-less multiplication instructions.
////////////////////////////////////////////////////////////////////////////////

defm : JWriteResFpuPair<WriteCLMul,   JVIMUL, 2>;

////////////////////////////////////////////////////////////////////////////////
// SSE4.1 instructions.
////////////////////////////////////////////////////////////////////////////////

def JWriteDPPS: SchedWriteRes<[JFPU0, JFPU1]> {
  let Latency = 11;
  let ResourceCycles = [3,3];
  let NumMicroOps = 5;
}
def : InstRW<[JWriteDPPS], (instrs DPPSrri, VDPPSrri)>;

def JWriteDPPSLd: SchedWriteRes<[JLAGU, JFPU0, JFPU1]> {
  let Latency = 16;
  let ResourceCycles = [1,3,3];
  let NumMicroOps = 6;
}
def : InstRW<[JWriteDPPSLd], (instrs DPPSrmi, VDPPSrmi)>;

def JWriteDPPD: SchedWriteRes<[JFPU0, JFPU1]> {
  let Latency = 9;
  let ResourceCycles = [3,3];
  let NumMicroOps = 3;
}
def : InstRW<[JWriteDPPD], (instrs DPPDrri, VDPPDrri)>;

def JWriteDPPDLd: SchedWriteRes<[JLAGU, JFPU0, JFPU1]> {
  let Latency = 14;
  let ResourceCycles = [1,3,3];
  let NumMicroOps = 3;
}
def : InstRW<[JWriteDPPDLd], (instrs DPPDrmi, VDPPDrmi)>;

////////////////////////////////////////////////////////////////////////////////
// SSE4A instructions.
////////////////////////////////////////////////////////////////////////////////

def JWriteEXTRQ: SchedWriteRes<[JFPU01]> {
  let Latency = 1;
  let ResourceCycles = [1];
}
def : InstRW<[JWriteEXTRQ], (instrs EXTRQ, EXTRQI)>;

def JWriteINSERTQ: SchedWriteRes<[JFPU01]> {
  let Latency = 2;
  let ResourceCycles = [4];
}
def : InstRW<[JWriteINSERTQ], (instrs INSERTQ, INSERTQI)>;

////////////////////////////////////////////////////////////////////////////////
// F16C instructions.
////////////////////////////////////////////////////////////////////////////////

def JWriteCVT3: SchedWriteRes<[JFPU1]> {
  let Latency = 3;
}
def : InstRW<[JWriteCVT3], (instrs VCVTPS2PHrr, VCVTPH2PSrr)>;

def JWriteCVT3St: SchedWriteRes<[JFPU1, JSAGU]> {
  let Latency = 3;
  let ResourceCycles = [1, 1];
}
def : InstRW<[JWriteCVT3St], (instrs VCVTPS2PHmr)>;

def JWriteCVT3Ld: SchedWriteRes<[JLAGU, JFPU1]> {
  let Latency = 8;
  let ResourceCycles = [1, 1];
}
def : InstRW<[JWriteCVT3Ld], (instrs VCVTPH2PSrm)>;

def JWriteCVTPS2PHY: SchedWriteRes<[JFPU1, JFPU01]> {
  let Latency = 6;
  let ResourceCycles = [2,2];
  let NumMicroOps = 3;
}
def : InstRW<[JWriteCVTPS2PHY], (instrs VCVTPS2PHYrr)>;

def JWriteCVTPS2PHYSt: SchedWriteRes<[JFPU1, JFPU01, JSAGU]> {
  let Latency = 11;
  let ResourceCycles = [2,2,1];
  let NumMicroOps = 3;
}
def : InstRW<[JWriteCVTPS2PHYSt], (instrs VCVTPS2PHYmr)>;

def JWriteCVTPH2PSY: SchedWriteRes<[JFPU1]> {
  let Latency = 3;
  let ResourceCycles = [2];
  let NumMicroOps = 2;
}
def : InstRW<[JWriteCVTPH2PSY], (instrs VCVTPH2PSYrr)>;

def JWriteCVTPH2PSYLd: SchedWriteRes<[JLAGU, JFPU1]> {
  let Latency = 8;
  let ResourceCycles = [1,2];
  let NumMicroOps = 2;
}
def : InstRW<[JWriteCVTPH2PSYLd], (instrs VCVTPH2PSYrm)>;

////////////////////////////////////////////////////////////////////////////////
// AVX instructions.
////////////////////////////////////////////////////////////////////////////////

def JWriteLogicY: SchedWriteRes<[JFPU01]> {
  let Latency = 1;
  let ResourceCycles = [2];
  let NumMicroOps = 2;
}
def : InstRW<[JWriteLogicY], (instrs VORPDYrr, VORPSYrr,
                                     VXORPDYrr, VXORPSYrr,
                                     VANDPDYrr, VANDPSYrr,
                                     VANDNPDYrr, VANDNPSYrr)>;

def JWriteLogicYLd: SchedWriteRes<[JLAGU, JFPU01]> {
  let Latency = 6;
  let ResourceCycles = [1, 2];
  let NumMicroOps = 3;
}
def : InstRW<[JWriteLogicYLd], (instrs VORPDYrm, VORPSYrm,
                                       VXORPDYrm, VXORPSYrm,
                                       VANDPDYrm, VANDPSYrm,
                                       VANDNPDYrm, VANDNPSYrm)>;

def JWriteVDPPSY: SchedWriteRes<[JFPU1, JFPU0]> {
  let Latency = 12;
  let ResourceCycles = [6, 6];
  let NumMicroOps = 10;
}
def : InstRW<[JWriteVDPPSY], (instrs VDPPSYrri)>;

def JWriteVDPPSYLd: SchedWriteRes<[JLAGU, JFPU1, JFPU0]> {
  let Latency = 17;
  let ResourceCycles = [1, 6, 6];
  let NumMicroOps = 11;
}
def : InstRW<[JWriteVDPPSYLd, ReadAfterLd], (instrs VDPPSYrmi)>;

def JWriteFAddY: SchedWriteRes<[JFPU0]> {
  let Latency = 3;
  let ResourceCycles = [2];
}
def : InstRW<[JWriteFAddY], (instrs VADDPDYrr, VADDPSYrr,
                                    VSUBPDYrr, VSUBPSYrr,
                                    VADDSUBPDYrr, VADDSUBPSYrr)>;

def JWriteFAddYLd: SchedWriteRes<[JLAGU, JFPU0]> {
  let Latency = 8;
  let ResourceCycles = [1, 2];
}
def : InstRW<[JWriteFAddYLd, ReadAfterLd], (instrs VADDPDYrm, VADDPSYrm,
                                                   VSUBPDYrm, VSUBPSYrm,
                                                   VADDSUBPDYrm, VADDSUBPSYrm)>;

def JWriteFDivY: SchedWriteRes<[JFPU1]> {
  let Latency = 38;
  let ResourceCycles = [38];
}
def : InstRW<[JWriteFDivY], (instrs VDIVPDYrr, VDIVPSYrr)>;

def JWriteFDivYLd: SchedWriteRes<[JLAGU, JFPU1]> {
  let Latency = 43;
  let ResourceCycles = [1, 38];
}
def : InstRW<[JWriteFDivYLd, ReadAfterLd], (instrs VDIVPDYrm, VDIVPSYrm)>;

def JWriteVMULYPD: SchedWriteRes<[JFPU1]> {
  let Latency = 4;
  let ResourceCycles = [4];
}
def : InstRW<[JWriteVMULYPD], (instrs VMULPDYrr)>;

def JWriteVMULYPDLd: SchedWriteRes<[JLAGU, JFPU1]> {
  let Latency = 9;
  let ResourceCycles = [1, 4];
}
def : InstRW<[JWriteVMULYPDLd, ReadAfterLd], (instrs VMULPDYrm)>;

def JWriteVMULYPS: SchedWriteRes<[JFPU1]> {
  let Latency = 2;
  let ResourceCycles = [2];
}
def : InstRW<[JWriteVMULYPS], (instrs VMULPSYrr, VRCPPSYr, VRSQRTPSYr)>;

def JWriteVMULYPSLd: SchedWriteRes<[JLAGU, JFPU1]> {
  let Latency = 7;
  let ResourceCycles = [1, 2];
}
def : InstRW<[JWriteVMULYPSLd, ReadAfterLd], (instrs VMULPSYrm, VRCPPSYm, VRSQRTPSYm)>;

def JWriteVMULPD: SchedWriteRes<[JFPU1]> {
  let Latency = 4;
  let ResourceCycles = [2];
}
def : InstRW<[JWriteVMULPD], (instrs MULPDrr, MULSDrr, VMULPDrr, VMULSDrr)>;

def JWriteVMULPDLd: SchedWriteRes<[JLAGU, JFPU1]> {
  let Latency = 9;
  let ResourceCycles = [1, 2];
}
def : InstRW<[JWriteVMULPDLd], (instrs MULPDrm, MULSDrm, VMULPDrm, VMULSDrm)>;

def JWriteVCVTY: SchedWriteRes<[JSTC]> {
  let Latency = 3;
  let ResourceCycles = [2];
}
def : InstRW<[JWriteVCVTY], (instrs VCVTDQ2PDYrr, VCVTDQ2PSYrr,
                                    VCVTPS2DQYrr, VCVTTPS2DQYrr,
                                    VROUNDYPDr,   VROUNDYPSr)>;

def JWriteVCVTYLd: SchedWriteRes<[JLAGU, JSTC]> {
  let Latency = 8;
  let ResourceCycles = [1, 2];
}
def : InstRW<[JWriteVCVTYLd, ReadAfterLd], (instrs VCVTDQ2PDYrm, VCVTDQ2PSYrm,
                                                   VCVTPS2DQYrm, VCVTTPS2DQYrm,
                                                   VROUNDYPDm,   VROUNDYPSm)>;

def JWriteVMOVNTDQSt: SchedWriteRes<[JSTC, JSAGU]> {
  let Latency = 2;
}
def : InstRW<[JWriteVMOVNTDQSt], (instrs MOVNTDQmr, VMOVNTDQmr)>;

def JWriteMOVNTSt: SchedWriteRes<[JSTC, JSAGU]> {
  let Latency = 3;
}
def : InstRW<[JWriteMOVNTSt], (instrs MOVNTPDmr, MOVNTPSmr, MOVNTSD, MOVNTSS, VMOVNTPDmr, VMOVNTPSmr)>;

def JWriteVMOVNTPYSt: SchedWriteRes<[JSTC, JSAGU]> {
  let Latency = 3;
  let ResourceCycles = [2,1];
}
def : InstRW<[JWriteVMOVNTPYSt], (instrs VMOVNTDQYmr, VMOVNTPDYmr, VMOVNTPSYmr)>;

def JWriteFCmp: SchedWriteRes<[JFPU0]> {
  let Latency = 2;
}
def : InstRW<[JWriteFCmp], (instregex "(V)?M(AX|IN)(P|S)(D|S)rr",
                                      "(V)?CMPP(S|D)rri", "(V)?CMPS(S|D)rr")>;

def JWriteFCmpLd: SchedWriteRes<[JLAGU, JFPU0]> {
  let Latency = 7;
}
def : InstRW<[JWriteFCmpLd], (instregex "(V)?M(AX|IN)(P|S)(D|S)rm",
                                        "(V)?CMPP(S|D)rmi", "(V)?CMPS(S|D)rm")>;

def JWriteVCVTPDY: SchedWriteRes<[JSTC, JFPU01]> {
  let Latency = 6;
  let ResourceCycles = [2, 4];
}
def : InstRW<[JWriteVCVTPDY], (instrs VCVTPD2DQYrr, VCVTTPD2DQYrr, VCVTPD2PSYrr)>;

def JWriteVCVTPDYLd: SchedWriteRes<[JLAGU, JSTC, JFPU01]> {
  let Latency = 11;
  let ResourceCycles = [1, 2, 4];
}
def : InstRW<[JWriteVCVTPDYLd, ReadAfterLd], (instrs VCVTPD2DQYrm, VCVTTPD2DQYrm, VCVTPD2PSYrm)>;

def JWriteVBlendVPY: SchedWriteRes<[JFPU01]> {
  let Latency = 3;
  let ResourceCycles = [6];
}
def : InstRW<[JWriteVBlendVPY], (instrs VBLENDVPDYrr, VBLENDVPSYrr, VPERMILPDYrr, VPERMILPSYrr)>;

def JWriteVBlendVPYLd: SchedWriteRes<[JLAGU, JFPU01]> {
  let Latency = 8;
  let ResourceCycles = [1, 6];
}
def : InstRW<[JWriteVBlendVPYLd, ReadAfterLd], (instrs VBLENDVPDYrm, VBLENDVPSYrm)>;

def JWriteVBROADCASTYLd: SchedWriteRes<[JLAGU, JFPU01]> {
  let Latency = 6;
  let ResourceCycles = [1, 4];
}
def : InstRW<[JWriteVBROADCASTYLd, ReadAfterLd], (instrs VBROADCASTSDYrm, VBROADCASTSSYrm)>;

def JWriteFPAY22: SchedWriteRes<[JFPU0]> {
  let Latency = 2;
  let ResourceCycles = [2];
}
def : InstRW<[JWriteFPAY22], (instregex "VCMPP(S|D)Yrri", "VM(AX|IN)P(D|S)Yrr")>;

def JWriteFPAY22Ld: SchedWriteRes<[JLAGU, JFPU0]> {
  let Latency = 7;
  let ResourceCycles = [1, 2];
}
def : InstRW<[JWriteFPAY22Ld, ReadAfterLd], (instregex "VCMPP(S|D)Yrmi", "VM(AX|IN)P(D|S)Yrm")>;

def JWriteVHAddSubY: SchedWriteRes<[JFPU0]> {
  let Latency = 3;
  let ResourceCycles = [2];
}
def : InstRW<[JWriteVHAddSubY], (instrs VHADDPDYrr, VHADDPSYrr, VHSUBPDYrr, VHSUBPSYrr)>;

def JWriteVHAddSubYLd: SchedWriteRes<[JLAGU, JFPU0]> {
  let Latency = 8;
  let ResourceCycles = [1, 2];
}
def : InstRW<[JWriteVHAddSubYLd], (instrs VHADDPDYrm, VHADDPSYrm, VHSUBPDYrm, VHSUBPSYrm)>;

def JWriteVMaskMovLd: SchedWriteRes<[JLAGU,JFPU01]> {
  let Latency = 6;
  let ResourceCycles = [1, 2];
}
def : InstRW<[JWriteVMaskMovLd], (instrs VMASKMOVPDrm, VMASKMOVPSrm)>;

def JWriteVMaskMovYLd: SchedWriteRes<[JLAGU,JFPU01]> {
  let Latency = 6;
  let ResourceCycles = [1, 4];
}
def : InstRW<[JWriteVMaskMovYLd], (instrs VMASKMOVPDYrm, VMASKMOVPSYrm)>;

def JWriteVMaskMovSt: SchedWriteRes<[JFPU01,JSAGU]> {
  let Latency = 6;
  let ResourceCycles = [4, 1];
}
def : InstRW<[JWriteVMaskMovSt], (instrs VMASKMOVPDmr, VMASKMOVPSmr)>;

def JWriteVMaskMovYSt: SchedWriteRes<[JFPU01,JSAGU]> {
  let Latency = 6;
  let ResourceCycles = [4, 1];
}
def : InstRW<[JWriteVMaskMovYSt], (instrs VMASKMOVPDYmr, VMASKMOVPSYmr)>;

// TODO: In fact we have latency '2+i'. The +i represents an additional 1 cycle transfer
// operation which moves the floating point result to the integer unit. During this
// additional cycle the floating point unit execution resources are not occupied
// and ALU0 in the integer unit is occupied instead.
def JWriteVMOVMSK: SchedWriteRes<[JFPU0]> {
  let Latency = 3;
}
def : InstRW<[JWriteVMOVMSK], (instrs VMOVMSKPDrr, VMOVMSKPDYrr, VMOVMSKPSrr, VMOVMSKPSYrr)>;

// TODO: In fact we have latency '3+i'. The +i represents an additional 1 cycle transfer
// operation which moves the floating point result to the integer unit. During this
// additional cycle the floating point unit execution resources are not occupied
// and ALU0 in the integer unit is occupied instead.
def JWriteVTESTY: SchedWriteRes<[JFPU01, JFPU0]> {
  let Latency = 4;
  let ResourceCycles = [2, 2];
  let NumMicroOps = 3;
}
def : InstRW<[JWriteVTESTY], (instrs VPTESTYrr, VTESTPDYrr, VTESTPSYrr)>;

def JWriteVTESTYLd: SchedWriteRes<[JLAGU, JFPU01, JFPU0]> {
  let Latency = 9;
  let ResourceCycles = [1, 2, 2];
  let NumMicroOps = 3;
}
def : InstRW<[JWriteVTESTYLd], (instrs VPTESTYrm, VTESTPDYrm, VTESTPSYrm)>;

def JWriteVTEST: SchedWriteRes<[JFPU0]> {
  let Latency = 3;
}
def : InstRW<[JWriteVTEST], (instrs PTESTrr, VPTESTrr, VTESTPDrr, VTESTPSrr)>;

def JWriteVTESTLd: SchedWriteRes<[JLAGU, JFPU0]> {
  let Latency = 8;
}
def : InstRW<[JWriteVTESTLd], (instrs PTESTrm, VPTESTrm, VTESTPDrm, VTESTPSrm)>;

def JWriteVSQRTYPD: SchedWriteRes<[JFPU1]> {
  let Latency = 54;
  let ResourceCycles = [54];
}
def : InstRW<[JWriteVSQRTYPD], (instrs VSQRTPDYr)>;

def JWriteVSQRTYPDLd: SchedWriteRes<[JLAGU, JFPU1]> {
  let Latency = 59;
  let ResourceCycles = [1, 54];
}
def : InstRW<[JWriteVSQRTYPDLd], (instrs VSQRTPDYm)>;

def JWriteVSQRTYPS: SchedWriteRes<[JFPU1]> {
  let Latency = 42;
  let ResourceCycles = [42];
}
def : InstRW<[JWriteVSQRTYPS], (instrs VSQRTPSYr)>;

def JWriteVSQRTYPSLd: SchedWriteRes<[JLAGU, JFPU1]> {
  let Latency = 47;
  let ResourceCycles = [1, 42];
}
def : InstRW<[JWriteVSQRTYPSLd], (instrs VSQRTPSYm)>;

def JWriteJVZEROALL: SchedWriteRes<[]> {
  let Latency = 90;
  let NumMicroOps = 73;
}
def : InstRW<[JWriteJVZEROALL], (instrs VZEROALL)>;

def JWriteJVZEROUPPER: SchedWriteRes<[]> {
  let Latency = 46;
  let NumMicroOps = 37;
}
def : InstRW<[JWriteJVZEROUPPER], (instrs VZEROUPPER)>;
} // SchedModel

