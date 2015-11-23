`timescale 1ps/1ps

//
// This is an inefficient implementation.
//   make it run correctly in less cycles, fastest implementation wins
//

//
// States:
//

// Fetch
`define F0 0
`define F1 1
`define F2 2

// decode
`define D0 3

// load
`define L0 4
`define L1 5
`define L2 6

// write-back
`define WB 7

// regs
`define R0 8
`define R1 9

// execute
`define EXEC 10

// halt
`define HALT 15

module main();

    initial begin
        $dumpfile("cpu.vcd");
        $dumpvars(1,main);
    end

    // clock
    wire clk;
    reg isStarted = 0;
    reg isActualHalt = 0;
    reg early_halt = 0;

    reg [15:0]extra_inst = 0;
    reg [15:0]anti_extra_inst = 0;

    reg DEFAULT_JUMP = 1;
    reg jump_prediction_0 = 0; 
    reg jump_prediction_1 = 0;
    wire test = cache[pc_heaven][1];
    wire test2 = cache[pc_M][1];
    wire test3 = cache[pc_W][1];
    //wire test2 = cache[1][1];
    //wire test3 = cache[2][1];
    //wire test4 = cache[3][1];
    //wire test5 = cache[4][1];

    reg[15:0]pc_heaven = 0;

    wire[15:0]mem_test = memory_cache[0][15:0];
    wire[15:0]mem_test_offset = memory_cache[0][18:16];

    reg [15:0]branch_cache_offset = 0; //used to flush cache
    reg [2:0] cache [31:0]; //only stores 2 bits per entry for branch prediction, not entire instructions
    reg [20:0]memory_cache[31:0]; //64 
    //DDDD DDDD DDDD DDDD OOOV  Data, offset, valid


    clock c0(clk); //manages clock ticks

    counter ctr((isHalt_W & valid_W) | early_halt, clk, !(anti_extra_inst > 0) & (valid_W | is_only_jeq_A | is_only_jeq_M | is_only_jump_D| jump_predict_D | !isStarted | extra_inst > 0 | early_halt), cycle); //displays clock count at completion

    // PC
    reg [15:0]pc = 16'h0000;
    wire [15:0]pc1 =    jump_predict_failed_M ? pc_M + 1 :
                        MARDF_flush ? pc_M : 
                        isActualJump_W ? (isJeq_W ? pc_W + rt_W : jjj_W) :
                        is_only_jeq_M  ? pc_M + rt_M :
                        is_only_jeq_A  ? pc_A + rt_A :
                        is_only_jump_D ? jjj_D : 
                        jump_predict_D ? pc_D + rt_D :
                                                     pc + 1;
                                                 
    // fetch ----------------------------------------------------------
    wire [15:0]memOut_F;
    wire [15:0]pc_F = pc;
    mem i0(clk, (isStarted & !DF_stall) ? pc1 : pc, inst_D_temp, res_A, memOut_W, Memw_enable, Memw_address, Memw_data);
    wire valid_F = isStarted;
    reg Memw_enable = 0;
    reg [15:0]Memw_address = -1;
    reg [15:0]Memw_data = 0;
    wire [15:0]inst_forward_data_F =  (inst_forward_F) ? Memw_data : -1;  
    wire inst_forward_F = (^Memw_address === 1'bx) ? 0 : (Memw_address == pc) & Memw_enable;

    // decode ----------------------------------------------------------
    reg valid_D = 0;
    reg [15:0]pc_D;
    reg [15:0]inst_forward_data_D = -1;
    wire [15:0]inst_D_temp;
    reg inst_forward_D = 0;
    wire [15:0]inst_D = (inst_forward_D) ? inst_forward_data_D : 
                        (just_DF_stalled) ? inst_D :
                        (valid_D & !(^inst_D_temp === 1'bx)) ? 
                        inst_D_temp : 16'hffff;
    wire [3:0]opcode_D = inst_D[15:12];
    //if need registers, will always just read from rA & rB anyways.
    wire [3:0]ra_D = inst_D[11:8]; 
    wire [3:0]rb_D = inst_D[7:4];
    wire [3:0]rt_D = inst_D[3:0];
    wire [15:0]jjj_D = inst_D[11:0]; // zero-extended
    wire [15:0]ii_D = inst_D[11:4]; // zero-extended
    wire [15:0]ss_D = inst_D[7:0];
    reg [15:0]inst_forward_data; 

    wire isMov_D = (opcode_D == 4'h0);
    wire isAdd_D = (opcode_D == 4'h1);
    wire isJmp_D = (opcode_D == 4'h2);
    wire isHalt_D = (opcode_D == 4'h3);
    wire isLd_D = (opcode_D == 4'h4);
    wire isLdr_D = (opcode_D == 4'h5);
    wire isJeq_D = (opcode_D == 4'h6);
    wire isMemw_D = (opcode_D == 4'h7);
    wire readsRegs_D = (isAdd_D|isJeq_D|isLdr_D|isMemw_D);
    wire writesRegs_D = (isMov_D|isAdd_D|isLd_D|isLdr_D);
    wire readsMemory_D = (isLd_D|isLdr_D);

    wire early_halt_D = valid_D & isHalt_D & !valid_R & !valid_A & !valid_M & !valid_W;

    wire jump_predict_D = (^cache[pc_D][1] === 1'bx) ? 0 :
                                        (cache[pc_D[4:0] ][1] & cache[pc_D[4:0] ][0] & valid_D);


    wire mem_cache_hit_D = valid_D & (pc_D[7:5] == memory_cache[pc_D[4:0]][18:16]);   

    //hazards
    wire is_rA_1STEP_hazard_D;
    wire is_rB_1STEP_hazard_D;
    wire is_rA_2STEP_hazard_D;
    wire is_rB_2STEP_hazard_D;   
    wire is_rA_3STEP_hazard_D;
    wire is_rB_3STEP_hazard_D; 
    wire is_rA_4STEP_hazard_D;
    wire is_rB_4STEP_hazard_D; 

    wire [15:0]dh_rA_4STEP_possible_data_D;
    wire [15:0]dh_rB_4STEP_possible_data_D;
    wire is_rA_1STEP_ldr_hazard_D;
    wire is_rB_1STEP_ldr_hazard_D; 
    wire is_early_execute_D = is_only_jump_D;


    /*wire is_only_jump_D =   isJmp_D & valid_D &
                            !(((isJmp_R | isJeq_R) & valid_R) | 
                            ((isJmp_A | (isJeq_A & !early_jeq_fail_A)) & valid_A) | 
                            ((isJmp_M | (isJeq_M & !early_jeq_fail_M)) & valid_M) | 
                            ((isJmp_W | (isJeq_W & !early_jeq_fail_W)) & valid_W));*/
    wire is_only_jump_D =   isJmp_D & valid_D & !(isMemw_R & (ss_R == jjj_D));


    // registers/READ ----------------------------------------------------------
    reg valid_R = 0;
    reg [15:0]pc_R = 0;
    reg [15:0]inst_R = 0;
    reg [3:0]opcode_R = 0;
    reg [3:0]ra_R = 0;
    reg [3:0]rb_R = 0;
    reg [3:0]rt_R = 0;
    reg [15:0]jjj_R = 0;
    reg [15:0]ii_R = 0;
    reg [15:0]ss_R = 0;
    reg isMov_R = 0;
    reg isAdd_R = 0;
    reg isJmp_R = 0;
    reg isHalt_R = 0;
    reg isLd_R = 0;
    reg isLdr_R = 0;
    reg isJeq_R = 0;
    reg isMemw_R = 0;
    reg readsRegs_R = 0;
    reg writesRegs_R = 0;
    reg readsMemory_R = 0; 
    reg is_early_execute_temp_R;
    wire is_early_execute_R = (is_early_execute_R);
    wire early_halt_R = valid_R & isHalt_R & !valid_A & !valid_M & !valid_W;
    reg jump_predict_R = 0;
    //prompt for data in D, get in A 2 cycles later
    regs rf(clk,
        readsRegs_D, ra_D, va_A,
        readsRegs_D, rb_D, vb_A, 
        writesRegs_W && valid_W, rt_W, writeData_W);

    assign is_rA_1STEP_hazard_D = valid_R & writesRegs_R & (rt_R == ra_D) & readsRegs_D & !(isLdr_D);
    assign is_rB_1STEP_hazard_D = valid_R & writesRegs_R & (rt_R == rb_D) & readsRegs_D & !(isLdr_D);
    
    //assign DF_stall = writesRegs_R & (rt_R == rb_D) & readsRegs_D & (isJeq_D);

    reg is_rA_1STEP_hazard_R = 0;
    reg is_rB_1STEP_hazard_R = 0;
    reg is_rA_2STEP_hazard_R = 0;
    reg is_rB_2STEP_hazard_R = 0;   
    reg is_rA_3STEP_hazard_R = 0;
    reg is_rB_3STEP_hazard_R = 0; 
    reg is_rA_4STEP_hazard_R = 0;
    reg is_rB_4STEP_hazard_R = 0; 



    wire [15:0]dh_rA_3STEP_possible_data_R;
    wire [15:0]dh_rB_3STEP_possible_data_R;
    reg [15:0]dh_rA_4STEP_possible_data_R = 0;
    reg [15:0]dh_rB_4STEP_possible_data_R = 0;
    reg is_rA_1STEP_ldr_hazard_R = 0;
    reg is_rB_1STEP_ldr_hazard_R = 0; 
    
    reg just_DF_stalled = 0;
    //wire DF_stall = (pc_D > 27 | pc_R > 27) ? 0 :
                //(!just_DF_stalled & writesRegs_R & (rt_R == rb_D | rt_R == ra_D) & readsRegs_D & (isLdr_D) & valid_R & valid_D);
    wire DF_stall = (^inst_D === 1'bx) ? 0 :
                (!just_DF_stalled & writesRegs_R & (rt_R == rb_D | rt_R == ra_D) & readsRegs_D & (isLdr_D) & valid_R & valid_D);

    //wire DF_stall = (valid_R & valid_D & !just_DF_stalled & writesRegs_R) ? 
    //((rt_R == rb_D | rt_R == ra_D) & readsRegs_D & (isLdr_D)) ? 1 : 0 : 0;
    //reg [15:0] cycle = 0; // ?

    // Add/ALU ----------------------------------------------------------
    reg valid_A = 0;
    reg [15:0]pc_A = 0;
    reg [15:0]inst_A = 0;
    reg [3:0]opcode_A = 0;
    reg [3:0]ra_A = 0;
    reg [3:0]rb_A = 0;
    reg [3:0]rt_A = 0;
    reg [15:0]jjj_A = 0;
    reg [15:0]ii_A = 0;
    reg [15:0]ss_A = 0;
    reg isMov_A = 0;
    reg isAdd_A = 0;
    reg isJmp_A = 0;
    reg isHalt_A = 0;
    reg isLd_A = 0;
    reg isLdr_A = 0;
    reg isJeq_A = 0;
    reg readsRegs_A = 0;
    reg writesRegs_A = 0;
    reg readsMemory_A = 0; 
    reg isMemw_A = 0;
    reg is_early_execute_temp_A;
    wire is_early_execute_A = (is_early_execute_temp_A | is_only_jeq_A);
    wire early_halt_A = valid_A & isHalt_A & !valid_M & !valid_W;
    reg jump_predict_A = 0;          

    wire [15:0]va_A; //data from register reads
    wire [15:0]vb_A;
    wire [15:0]va_real_A =  (is_rA_2STEP_hazard_A) ? dh_rA_2STEP_possible_data_A :
                            (is_rA_3STEP_hazard_A) ? dh_rA_3STEP_possible_data_A :
                            (is_rA_4STEP_hazard_A) ? dh_rA_4STEP_possible_data_A :
                            (is_rA_1STEP_ldr_hazard_A) ? dh_rA_1STEP_ldr_possible_data_A :
                            (^va_A === 1'bx) ? -1 : va_A;
    wire wtf = (^va_A === 1'bx);
                                                        

    wire [15:0]vb_real_A =  (is_rB_2STEP_hazard_A) ? dh_rB_2STEP_possible_data_A :
                            (is_rB_3STEP_hazard_A) ? dh_rB_3STEP_possible_data_A :
                            (is_rB_4STEP_hazard_A) ? dh_rB_4STEP_possible_data_A :
                            (is_rB_1STEP_ldr_hazard_A) ? dh_rB_1STEP_ldr_possible_data_A :  
                            (^vb_A === 1'bx) ? -1 : vb_A;

    wire [15:0]res_A = (isAdd_A|isLdr_A) ? va_real_A + vb_real_A : 
                      (isMov_A|isLd_A) ? ii_A :
                                    0;

    wire early_jeq_fail_A = !(va_real_A == vb_real_A) & !(is_rA_1STEP_hazard_A|is_rB_1STEP_hazard_A); 

   /* wire is_only_jeq_A =  (^inst_A === 1'bx) ? 0 : isJeq_A & (va_real_A == vb_real_A) & !(is_rA_1STEP_hazard_A|is_rB_1STEP_hazard_A) & valid_A & !isLdr_D &
                        !(((isJmp_M | (isJeq_M & !early_jeq_fail_M)) & valid_M) | 
                        ((isJmp_W | (isJeq_W & !early_jeq_fail_W)) & valid_W));*/

    wire is_only_jeq_A =  (^inst_A === 1'bx) ? 0 : isJeq_A & (va_real_A == vb_real_A) & !(is_rA_1STEP_hazard_A|is_rB_1STEP_hazard_A) & valid_A & !isLdr_D;


    assign is_rA_2STEP_hazard_D = valid_A & writesRegs_A & (rt_A == ra_D) & readsRegs_D;
    assign is_rB_2STEP_hazard_D = valid_A & writesRegs_A & (rt_A == rb_D) & readsRegs_D;
    assign is_rA_1STEP_ldr_hazard_D = writesRegs_R & (rt_R == ra_D) & readsRegs_D;
    assign is_rB_1STEP_ldr_hazard_D = writesRegs_R & (rt_R == rb_D) & readsRegs_D;                                    

    //hazards
    reg is_rA_1STEP_hazard_A = 0;
    reg is_rB_1STEP_hazard_A = 0; 
    reg is_rA_2STEP_hazard_A = 0;
    reg is_rB_2STEP_hazard_A = 0;   
    reg is_rA_3STEP_hazard_A = 0;
    reg is_rB_3STEP_hazard_A = 0; 
    reg is_rA_4STEP_hazard_A = 0;
    reg is_rB_4STEP_hazard_A = 0; 

    reg is_rA_1STEP_ldr_hazard_A = 0;
    reg is_rB_1STEP_ldr_hazard_A = 0; 

    wire [15:0]dh_rA_2STEP_possible_data_A;
    wire [15:0]dh_rB_2STEP_possible_data_A;
    reg [15:0]dh_rA_3STEP_possible_data_A = 0;
    reg [15:0]dh_rB_3STEP_possible_data_A = 0;
    reg [15:0]dh_rA_4STEP_possible_data_A = 0;
    reg [15:0]dh_rB_4STEP_possible_data_A = 0;

    wire [15:0]dh_rA_1STEP_ldr_possible_data_A;
    wire [15:0]dh_rB_1STEP_ldr_possible_data_A;


    wire is_MA_1STEP_hazard_A = isMemw_M & valid_M & valid_A & 
                                    ((isLd_A & (ii_A == ss_M)) | (isLdr_A & (va_real_A + vb_real_A == ss_M)));
    wire [15:0] mh_MA_1STEP_possible_data_A = va_real_M;  

    wire is_WA_INSTRUCTION_hazard_A = isMemw_W & valid_W & valid_A& (pc_A == ss_W) && (inst_A != va_real_W);


     // what to write in the register file

    // Memory ----------------------------------------------------------
    reg valid_M = 0;
    reg [15:0]pc_M = 0;
    reg [15:0]inst_M = 0;
    reg [3:0]opcode_M = 0;
    reg [3:0]ra_M = 0;
    reg [3:0]rb_M = 0;
    reg [3:0]rt_M = 0;
    reg [15:0]jjj_M = 0;
    reg [15:0]ii_M = 0;
    reg [15:0]ss_M = 0;
    reg isMov_M = 0;
    reg isAdd_M = 0;
    reg isJmp_M = 0;
    reg isHalt_M = 0;
    reg isLd_M = 0;
    reg isLdr_M = 0;
    reg isJeq_M = 0;
    reg readsRegs_M = 0;
    reg writesRegs_M = 0;
    reg readsMemory_M = 0; 
    reg [15:0]res_M = 0;
    reg [15:0]va_M = 0;
    reg [15:0]vb_M = 0;
    reg isMemw_M = 0;
    reg is_early_execute_temp_M;
    wire is_early_execute_M = (is_early_execute_temp_M | is_only_jeq_M);
    wire early_halt_M = valid_M & isHalt_M & !valid_W;
    reg jump_predict_M = 0;
    wire [15:0]va_real_M =  (is_rA_1STEP_hazard_M) ? dh_rA_possible_data_M :
                            (is_rA_2STEP_hazard_M) ? dh_rA_2STEP_possible_data_M :
                            (is_rA_3STEP_hazard_M) ? dh_rA_3STEP_possible_data_M :
                            (is_rA_4STEP_hazard_M) ? dh_rA_4STEP_possible_data_M :
                            (is_rA_1STEP_ldr_hazard_A) ? dh_rA_1STEP_ldr_possible_data_M :  
                                                        va_M;

    wire [15:0]vb_real_M =  (is_rB_1STEP_hazard_M) ? dh_rB_possible_data_M :
                            (is_rB_2STEP_hazard_M) ? dh_rB_2STEP_possible_data_M :
                            (is_rB_3STEP_hazard_M) ? dh_rB_3STEP_possible_data_M :
                            (is_rB_4STEP_hazard_M) ? dh_rB_4STEP_possible_data_M :
                            (is_rB_1STEP_ldr_hazard_A) ? dh_rB_1STEP_ldr_possible_data_M :  
                                                      vb_M;

    /*wire is_only_jeq_M =  (^inst_M === 1'bx) ? 0 : isJeq_M & (va_real_M == vb_real_M)  & valid_M &
                    !((isJmp_W | (isJeq_W & !early_jeq_fail_W)) & valid_W);*/
         wire is_only_jeq_M =  (^inst_M === 1'bx) ? 0 : isJeq_M & (va_real_M == vb_real_M)  & valid_M;              

    reg early_jeq_fail_int_M = 0;
    wire early_jeq_fail_M = (is_rA_1STEP_hazard_M | is_rB_1STEP_hazard_M) ? !(va_real_M == vb_real_M) : early_jeq_fail_int_M;
    //hazards
    reg is_rA_1STEP_hazard_M = 0;
    reg is_rB_1STEP_hazard_M = 0;
    reg is_rA_2STEP_hazard_M = 0;
    reg is_rB_2STEP_hazard_M = 0;   
    reg is_rA_3STEP_hazard_M = 0;
    reg is_rB_3STEP_hazard_M = 0; 
    reg is_rA_4STEP_hazard_M = 0;
    reg is_rB_4STEP_hazard_M = 0; 

    //hazard data
    wire [15:0]dh_rA_possible_data_M;
    wire [15:0]dh_rB_possible_data_M;
    reg [15:0]dh_rA_2STEP_possible_data_M = 0;
    reg [15:0]dh_rB_2STEP_possible_data_M = 0;
    reg [15:0]dh_rA_3STEP_possible_data_M = 0;
    reg [15:0]dh_rB_3STEP_possible_data_M = 0;
    reg [15:0]dh_rA_4STEP_possible_data_M = 0;
    reg [15:0]dh_rB_4STEP_possible_data_M = 0;
    reg [15:0]dh_rA_1STEP_ldr_possible_data_M = 0;
    reg [15:0]dh_rB_1STEP_ldr_possible_data_M = 0;
    

    reg is_MA_1STEP_hazard_M = 0;
    reg [15:0]mh_MA_1STEP_possible_data_M = 0;  



    wire is_WM_INSTRUCTION_hazard_M = isMemw_W & valid_W & valid_M & (pc_M == ss_W) && (inst_M != va_real_W);
    wire jump_predict_failed_M = jump_predict_M & isJeq_M & (va_real_M != vb_real_M);
    wire MARDF_flush = is_WM_INSTRUCTION_hazard_M | jump_predict_failed_M;
    reg MARDF_stall = 0;
    assign is_rA_3STEP_hazard_D = valid_M & writesRegs_M & (rt_M == ra_D) & readsRegs_D;
    assign is_rB_3STEP_hazard_D = valid_M & writesRegs_M & (rt_M == rb_D) & readsRegs_D;
    // Writeback ----------------------------------------------------------
    reg valid_W = 0;
    reg [15:0]inst_W = 0;
    reg [15:0]pc_W  = 0;
    reg [3:0]opcode_W = 0;
    reg [3:0]ra_W = 0;
    reg [3:0]rb_W = 0;
    reg [3:0]rt_W = 0;
    reg [15:0]jjj_W = 0;
    reg [15:0]ii_W = 0;
    reg [15:0]ss_W = 0;
    reg isMov_W = 0;
    reg isAdd_W = 0;
    reg isJmp_W = 0;
    reg isHalt_W = 0;
    reg isLd_W = 0;
    reg isLdr_W = 0;
    reg isJeq_W = 0;
    reg isMemw_W = 0;
    reg readsRegs_W = 0;
    reg writesRegs_W = 0;
    reg readsMemory_W = 0; 
    reg [15:0]res_W = 0;
    wire [15:0]memOut_W;
    reg [15:0]va_W = -1;
    reg [15:0]vb_W = -1;
    reg is_early_execute_temp_W;
    reg jump_predict_W = 0;
    wire is_early_execute_W = is_early_execute_temp_W;



    wire [15:0]va_real_W =  (is_rA_1STEP_hazard_W) ? dh_rA_possible_data_W :
                            (is_rA_2STEP_hazard_W) ? dh_rA_2STEP_possible_data_W :
                            (is_rA_3STEP_hazard_W) ? dh_rA_3STEP_possible_data_W :
                            (is_rA_4STEP_hazard_W) ? dh_rA_4STEP_possible_data_W :
                            (^va_W === 1'bx)? -1 : va_W;

    wire [15:0]vb_real_W =  (is_rB_1STEP_hazard_W) ? dh_rB_possible_data_W :
                            (is_rB_2STEP_hazard_W) ? dh_rB_2STEP_possible_data_W :
                            (is_rB_3STEP_hazard_W) ? dh_rB_3STEP_possible_data_W :
                            (is_rB_4STEP_hazard_W) ? dh_rB_4STEP_possible_data_W :
                            (^vb_W === 1'bx)? -2 : vb_W;

    reg early_jeq_fail_W = 0;                                              
    wire isActualJump_W =  valid_W & (isJmp_W | (isJeq_W && (va_real_W == vb_real_W)));
    wire [15:0]writeData_W = (isAdd_W & (is_rA_1STEP_hazard_W | is_rB_1STEP_hazard_W)) ? va_real_W + vb_real_W :
                             (isAdd_W | isMov_W) ? res_W :
                             (is_MA_1STEP_hazard_W) ? mh_MA_1STEP_possible_data_W :
                             (isLdr_W | isLd_W)  ? memOut_W : 
                                                   0;   


    //wire early_jeq_fail_W = !(va_real_W == vb_real_W) & !(is_rA_1STEP_hazard_W|is_rB_1STEP_hazard_W); 
    //hazards
    assign is_rA_4STEP_hazard_D = valid_W & writesRegs_W & (rt_W == ra_D) & readsRegs_D;
    assign is_rB_4STEP_hazard_D = valid_W & writesRegs_W & (rt_W == rb_D) & readsRegs_D;
    reg is_rA_1STEP_hazard_W = 0;
    reg is_rB_1STEP_hazard_W = 0;
    reg is_rA_2STEP_hazard_W = 0;
    reg is_rB_2STEP_hazard_W = 0;   
    reg is_rA_3STEP_hazard_W = 0;
    reg is_rB_3STEP_hazard_W = 0; 
    reg is_rA_4STEP_hazard_W = 0;
    reg is_rB_4STEP_hazard_W = 0; 
    reg [15:0]dh_rA_possible_data_W = 0;
    reg [15:0]dh_rB_possible_data_W = 0; 
    reg [15:0]dh_rA_2STEP_possible_data_W = 0;
    reg [15:0]dh_rB_2STEP_possible_data_W = 0;
    reg [15:0]dh_rA_3STEP_possible_data_W = 0;
    reg [15:0]dh_rB_3STEP_possible_data_W = 0;
    reg [15:0]dh_rA_4STEP_possible_data_W = 0;
    reg [15:0]dh_rB_4STEP_possible_data_W = 0;

    assign dh_rA_1STEP_ldr_possible_data_A = writeData_W;
    assign dh_rB_1STEP_ldr_possible_data_A = writeData_W;
    assign dh_rA_possible_data_M = writeData_W;
    assign dh_rB_possible_data_M = writeData_W;
    assign dh_rA_2STEP_possible_data_A = writeData_W;
    assign dh_rB_2STEP_possible_data_A = writeData_W;
    assign dh_rA_3STEP_possible_data_R = writeData_W;
    assign dh_rB_3STEP_possible_data_R = writeData_W;
    assign dh_rA_4STEP_possible_data_D = writeData_W;
    assign dh_rB_4STEP_possible_data_D = writeData_W;

    reg is_MA_1STEP_hazard_W = 0;
    reg [15:0] mh_MA_1STEP_possible_data_W = 0;  

    always @(posedge clk) begin





       // if(!(isActualJump_W|is_only_jump_D)) begin
           // pc <= (isStarted & !DF_stall) ? pc + 1 : pc;  
        //end
        
       pc <=(jump_predict_failed_M) ? pc_M + 1 : 
            (jump_predict_D) ? pc_D + rt_D : 
            (MARDF_stall) ? pc : 
            (MARDF_flush) ? pc_M : 
            (isStarted & !DF_stall) ? pc + 1 : pc;
        isStarted <= 1;
       //isStarted <= !(isActualJump_W|is_only_jump_D);
 
        if(jump_predict_failed_M) begin
            cache[ pc_M[4:0] ][1] <= 0;
        end

        if(valid_M & is_only_jeq_M) begin
            pc <= pc_M + rt_M;
            cache[pc_M[4:0] ][0] <= 1;
            cache[pc_M[4:0] ][1] <= 1;
            jump_prediction_1 <= jump_prediction_0;
            jump_prediction_0 <= 1;            
        end 
        else if(valid_A & is_only_jeq_A) begin
            pc <= pc_A + rt_A;
            jump_prediction_1 <= jump_prediction_0;
            jump_prediction_0 <= 1;
            cache[pc_A[4:0] ][0] <= 1;
            cache[pc_A[4:0] ][1] <= 1;
        end 
        else if(valid_D & is_only_jump_D) begin
            pc <= jjj_D;
        end 
        else if(valid_W | jump_predict_W) begin
            case(opcode_W)
                4'h2 : begin // jmp
                    pc <= isActualJump_W ? jjj_W : pc + 1;
                end
                4'h6 : begin // jeq
                    pc <= isActualJump_W ? pc_W + rt_W : pc + 1;
                    cache[pc_W][0] <= 1;
                    cache[pc_W][1] <= isActualJump_W;
                    jump_prediction_1 <= jump_prediction_0;
                    jump_prediction_0 <= isActualJump_W;

                end            
            endcase  
        end

if(!MARDF_stall) begin
    if(!DF_stall) begin 
        just_DF_stalled <= 0;
        valid_D <= (isHalt_W & valid_W) | MARDF_flush ? 0 : (isActualJump_W|is_only_jump_D|is_only_jeq_A|is_only_jeq_M|jump_predict_D) ? 0 : valid_F;
    //Decode<=Fetch
        pc_D <= pc_F;
        inst_forward_data_D <= inst_forward_data_F;
        inst_forward_D <= inst_forward_F;
    end else begin
        just_DF_stalled <= 1;
    end

    //Read<=Decode
        valid_R <=  (isHalt_W & valid_W) | MARDF_flush ? 0 : DF_stall ? 0 : 
                    (isActualJump_W|is_only_jump_D|is_only_jeq_A|is_only_jeq_M|jump_predict_D) ? 0 : valid_D;

        inst_R <= inst_D;
        pc_R <= pc_D;
        opcode_R <= opcode_D;
        ra_R <= ra_D;
        rb_R <= rb_D;
        rt_R <= rt_D;
        jjj_R <= jjj_D;
        ii_R <=  ii_D;
        ss_R <= ss_D;
        isMov_R <= isMov_D;
        isAdd_R <= isAdd_D;
        isJmp_R <= isJmp_D;
        isHalt_R <= isHalt_D;
        isLd_R <= isLd_D;
        isLdr_R <= isLdr_D;
        isJeq_R <= isJeq_D;
        isMemw_R <= isMemw_D;
        readsRegs_R <= readsRegs_D;
        writesRegs_R <= writesRegs_D;
        readsMemory_R <= readsMemory_D; 
        is_rA_1STEP_ldr_hazard_R <= is_rA_1STEP_ldr_hazard_D;
        is_rB_1STEP_ldr_hazard_R <= is_rB_1STEP_ldr_hazard_D;
        is_rA_1STEP_hazard_R <= is_rA_1STEP_hazard_D;
        is_rB_1STEP_hazard_R <= is_rB_1STEP_hazard_D;
        is_rA_2STEP_hazard_R <= is_rA_2STEP_hazard_D;
        is_rB_2STEP_hazard_R <= is_rB_2STEP_hazard_D;  
        is_rA_3STEP_hazard_R <= is_rA_3STEP_hazard_D;
        is_rB_3STEP_hazard_R <= is_rB_3STEP_hazard_D;
        is_rA_4STEP_hazard_R <= is_rA_4STEP_hazard_D;
        is_rB_4STEP_hazard_R <= is_rB_4STEP_hazard_D;
        is_early_execute_temp_R <= is_early_execute_D;
        dh_rA_4STEP_possible_data_R <= dh_rA_4STEP_possible_data_D;
        dh_rB_4STEP_possible_data_R <= dh_rB_4STEP_possible_data_D;
        jump_predict_R <= jump_predict_D & !jump_predict_failed_M;

    //ALU<=Read
        valid_A <= (isHalt_W & valid_W) | MARDF_flush? 0 : (isActualJump_W | is_only_jeq_A | is_only_jeq_M) ? 0 : valid_R;

        inst_A <= inst_R;
        pc_A <= pc_R;
        opcode_A <= opcode_R;
        ra_A <= ra_R;
        rb_A <= rb_R;
        rt_A <= rt_R;
        jjj_A <= jjj_R;
        ii_A <=  ii_R;
        ss_A <= ss_R;
        isMov_A <= isMov_R;
        isAdd_A <= isAdd_R;
        isJmp_A <= isJmp_R;
        isHalt_A <= isHalt_R;
        isLd_A <= isLd_R;
        isLdr_A <= isLdr_R;
        isJeq_A <= isJeq_R;
        isMemw_A <= isMemw_R;
        readsRegs_A <= readsRegs_R;
        writesRegs_A <= writesRegs_R;
        readsMemory_A <= readsMemory_R;
        is_early_execute_temp_A <= is_early_execute_R;

        is_rA_1STEP_ldr_hazard_A <= is_rA_1STEP_ldr_hazard_R;
        is_rB_1STEP_ldr_hazard_A <= is_rB_1STEP_ldr_hazard_R;
        is_rA_1STEP_hazard_A <= is_rA_1STEP_hazard_R;
        is_rB_1STEP_hazard_A <= is_rB_1STEP_hazard_R;
        is_rA_2STEP_hazard_A <= is_rA_2STEP_hazard_R;
        is_rB_2STEP_hazard_A <= is_rB_2STEP_hazard_R;  
        is_rA_3STEP_hazard_A <= is_rA_3STEP_hazard_R;
        is_rB_3STEP_hazard_A <= is_rB_3STEP_hazard_R;
        is_rA_4STEP_hazard_A <= is_rA_4STEP_hazard_R;
        is_rB_4STEP_hazard_A <= is_rB_4STEP_hazard_R;

        dh_rA_3STEP_possible_data_A <= dh_rA_3STEP_possible_data_R;
        dh_rB_3STEP_possible_data_A <= dh_rB_3STEP_possible_data_R;
        dh_rA_4STEP_possible_data_A <= dh_rA_4STEP_possible_data_R;
        dh_rB_4STEP_possible_data_A <= dh_rB_4STEP_possible_data_R;
        jump_predict_A <= jump_predict_R & !jump_predict_failed_M;
    //Memory<=ALU
        valid_M <= (isHalt_W & valid_W) | MARDF_flush ? 0 : (isActualJump_W | is_only_jeq_A |  is_only_jeq_M) ? 0 : valid_A;

        inst_M <= inst_A;
        pc_M <= pc_A;
        opcode_M <= opcode_A;
        ra_M <= ra_A;
        rb_M <= rb_A;
        va_M <= va_A;
        vb_M <= vb_A;
        rt_M <= rt_A;
        jjj_M <= jjj_A;
        ii_M <=  ii_A;
        ss_M <= ss_A;
        isMov_M <= isMov_A;
        isAdd_M <= isAdd_A;
        isJmp_M <= isJmp_A;
        isHalt_M <= isHalt_A;
        isLd_M <= isLd_A;
        isLdr_M <= isLdr_A;
        isJeq_M <= isJeq_A;
        isMemw_M <= isMemw_A;
        readsRegs_M <= readsRegs_A;
        writesRegs_M <= writesRegs_A;
        readsMemory_M <= readsMemory_A; 
        early_jeq_fail_int_M <= early_jeq_fail_A;
        res_M <= res_A;
        is_early_execute_temp_M <= is_early_execute_A;
        is_rA_1STEP_hazard_M <= is_rA_1STEP_hazard_A;
        is_rB_1STEP_hazard_M <= is_rB_1STEP_hazard_A;
        is_rA_2STEP_hazard_M <= is_rA_2STEP_hazard_A;
        is_rB_2STEP_hazard_M <= is_rB_2STEP_hazard_A;  
        is_rA_3STEP_hazard_M <= is_rA_3STEP_hazard_A;
        is_rB_3STEP_hazard_M <= is_rB_3STEP_hazard_A;
        is_rA_4STEP_hazard_M <= is_rA_4STEP_hazard_A;
        is_rB_4STEP_hazard_M <= is_rB_4STEP_hazard_A;

        dh_rA_2STEP_possible_data_M <= dh_rA_2STEP_possible_data_A;
        dh_rB_2STEP_possible_data_M <= dh_rB_2STEP_possible_data_A;    
        dh_rA_3STEP_possible_data_M <= dh_rA_3STEP_possible_data_A;
        dh_rB_3STEP_possible_data_M <= dh_rB_3STEP_possible_data_A;
        dh_rA_4STEP_possible_data_M <= dh_rA_4STEP_possible_data_A;
        dh_rB_4STEP_possible_data_M <= dh_rB_4STEP_possible_data_A;
        dh_rA_1STEP_ldr_possible_data_M <= dh_rA_1STEP_ldr_possible_data_A;
        dh_rB_1STEP_ldr_possible_data_M <= dh_rB_1STEP_ldr_possible_data_A;

        is_MA_1STEP_hazard_M <= is_MA_1STEP_hazard_A;
        mh_MA_1STEP_possible_data_M <= mh_MA_1STEP_possible_data_A;

        jump_predict_M <= jump_predict_A & !jump_predict_failed_M;
        //is_rA_1STEP_ldr_hazard_M <= is_rA_1STEP_ldr_hazard_A;
        //is_rB_1STEP_ldr_hazard_M <= is_rB_1STEP_ldr_hazard_A;
        //dh_rA_1STEP_ldr_possible_data_M <= dh_rA_1STEP_ldr_possible_data_A;
        //dh_rB_1STEP_ldr_possible_data_M <= dh_rB_1STEP_ldr_possible_data_A;

    //Writeback<=Memory
        valid_W <= (isHalt_W & valid_W) | MARDF_flush ? 0 : (isActualJump_W | is_only_jeq_M) ?  0 : valid_M;

        inst_W <= inst_M;
        pc_W <= pc_M;
        opcode_W <= opcode_M;
        ra_W <= ra_M;
        rb_W <= rb_M;
        va_W <= va_M;
        vb_W <= vb_M;
        rt_W <= rt_M;
        jjj_W <= jjj_M;
        ii_W <=  ii_M;
        ss_W <= ss_M;
        isMov_W <= isMov_M;
        isAdd_W <= isAdd_M;
        isJmp_W <= isJmp_M;
        isHalt_W <= isHalt_M;
        isLd_W <= isLd_M;
        isLdr_W <= isLdr_M;
        isJeq_W <= isJeq_M;
        isMemw_W <= isMemw_M;
        readsRegs_W <= readsRegs_M;
        writesRegs_W <= writesRegs_M;
        readsMemory_W <= readsMemory_M; 
        is_early_execute_temp_W <= is_early_execute_M;
        res_W <= res_M;
        early_jeq_fail_W <= early_jeq_fail_M;
        is_rA_1STEP_hazard_W <= is_rA_1STEP_hazard_M;
        is_rB_1STEP_hazard_W <= is_rB_1STEP_hazard_M;
        is_rA_2STEP_hazard_W <= is_rA_2STEP_hazard_M;
        is_rB_2STEP_hazard_W <= is_rB_2STEP_hazard_M;  
        is_rA_3STEP_hazard_W <= is_rA_3STEP_hazard_M;
        is_rB_3STEP_hazard_W <= is_rB_3STEP_hazard_M;
        is_rA_4STEP_hazard_W <= is_rA_4STEP_hazard_M;
        is_rB_4STEP_hazard_W <= is_rB_4STEP_hazard_M;
        //is_rA_1STEP_ldr_hazard_W <= is_rA_1STEP_ldr_hazard_M;
        //is_rB_1STEP_ldr_hazard_W <= is_rB_1STEP_ldr_hazard_M;
        dh_rA_possible_data_W <= dh_rA_possible_data_M;
        dh_rB_possible_data_W <= dh_rB_possible_data_M;
        dh_rA_2STEP_possible_data_W <= dh_rA_2STEP_possible_data_M;
        dh_rB_2STEP_possible_data_W <= dh_rB_2STEP_possible_data_M;    
        dh_rA_3STEP_possible_data_W <= dh_rA_3STEP_possible_data_M;
        dh_rB_3STEP_possible_data_W <= dh_rB_3STEP_possible_data_M;
        dh_rA_4STEP_possible_data_W <= dh_rA_4STEP_possible_data_M;
        dh_rB_4STEP_possible_data_W <= dh_rB_4STEP_possible_data_M;
        //dh_rA_1STEP_ldr_possible_data_W <= dh_rA_1STEP_ldr_possible_data_M;
        //dh_rB_1STEP_ldr_possible_data_W <= dh_rB_1STEP_ldr_possible_data_M;
        is_MA_1STEP_hazard_W <= is_MA_1STEP_hazard_M;
        mh_MA_1STEP_possible_data_W <= mh_MA_1STEP_possible_data_M;
        jump_predict_W <= jump_predict_M & !jump_predict_failed_M;
        pc_heaven <= pc_W;

    //halt logic
        if (!isActualHalt) begin
            isActualHalt <= isHalt_W & valid_W;
        end
    //Memory writeback <= writeback
        Memw_data <= va_real_W;
        Memw_address <= ss_W;
        Memw_enable <= isMemw_W & valid_W;

    if(isMemw_W & valid_W) begin
        memory_cache[ss_W[4:0]][15:0] = va_real_W;
        memory_cache[ss_W[4:0]][18:16] = ss_W[7:5];
        memory_cache[ss_W[4:0]][19:19] = 1;
    end
    //Counter logic
        extra_inst <= (valid_W & (is_only_jeq_A | is_only_jeq_M | is_only_jump_D | jump_predict_D)) ? extra_inst + 1 :
                      (valid_W | is_only_jeq_A | is_only_jeq_M | is_only_jump_D | jump_predict_D) ? extra_inst : 
                      (extra_inst > 0) ? extra_inst - 1 : extra_inst;

        anti_extra_inst <= (jump_predict_failed_M) ? anti_extra_inst + 1 : 
                           ((anti_extra_inst > 0) & (valid_W | is_only_jeq_A | is_only_jeq_M | is_only_jump_D| jump_predict_D | !isStarted | extra_inst > 0 | early_halt))
                                    ? anti_extra_inst - 1 : anti_extra_inst;
        early_halt <= (early_halt_D | early_halt_R | early_halt_A | early_halt_M);              

    end
        //MARDF_stall <= MARDF_stall ? 0 : MARDF_flush;
    end
endmodule
