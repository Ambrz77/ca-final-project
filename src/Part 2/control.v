`include "control.h"
`include "memory.h"
`include "dbgflags.h"

module CacheControl (
        DStrobe, DRW, DReady,
        Match, Valid, Dirty,
        Write,
        DirtyValue,
        MDataSelect,
        MAddrSelect,
        DDataSelect,
        MDataOE, DDataOE,
        MStrobe, MRW, Reset, Clk );

input           DStrobe, DRW;
output          DReady;
input           Match, Valid, Dirty;
output          Write;
output		DirtyValue;
output          MDataSelect, MAddrSelect;
output          DDataSelect;
output          MDataOE, DDataOE;
output          MStrobe, MRW;
input           Reset;
input           Clk;


reg             WSCLoad;
reg    [15:0]   WSCLoadVal;
wire            WSCSig;
WaitStateCtr    WaitStateCtr (WSCLoad, WSCLoadVal, WSCSig, Clk);

reg             DReadyEnable;
reg             MStrobe;
reg             MRW;
reg             MDataOE;
reg             Write;
reg		DirtyValue;
reg             Ready;
reg             MDataSelect, MAddrSelect;
reg             DDataSelect;
reg             DDataOE;

wire DReady = (DReadyEnable && Match && Valid && DRW) || Ready;

/*
always @ (DReadyEnable or Match or Valid or Ready)
   if (DReadyEnable && Match && Valid && DRW)
      $display($time, " DReady due to Read Cache Hit");
   else if (Ready)
      $display($time, " DReady due to Memory Ready");
   else
      $display($time, " DReady value %b due to (%b,%b,%b,%b)",
                DReady, DReadyEnable, Match, Valid, Ready);
*/

reg     [3:0]   State;
reg     [3:0]   NextState;


initial begin
   State     = `STATE_IDLE;
   NextState = `STATE_IDLE;
end

always @ (posedge Clk) begin
   State = NextState;
   UpdateSignals(State);
   //if (Reset)
   //   NextState = `STATE_IDLE;
   //else
   begin
      case (State)
         `STATE_IDLE: begin
                        if (`dbg) $display(" ctrl> IDLE", $time);
                        if (DStrobe && DRW)
                           NextState = `STATE_READ;
                        else if (DStrobe && !DRW)
                           NextState = `STATE_WRITE;
                        else
                           NextState = `STATE_IDLE;
                     end

         `STATE_READ: begin
                        if (`dbg) $display(" ctrl> READ", $time);
                        if (Match && Valid) begin    // read hit
                           NextState = `STATE_IDLE;
                           if (`vbs) $display(" ctrl> READ HIT", $time);
                           Main.Driver.nreadhits = Main.Driver.nreadhits + 1;
                        end
                        else if ((!Match) && Valid && Dirty)            // writeback
                                 NextState = `STATE_WRITEBACK;
                             else NextState = `STATE_READMISS;
                     end

         `STATE_READMISS: begin
                        if (`vbs) $display(" ctrl> READMISS", $time);
                        Main.Driver.nreadmiss = Main.Driver.nreadmiss + 1;
                        WSCLoadVal = `READ_WAITCYCLES-1;
                        NextState  = `STATE_READMEM;
                     end

         `STATE_READMEM: begin
                        if (`dbg) $display(" ctrl> READMEM", $time);
                        if (WSCSig)
                           NextState = `STATE_READDATA;
                        else
                           NextState = `STATE_READMEM;
                     end

         `STATE_READDATA: begin
                        if (`dbg) $display(" ctrl> READDATA", $time);
                        NextState = `STATE_IDLE;
                     end

         `STATE_WRITE: begin
                        if (`dbg) $display(" ctrl> WRITE", $time);
                        if (Match && Valid) begin
                           NextState = `STATE_WRITEHIT;
                        end
                        else
                           NextState = `STATE_WRITEMISS;
                     end

         `STATE_WRITEHIT: begin
                        if (`vbs) $display(" ctrl> WRITEHIT", $time);
                        Main.Driver.nwritehits = Main.Driver.nwritehits + 1;
                        NextState  = `STATE_IDLE;
                     end

         `STATE_WRITEMISS: begin
                     if (`vbs) $display(" ctrl> WRITEMISS ", $time);
                        Main.Driver.nwritemiss = Main.Driver.nwritemiss + 1;
                        WSCLoadVal = `WRITE_WAITCYCLES-2;
                        NextState  = `STATE_WRITEMEM;
                     end

         `STATE_WRITEMEM: begin
                        if (`dbg) $display(" ctrl> WRITEMEM", $time);
                        if (WSCSig)
                           NextState = `STATE_WRITEDATA;
                        else
                           NextState = `STATE_WRITEMEM;
                     end

         `STATE_WRITEDATA: begin
                        if (`dbg) $display(" ctrl> WRITEDATA", $time);
                        NextState = `STATE_IDLE;
                     end
                     
         `STATE_WRITEBACK: begin
	                if (`vbs) $display(" ctrl> WRITEBACK", $time);
	                Main.Driver.nwriteback = Main.Driver.nwriteback + 1;
	                WSCLoadVal = `WRITE_WAITCYCLES-1;
	                NextState  = `STATE_WRITEBACKMEM;
                     end
                     
         `STATE_WRITEBACKMEM: begin
	                if (`dbg) $display(" ctrl> WRITEBACKMEM", $time);
	                if (WSCSig)
	                  NextState = `STATE_READMISS;
	                else
	                 NextState = `STATE_WRITEBACKMEM;
                     end
           default: NextState = `STATE_IDLE;       
         
      endcase
   end
end

task OutputVec;
input   [11:0]   vector;
begin
   WSCLoad              = vector[11];
   DReadyEnable         = vector[10];
   Ready                = vector[9];     // signal driver
   Write		= vector[8];     // to cache Data, Tag, Valid and Dirty RAMs
   DirtyValue           = vector[7];	// state to be written to Dirty RAM
   MStrobe              = vector[6];     // memory strobe
   MRW                  = vector[5];
   MAddrSelect		= vector[4];
   MDataSelect     	= vector[3];
   DDataSelect          = vector[2];
   DDataOE              = vector[1];
   MDataOE              = vector[0];

end
endtask

task UpdateSignals;
input [3:0] state;
   case (state)
      `STATE_IDLE:      	OutputVec(12'b000000000000);
      `STATE_READ:      	OutputVec(12'b010000000010);
      `STATE_READMISS:  	OutputVec(12'b100001100010);
      `STATE_READMEM:   	OutputVec(12'b000000100010);
      `STATE_READDATA:  	OutputVec(12'b001100100110);
      `STATE_WRITE:     	OutputVec(12'b000000000000);
      `STATE_WRITEHIT:  	OutputVec(12'b001110000000);
      `STATE_WRITEMISS: 	OutputVec(12'b100001000001);
      `STATE_WRITEMEM:  	OutputVec(12'b000000000001);
      `STATE_WRITEDATA: 	OutputVec(12'b001000000001);
      `STATE_WRITEBACK:		OutputVec(12'b100001011001);
      `STATE_WRITEBACKMEM: 	OutputVec(12'b000000011001);
   endcase
endtask

endmodule /* Control */



module WaitStateCtr(Load, LoadValue, Sig, Clk);
input           Load;
input   [15:0]  LoadValue;
output          Sig;
input           Clk;

reg     [15:0]  Count;
wire            Sig = Count == 16'b0;

always @(posedge Clk) begin
   if (Load)
      Count = LoadValue;
   else
      Count = Count - 16'b1;
   if (`dbg) $display($time, " WaitState    %d", Count);
end

endmodule /* WaitStateCtr */
