`include "para.v"
// default_nettype of none prevents implicit wire declaration.
`default_nettype none

module ResultWriteMaster #(
  // Set to the address width of the interface
  parameter integer C_M_AXI_ADDR_WIDTH  = 64,

  // Set the data width of the interface
  // Range: 32, 64, 128, 256, 512, 1024
  parameter integer C_M_AXI_DATA_WIDTH  = 512,
  parameter integer STAGE_NUMS          = `PARA_PIPELINE_STAGE_NUMS
)
(
  // AXI Interface
  input  wire                            aclk,
  input  wire                            areset,

  // Control signals
  input  wire                            ctrl_start,              // Pulse high for one cycle to begin reading
  output wire                            ctrl_done,               // Pulses high for one cycle when transfer request is complete
  // The following ctrl signals are sampled when ctrl_start is asserted
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]   ctrl_addr_offset,        // Starting Address offset
  input  wire                            ctrl_result_over, 

  // AXI4 master interface (write only)
  output wire                            m_axi_awvalid,
  input  wire                            m_axi_awready,
  output wire [C_M_AXI_ADDR_WIDTH-1:0]   m_axi_awaddr,
  output wire [7:0]                      m_axi_awlen,

  output wire                            m_axi_wvalid,
  input  wire                            m_axi_wready,
  output wire [C_M_AXI_DATA_WIDTH-1:0]   m_axi_wdata,
  output wire [C_M_AXI_DATA_WIDTH/8-1:0] m_axi_wstrb,
  output wire                            m_axi_wlast,

  input  wire                            m_axi_bvalid,
  output wire                            m_axi_bready,
  // AXI4-Stream interface
  input  wire                            s_axis_tvalid,
  output wire                            s_axis_tready,
  input  wire  [C_M_AXI_DATA_WIDTH-1:0]  s_axis_tdata

);

timeunit 1ps;
timeprecision 1ps;

///////////////////////////////////////////////////////////////////////////////
// functions
///////////////////////////////////////////////////////////////////////////////
function integer f_min (
  input integer a,
  input integer b
);
  f_min = (a < b) ? a : b;
endfunction

function integer f_max (
  input integer a,
  input integer b
);
  f_max = (a > b) ? a : b;
endfunction

/////////////////////////////////////////////////////////////////////////////
// Local Parameters
/////////////////////////////////////////////////////////////////////////////
localparam integer LP_DW_BYTES                   = C_M_AXI_DATA_WIDTH/8;
localparam integer LP_LOG_DW_BYTES               = $clog2(LP_DW_BYTES);
localparam integer LP_MAX_BURST_LENGTH           = 256;   // Max AXI Protocol burst length
localparam integer LP_MAX_BURST_BYTES            = 4096;  // Max AXI Protocol burst size in bytes
localparam integer LP_AXI_BURST_LEN              = f_min(LP_MAX_BURST_BYTES/LP_DW_BYTES, LP_MAX_BURST_LENGTH);
localparam integer LP_LOG_BURST_LEN              = $clog2(LP_AXI_BURST_LEN);
localparam integer LP_FIFO_DEPTH                 = 2**($clog2(f_max(LP_AXI_BURST_LEN * 4, STAGE_NUMS * 4)) + 1);
localparam integer LP_TRANSACTION_CNTR_WIDTH     = $clog2(LP_FIFO_DEPTH/LP_AXI_BURST_LEN) + 3;
localparam [C_M_AXI_ADDR_WIDTH-1:0] LP_ADDR_MASK = LP_DW_BYTES*LP_AXI_BURST_LEN - 1;
localparam integer LP_FIFO_READ_LATENCY          = 0;
localparam integer LP_FIFO_COUNT_WIDTH           = $clog2(LP_FIFO_DEPTH)+1;
localparam S_IDLE = 2'b00;
localparam S_ADDR = 2'b01;
localparam S_DATA = 2'b11;
localparam S_RESP = 2'b10;
/////////////////////////////////////////////////////////////////////////////
// Variables
/////////////////////////////////////////////////////////////////////////////
// Control
logic                                 done_pulse = 1'b0;
logic                                 done_pulse_reminder = 1'b0;
logic                                 ctrl_start_d1 = 1'b0;
logic [C_M_AXI_ADDR_WIDTH-1:0]        addr_offset_r = 0;
logic                                 start    = 1'b0;
logic [LP_LOG_BURST_LEN-1:0]          count_burst_len;
// Write data channel
logic                                 m_axi_wvalid_i;
logic                                 wxfer;       // Unregistered write data transfer
logic [LP_LOG_BURST_LEN-1:0]          wxfers_to_go;  // Used for simulation debug
logic [LP_TRANSACTION_CNTR_WIDTH-1:0] w_transactions_to_go;
logic                                 w_running;
logic                                 zero_complete_trans;
logic                                 final_counter_is_zero;
logic                                 add_transaction;
logic                                 complete_transaction;
logic                                 final_transaction;
logic                                 start_transaction;
logic [LP_FIFO_COUNT_WIDTH-1:0]       count_buffer_size;
logic                                 buffer_counter_is_zero;
logic                                 buffer_almost_full;
// Write address channel
logic                                 awxfer;
logic                                 aw_valid_r = 1'b0;
logic [C_M_AXI_ADDR_WIDTH-1:0]        aw_addr_r = 0;
logic [7:0]                           aw_len_r = 0;
logic [C_M_AXI_ADDR_WIDTH-1:0]        addr_r = 0;
logic [7:0]                           len_r = 0;
// Write response channel
logic                                 b_ready_r = 1'b0;
// --- state machine
logic [1:0]                           s_state = S_IDLE;           
logic                                 busy_r = 1'b0;

/////////////////////////////////////////////////////////////////////////////
// Control logic
/////////////////////////////////////////////////////////////////////////////
assign ctrl_done = done_pulse;

// Done logic
always @(posedge aclk) begin
  if (areset | ctrl_start) begin
    done_pulse <= 1'b0;
    done_pulse_reminder <= 1'b0;
  end
  else begin
    done_pulse <= done_pulse ? 
      0 : !done_pulse_reminder & !busy_r & zero_complete_trans & final_counter_is_zero & ctrl_result_over;
    done_pulse_reminder <= (!busy_r & zero_complete_trans & final_counter_is_zero & ctrl_result_over) ? 1'b1 : done_pulse_reminder;
  end
end

always @(posedge aclk) begin
  ctrl_start_d1 <= ctrl_start;
end

always @(posedge aclk) begin
  if (ctrl_start) begin
    // Align transfer to burst length to avoid AXI protocol issues if starting address is not correctly aligned.
    addr_offset_r <= ctrl_addr_offset & ~LP_ADDR_MASK;
  end
end

always @(posedge aclk) begin
  start <= ctrl_start_d1;
end

/////////////////////////////////////////////////////////////////////////////
// AXI Write Data Channel
/////////////////////////////////////////////////////////////////////////////
//数据通道在数据传输状态开启
assign w_running = s_state == S_DATA;

// xpm_fifo_sync: Synchronous FIFO
// Xilinx Parameterized Macro, Version 2017.4
xpm_fifo_sync # (
  .FIFO_MEMORY_TYPE    ( "block"              ) , // string; "auto", "block", "distributed", or "ultra";
  .ECC_MODE            ( "no_ecc"             ) , // string; "no_ecc" or "en_ecc";
  .FIFO_WRITE_DEPTH    ( LP_FIFO_DEPTH        ) , // positive integer
  .WRITE_DATA_WIDTH    ( C_M_AXI_DATA_WIDTH   ) , // positive integer
  .WR_DATA_COUNT_WIDTH ( LP_FIFO_COUNT_WIDTH  ) , // positive integer, not used
  .PROG_FULL_THRESH    ( 10                   ) , // positive integer, not used
  .FULL_RESET_VALUE    ( 1                    ) , // positive integer; 0 or 1
  .USE_ADV_FEATURES    ( "1F1F"               ) , // string; "0000" to "1F1F";
  .READ_MODE           ( "fwft"               ) , // string; "std" or "fwft";
  .FIFO_READ_LATENCY   ( LP_FIFO_READ_LATENCY ) , // positive integer;
  .READ_DATA_WIDTH     ( C_M_AXI_DATA_WIDTH   ) , // positive integer
  .RD_DATA_COUNT_WIDTH ( LP_FIFO_COUNT_WIDTH  ) , // positive integer, not used
  .PROG_EMPTY_THRESH   ( 10                   ) , // positive integer, not used
  .DOUT_RESET_VALUE    ( "0"                  ) , // string, don't care
  .WAKEUP_TIME         ( 0                    ) // positive integer; 0 or 2;
)
inst_xpm_fifo_sync (
  .sleep         ( 1'b0                     ) ,
  .rst           ( areset                   ) ,
  .wr_clk        ( aclk                     ) ,
  .wr_en         ( s_axis_tvalid            ) ,
  .din           ( s_axis_tdata             ) ,
  .full          (                          ) ,
  .overflow      (                          ) ,
  .prog_full     (                          ) ,
  .wr_data_count (                          ) ,
  .almost_full   (                          ) ,
  .wr_ack        (                          ) ,
  .wr_rst_busy   (                          ) ,
  .rd_en         ( m_axi_wready & w_running ) ,//数据通道wready
  .dout          ( m_axi_wdata              ) ,//数据通道wdata
  .empty         (                          ) ,
  .prog_empty    (                          ) ,
  .rd_data_count (                          ) ,
  .almost_empty  (                          ) ,
  .data_valid    ( m_axi_wvalid_i           ) ,
  .underflow     (                          ) ,
  .rd_rst_busy   (                          ) ,
  .injectsbiterr ( 1'b0                     ) ,
  .injectdbiterr ( 1'b0                     ) ,
  .sbiterr       (                          ) ,
  .dbiterr       (                          )
);

assign m_axi_wstrb  = {(C_M_AXI_DATA_WIDTH/8){1'b1}};//数据通道wstrb
assign m_axi_wvalid = m_axi_wvalid_i & w_running;//数据通道wvalid
assign wxfer = m_axi_wvalid & m_axi_wready;//发生一次数据传输

//跟踪fifo中的结果数量
example_counter #(
  .C_WIDTH ( LP_FIFO_COUNT_WIDTH            ) ,
  .C_INIT  ( {LP_FIFO_COUNT_WIDTH{1'b0}}    )
)
inst_buffer_cntr (
  .clk        ( aclk                        ) ,
  .clken      ( 1'b1                        ) ,
  .rst        ( areset                      ) ,
  .load       ( start                       ) ,
  .incr       ( s_axis_tvalid               ) ,
  .decr       ( m_axi_wready & w_running    ) ,
  .load_value ( {LP_FIFO_COUNT_WIDTH{1'b0}} ) ,
  .count      ( count_buffer_size           ) ,
  .is_zero    ( buffer_counter_is_zero      )
);

always @(posedge aclk) begin
  if(areset | start) begin
     buffer_almost_full <= 1'b0;
  end else if(count_buffer_size > (LP_FIFO_DEPTH / 2)) begin
     buffer_almost_full <= 1'b1;
  end else if(count_buffer_size < (LP_FIFO_DEPTH / 4)) begin
     buffer_almost_full <= 1'b0;
  end
end
assign s_axis_tready = buffer_almost_full;

//每次向fifo写入一个元组final计数器加1,达到标准突发长度增加一次突发事务
example_counter #(
  .C_WIDTH ( LP_LOG_BURST_LEN            ) ,
  .C_INIT  ( {LP_LOG_BURST_LEN{1'b0}}    )
)
inst_final_cntr (
  .clk        ( aclk                      ) ,
  .clken      ( 1'b1                      ) ,
  .rst        ( areset                    ) ,
  .load       ( start | final_transaction ) ,
  .incr       ( s_axis_tvalid             ) ,//最大值再加1自动恢复0
  .decr       ( 1'b0                      ) ,
  .load_value ( {LP_LOG_BURST_LEN{1'b0}}  ) ,
  .count      ( count_burst_len           ) ,
  .is_zero    ( final_counter_is_zero     )
);

assign add_transaction = (count_burst_len == {LP_LOG_BURST_LEN{1'b1}}) & s_axis_tvalid;

//fifo写入元组每满一个标准突发长度增加一次突发事务，每次完成突发事务数据传输减一
example_counter #(
  .C_WIDTH ( LP_TRANSACTION_CNTR_WIDTH         ) ,
  .C_INIT  ( {LP_TRANSACTION_CNTR_WIDTH{1'b0}} )
)
inst_w_transaction_cntr (
  .clk        ( aclk                 ) ,
  .clken      ( 1'b1                 ) ,
  .rst        ( areset               ) ,
  .load       ( start                ) ,
  .incr       ( add_transaction      ) ,
  .decr       ( complete_transaction ) ,
  .load_value ( 0                    ) ,
  .count      ( w_transactions_to_go ) ,
  .is_zero    ( zero_complete_trans  )
);

// 最后一次传输之前将长度设置为count_burst_len,一般传输长度固定初值
example_counter #(
  .C_WIDTH ( LP_LOG_BURST_LEN         ) ,
  .C_INIT  ( {LP_LOG_BURST_LEN{1'b1}} )
)
inst_burst_cntr (
  .clk        ( aclk                 ) ,
  .clken      ( 1'b1                 ) ,
  .rst        ( areset               ) ,
  .load       ( final_transaction    ) ,
  .incr       ( 1'b0                 ) ,
  .decr       ( wxfer                ) ,//0再减1自动恢复init的值
  .load_value ( count_burst_len-1'b1 ) ,//从元组数调整为axi_len规则
  .count      ( wxfers_to_go         ) ,
  .is_zero    ( m_axi_wlast          )
);

assign start_transaction = complete_transaction | final_transaction;
assign complete_transaction = !busy_r & !zero_complete_trans;
assign final_transaction = !busy_r & zero_complete_trans & !final_counter_is_zero & ctrl_result_over;

/////////////////////////////////////////////////////////////////////////////
// AXI Write Address Channel
/////////////////////////////////////////////////////////////////////////////
assign m_axi_awvalid = aw_valid_r;
assign m_axi_awaddr = aw_addr_r;
assign m_axi_awlen = aw_len_r;

assign awxfer = m_axi_awvalid & m_axi_awready;
always @(posedge aclk) begin
  addr_r <= start  ? addr_offset_r :
          awxfer ? addr_r + LP_DW_BYTES*LP_AXI_BURST_LEN :
                   addr_r;
end

always @(posedge aclk) begin
  len_r <=  start  ? (LP_AXI_BURST_LEN- 1) :
          final_transaction ? (count_burst_len - 1'b1 ):
                   len_r;
end

/////////////////////////////////////////////////////////////////////////////
// AXI Write Response Channel
/////////////////////////////////////////////////////////////////////////////
assign m_axi_bready = b_ready_r;

/////////////////////////////////////////////////////////////////////////////
// State Machine
/////////////////////////////////////////////////////////////////////////////
always @ (posedge aclk) begin
    if (areset) begin
        s_state <= S_IDLE;
        aw_valid_r <= 0;
        aw_addr_r <= 0;
        aw_len_r <= 0;
        b_ready_r <= 1'b0;
        busy_r <= 1'b0;
    end else begin
        case(s_state)
            S_IDLE: begin
                if(start_transaction) begin
                    busy_r <= 1'b1;
                    s_state <= S_ADDR;
                end else begin
                    busy_r <= 1'b0;
                end
            end
            S_ADDR: begin
                aw_valid_r <= 1'b1;
                aw_addr_r <= addr_r;
                aw_len_r <= len_r;
                if(awxfer) begin//地址握手
                    aw_valid_r <= 1'b0;
                    s_state = S_DATA;
                end
            end
            S_DATA: begin
                if(m_axi_wlast & wxfer)begin//最后一个数据握手
                    b_ready_r <= 1'b1;
                    s_state <= S_RESP;
                end else begin
                    s_state = S_DATA;
                end
            end
            S_RESP: begin
                if (m_axi_bvalid) begin//响应握手
                    b_ready_r <= 1'b0;
                    busy_r <= 1'b0;
                    aw_len_r <= 0;
                    s_state <= S_IDLE;
                end
            end
        endcase
    end
end

endmodule : ResultWriteMaster
`default_nettype wire