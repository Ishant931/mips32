module mips32 (clk1,clk2);
input clk1 , clk2;

reg [31:0] PC , IF_ID_IR, IF_ID_NPC;
reg [31:0] ID_EX_IR , ID_EX_NPC,ID_EX_A, ID_EX_B,ID_EX_IMM;
reg [2:0]  ID_EX_type,EX_MEM_type,MEM_WB_type;
reg [31:0] EX_MEM_IR, EX_MEM_ALUout,EX_MEM_B;
reg        EX_MEM_cond;
reg [31:0] MEM_WB_IR,MEM_WB_ALUout,MEM_WB_LMD;

reg [31:0] Reg [0:31]; // register bank (32*32)
reg [31:0] Mem [0:1023]; // 1024*32 memory
parameter ADD  =6'b000000,
          SUB  =6'b000001,
          AND  =6'b000010,
          OR   =6'b000011,
          SLT  =6'b000100,
          MUL  =6'b000101,
          HLT  =6'b111111,

          LW   =6'b001000,
          SW   =6'b001001,
          ADDI =6'b001010,
          SUBI =6'b001011,
          SLTI =6'b001100,
          BNEQZ=6'b001101,
          BEQZ =6'b001110;


 parameter RR_ALU = 0, RM_ALU=1,LOAD=2,STORE=3,BRANCH=4,HALT=5;

reg HALTED;
reg TAKEN_BRANCH;

always@(posedge clk1)
      if (HALTED ==0)
      begin 
      if (((EX_MEM_IR[31:26] ==BEQZ) && (EX_MEM_cond ==1)) || ((EX_MEM_IR[31:26] == BNEQZ) && (EX_MEM_cond==0)))
      begin 
      IF_ID_IR     <= #2 Mem[EX_MEM_ALUout];
      TAKEN_BRANCH <= #2 1'b1;
      IF_ID_NPC    <= #2 EX_MEM_ALUout +1;
      PC           <= #2 EX_MEM_ALUout +1;
      end 
    else
    begin
    IF_ID_IR  <= #2 Mem[PC];
    IF_ID_NPC <= #2 PC + 1 ;
    PC        <= #2 PC + 1 ;
    end
end

always @(posedge clk2)     // ID stage
     if (HALTED==0)
     begin
          if (IF_ID_IR[25:21]== 5'b00000) ID_EX_A <=0;
          else ID_EX_A  <= #2 Reg[IF_ID_IR[25:21]];   //rs

          if (IF_ID_IR[20:16]==5'b 00000) ID_EX_B <= 0;  // rt 
          else ID_EX_B <= #2 Reg[IF_ID_IR[20:16]];

          ID_EX_NPC <= #2 IF_ID_NPC;
          ID_EX_IR  <= #2 IF_ID_IR;
          ID_EX_IMM <= #2 {{16{IF_ID_IR[15]}},{IF_ID_IR[15:0]}};


case (IF_ID_IR[31:26])
ADD,SUB,AND,OR,SLT,MUL : ID_EX_type <= #2 RR_ALU;
ADDI,SUBI,SLTI :  ID_EX_type <= #2 RM_ALU;
LW :  ID_EX_type <= #2 LOAD ;
SW :  ID_EX_type <= #2 STORE;
BNEQZ,BEQZ :    ID_EX_type <= #2 BRANCH;
HLT  :  ID_EX_type <= #2 HALT;
default :  ID_EX_type <= #2 HALT; // invalid opcode
endcase
end

always@(posedge clk1) // EX stage
  if(HALTED==0)
     begin
         EX_MEM_type <= #2 ID_EX_type;
         EX_MEM_IR <= #2 ID_EX_IR ;
         TAKEN_BRANCH <= #2 0;

     case (ID_EX_type)
       RR_ALU: begin 
                    case (ID_EX_IR[31:26])
                      ADD: EX_MEM_ALUout <=  #2 ID_EX_A + ID_EX_B ;
                      SUB: EX_MEM_ALUout <=  #2 ID_EX_A - ID_EX_B ;
                      AND: EX_MEM_ALUout <=  #2 ID_EX_A & ID_EX_B ;
                      OR: EX_MEM_ALUout <=  #2 ID_EX_A | ID_EX_B ;
                      SLT: EX_MEM_ALUout <=  #2 ID_EX_A < ID_EX_B ;
                      MUL: EX_MEM_ALUout <=  #2 ID_EX_A * ID_EX_B ;
                      default: EX_MEM_ALUout <= #2 32'hxxxxxxxx;
                    endcase
               end
       RM_ALU: begin
                    case(ID_EX_IR[31:26])
                      ADDI: EX_MEM_ALUout <=  #2 ID_EX_A + ID_EX_IMM ;
                      SUBI: EX_MEM_ALUout <=  #2 ID_EX_A - ID_EX_IMM ;
                      SLTI: EX_MEM_ALUout <=  #2 ID_EX_A < ID_EX_IMM ;
                      default: EX_MEM_ALUout <= #2 32'hxxxxxxxx;
                    endcase
               end
       LOAD,STORE:begin
                        EX_MEM_ALUout <=  #2 ID_EX_A + ID_EX_IMM ;
                        EX_MEM_B <= #2 ID_EX_B;
                  end
       BRANCH: begin 
                      EX_MEM_ALUout <= #2 ID_EX_NPC + ID_EX_IMM;
                      EX_MEM_cond <= #2 (ID_EX_A==0);
               end
     endcase
     end

always@ (posedge clk2) // mem stage
if (HALTED == 0)
 begin
    MEM_WB_type <= EX_MEM_type ;
    MEM_WB_IR <= #2 EX_MEM_IR;

  case (EX_MEM_type)
    RR_ALU,RM_ALU: MEM_WB_ALUout <= #2 EX_MEM_ALUout;
    LOAD: MEM_WB_LMD <= #2 Mem[EX_MEM_ALUout];
    STORE: if(TAKEN_BRANCH == 0) 
              Mem[EX_MEM_ALUout] <= #2 EX_MEM_B;
  endcase
 end

 always@(posedge clk1) // wb stage
   begin
     if (TAKEN_BRANCH == 0)
       case (MEM_WB_type)
                   RR_ALU: Reg[MEM_WB_IR[15:11]] <= #2 MEM_WB_ALUout;
                   RM_ALU: Reg[MEM_WB_IR[20:16]] <= #2 MEM_WB_ALUout;
                   LOAD: Reg[MEM_WB_IR[15:11]] <= #2 MEM_WB_LMD;
                   HALT: HALTED <= #2 1'b1;
       endcase
    end

endmodule   




                 





