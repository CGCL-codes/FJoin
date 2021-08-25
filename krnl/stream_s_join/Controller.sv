`include "para.v"
// default_nettype of none prevents implicit wire declaration.
`default_nettype none

module Controller #(
  // Set to the address width of the interface
  parameter integer C_M_AXI_ADDR_WIDTH  = 64,
  // Set the data width of the interface
  // Range: 32, 64, 128, 256, 512, 1024
  parameter integer C_M_AXI_DATA_WIDTH  = 512,
  parameter integer STAGE_NUMS          = `PARA_PIPELINE_STAGE_NUMS
)
(
  input  wire                            aclk,
  input  wire                            areset,
  input  wire                            ctrl_start,              // Pulse high for one cycle to begin reading
  output wire                            ctrl_done,               // Pulses high for one cycle when transfer request is complete

  output wire                            ctrl_stream_start,
  input  wire                            ctrl_stream_done,
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]   stream,
  input  wire [31:0]                     stream_length,
  input  wire                            stream_reader_tvalid,
  input  wire                            stream_pipeline_tready,
  output wire                            crtl_stream_load,
  output wire                            ctrl_stream_stage_clear,

  output wire                            ctrl_info_start,
  input  wire                            ctrl_info_done,
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]   info,
  output wire [C_M_AXI_DATA_WIDTH-1:0]   device_info,

  output wire                            ctrl_window_start,
  input  wire                            ctrl_window_done,
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]   window,
  input  wire [31:0]                     window_length,
  input  wire                            window_reader_tvalid,
  input  wire                            window_pipeline_tready,
  output wire                            crtl_window_load,
  input  wire                            window_pipeline_tail_valid,

  output wire                            ctrl_result_start,
  input  wire                            ctrl_result_done,
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]   result,
  input  wire [C_M_AXI_DATA_WIDTH-1:0]   result_max,
  output wire                            ctrl_result_over,
  input  wire                            result_pipeline_tvalid,
  output wire                            crtl_result_write
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

/////////////////////////////////////////////////////////////////////////////
// Local Parameters
/////////////////////////////////////////////////////////////////////////////
localparam integer LP_DW_BYTES                   = C_M_AXI_DATA_WIDTH/8;
localparam integer LP_MAX_BURST_LENGTH           = 256;   // Max AXI Protocol burst length
localparam integer LP_MAX_BURST_BYTES            = 4096;  // Max AXI Protocol burst size in bytes
localparam integer LP_AXI_BURST_LEN              = f_min(LP_MAX_BURST_BYTES/LP_DW_BYTES, LP_MAX_BURST_LENGTH);
localparam [C_M_AXI_ADDR_WIDTH-1:0] LP_ADDR_MASK = LP_DW_BYTES*LP_AXI_BURST_LEN - 1;
localparam [31:0]  STAGE_NUMS_WIRE               = STAGE_NUMS;
localparam [31:0]  STAGE_NUMS_PLUS               = STAGE_NUMS + 3;
localparam S_IDLE  = 3'b000;
localparam S_INIT  = 3'b001;
localparam S_LOAD  = 3'b010;
localparam S_JOIN  = 3'b110;
localparam S_OVER  = 3'b111;
localparam S_DONE  = 3'b101;
/////////////////////////////////////////////////////////////////////////////
// Variables
/////////////////////////////////////////////////////////////////////////////
logic         done;
logic         ctrl_start_d1            = 1'b0;
logic         start                    = 1'b0;
// --- state machine
logic [2:0]   s_state                  = S_IDLE;           
logic         busy_r                   = 1'b0;
logic [31:0]  stream_length_r          = 32'b0;
logic [31:0]  window_length_r          = 32'b0;
logic [31:0]  result_max_r             = 32'b0;
logic [63:0]  stream_r                 = 64'b0;
logic [63:0]  window_r                 = 64'b0;
logic [63:0]  result_r                 = 64'b0;
logic [63:0]  info_r                   = 64'b0;
logic         invalid_input_r          = 1'b0;
logic         stream_reader_start_r    = 1'b0;
logic         result_writer_start_r    = 1'b0;
logic         window_reader_start_r    = 1'b0;
logic         window_reader_done_r     = 1'b0;
logic         stream_stage_clear_r     = 1'b0;
logic         result_over_r            = 1'b0;
logic         stream_reader_done_r     = 1'b0;
logic         result_writer_done_r     = 1'b0;
logic         info_start_r             = 1'b0;
logic         info_start_reminder      = 1'b0;
logic         info_wirter_done_r       = 1'b0;
logic         invalid_stream_length_r  = 1'b0;
logic         invalid_window_length_r  = 1'b0;
logic         invalid_result_max_r     = 1'b0;
logic         invalid_stream_address_r = 1'b0;
logic         invalid_window_address_r = 1'b0;
logic         invalid_result_address_r = 1'b0;
logic         invalid_info_address_r   = 1'b0;
logic [31:0]  dbg_stream_to_go;
logic         valid_start;
logic         restart_join;
logic [31:0]  stream_in_pipeline;
logic [31:0]  dbg_window_to_go;
logic         start_join;
logic         window_reminder_is_zero;
logic         join_over;
logic [31:0]  dbg_clear_to_go;
logic         clear_done;
logic         stream_reminder_is_zero;
logic         stream_pipeline_empty;
logic         dbg_no_result_write;
logic [31:0]  write_result_num;
logic         process_done;
logic         result_buffer_full;

/////////////////////////////////////////////////////////////////////////////
// Control logic
/////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////
// S_IDLE
/////////////////////////////////////////////////////////////////////////////
//start之前对所有输入参数进行采样,判断输入参数是否合法
always @(posedge aclk) begin
  ctrl_start_d1 <= ctrl_start;
end

always @(posedge aclk) begin //采样所有输入的参数
  if (ctrl_start) begin
    stream_length_r <= stream_length;
    window_length_r <= window_length;
    result_max_r <= result_max;
    stream_r <= stream;
    window_r <= window;
    result_r <= result;
    info_r <= info;
  end
end

always @(posedge aclk) begin
  start <= ctrl_start_d1;
end

always @(posedge aclk) begin //采样所有输入的参数
  if (ctrl_start_d1) begin
    invalid_stream_length_r  <= (stream_length_r <= 0);
    invalid_window_length_r  <= (window_length_r <= 0);
    invalid_result_max_r     <= (result_max_r    <= 0);
    invalid_stream_address_r <= ((stream_r  &  LP_ADDR_MASK) != 0);
    invalid_window_address_r <= ((window_r  &  LP_ADDR_MASK) != 0);
    invalid_result_address_r <= ((result_r  &  LP_ADDR_MASK) != 0);
    invalid_info_address_r   <= ((info_r    &  LP_ADDR_MASK) != 0);
  end
end


always @(posedge aclk) begin //计算是否为不合法输入
  if(areset | done)begin
    invalid_input_r <= 0;
  end else if(start) begin
    invalid_input_r <= 
      invalid_stream_length_r | invalid_window_length_r | invalid_result_max_r |
      invalid_stream_address_r | invalid_window_address_r | invalid_result_address_r | invalid_info_address_r;
  end
end

/////////////////////////////////////////////////////////////////////////////
// S_INIT//INIT状态只停留一个周期
/////////////////////////////////////////////////////////////////////////////
//向stream reader发start信号
assign valid_start = (s_state == S_INIT) & !invalid_input_r;
always @(posedge aclk) begin
  if(areset)begin
    stream_reader_start_r <= 1'b0;
  end else if(valid_start) begin
    stream_reader_start_r <= 1'b1;
  end else begin
    stream_reader_start_r <= 1'b0;
  end
end
assign ctrl_stream_start = stream_reader_start_r;

//向result writer发start信号
always @(posedge aclk) begin
  if(areset)begin
    result_writer_start_r <= 1'b0;
  end else if(valid_start) begin
    result_writer_start_r <= 1'b1;
  end else begin
    result_writer_start_r <= 1'b0;
  end
end
assign ctrl_result_start = result_writer_start_r;

//stream总计数器在进入连接时载入初值,每流入流水线一个减去一
example_counter #(
  .C_WIDTH ( 32                         ) ,
  .C_INIT  ( {32{1'b0}}                 )
)
stream_reminder_cntr (
  .clk        ( aclk                    ) ,
  .clken      ( 1'b1                    ) ,
  .rst        ( areset                  ) ,
  .load       ( valid_start             ) ,
  .incr       ( 1'b0                    ) ,
  .decr       ( crtl_stream_load        ) ,
  .load_value ( stream_length_r         ) ,
  .count      ( dbg_stream_to_go        ) ,
  .is_zero    ( stream_reminder_is_zero )
);

/////////////////////////////////////////////////////////////////////////////
// S_LOAD
/////////////////////////////////////////////////////////////////////////////
assign crtl_stream_load = (s_state == S_LOAD) & stream_reader_tvalid & stream_pipeline_tready;

// 计算load状态流入流水线的stream元组个数
example_counter #(
  .C_WIDTH ( 32                            ) ,
  .C_INIT  ( {32{1'b0}}                    )
)
in_pipeline_stream_reminder_cntr (
  .clk        ( aclk                       ) ,
  .clken      ( 1'b1                       ) ,
  .rst        ( areset                     ) ,
  .load       ( valid_start | restart_join ) ,
  .incr       ( crtl_stream_load           ) ,
  .decr       ( 1'b0                       ) ,
  .load_value ( {32{1'b0}}                 ) ,
  .count      ( stream_in_pipeline         ) ,
  .is_zero    ( stream_pipeline_empty      )
);

assign start_join = (s_state == S_LOAD) & 
  ((stream_in_pipeline == STAGE_NUMS_WIRE) | stream_reminder_is_zero);
//这里默认window元组不会追上stream元组,所以填充满可以直接进入join状态

/////////////////////////////////////////////////////////////////////////////
// S_JOIN
/////////////////////////////////////////////////////////////////////////////
//向window reader发start信号
always @(posedge aclk) begin
  if(areset)begin
    window_reader_start_r <= 1'b0;
  end else if(start_join) begin
    window_reader_start_r <= 1'b1;
  end else begin
    window_reader_start_r <= 1'b0;
  end
end
assign ctrl_window_start = window_reader_start_r;

assign crtl_window_load = (s_state == S_JOIN) & window_reader_tvalid & window_pipeline_tready;

//计算流出流水线window元组个数
example_counter #(
  .C_WIDTH ( 32                            ) ,
  .C_INIT  ( {32{1'b0}}                    )
)
window_reminder_cntr (
  .clk        ( aclk                       ) ,
  .clken      ( 1'b1                       ) ,
  .rst        ( areset                     ) ,
  .load       ( start_join                 ) ,
  .incr       ( 1'b0                       ) ,
  .decr       ( window_pipeline_tail_valid ) ,
  .load_value ( window_length_r            ) ,
  .count      ( dbg_window_to_go           ) ,
  .is_zero    ( window_reminder_is_zero    )
);

//记录window reader的done信号
always @(posedge aclk) begin
  if(areset | start_join | join_over)begin
    window_reader_done_r <= 1'b0;
  end else if(ctrl_window_done)begin
    window_reader_done_r <= 1'b1;
  end else begin
    window_reader_done_r <= window_reader_done_r;
  end
end
assign join_over = (s_state == S_JOIN) & window_reminder_is_zero & window_reader_done_r;

/////////////////////////////////////////////////////////////////////////////
// S_OVER
/////////////////////////////////////////////////////////////////////////////

//向pipeline发clear信号,该信号流水传递源头只需保持一个周期
always @(posedge aclk) begin
  if(areset)begin
    stream_stage_clear_r <= 1'b0;
  end else if(join_over) begin
    stream_stage_clear_r <= 1'b1;
  end else begin
    stream_stage_clear_r <= 1'b0;
  end
end
assign ctrl_stream_stage_clear = stream_stage_clear_r;

//计算CLEAR周期数
example_counter #(
  .C_WIDTH ( 32                      ) ,
  .C_INIT  ( {32{1'b0}}              )
)
clear_reminder_cntr (
  .clk        ( aclk                 ) ,
  .clken      ( 1'b1                 ) ,
  .rst        ( areset               ) ,
  .load       ( join_over            ) ,
  .incr       ( 1'b0                 ) ,
  .decr       ( 1'b1                 ) ,
  .load_value ( STAGE_NUMS_PLUS      ) ,
  .count      ( dbg_clear_to_go      ) ,
  .is_zero    ( clear_done           )
);
assign process_done = (s_state == S_OVER) & clear_done & stream_reminder_is_zero;
assign restart_join = (s_state == S_OVER) & clear_done & !stream_reminder_is_zero;

/////////////////////////////////////////////////////////////////////////////
// S_DONE
/////////////////////////////////////////////////////////////////////////////
//记录stream reader的done信号
always @(posedge aclk) begin
  if(areset | done)begin
    stream_reader_done_r <= 1'b0;
  end else if(ctrl_stream_done)begin
    stream_reader_done_r <= 1'b1;
  end else begin
    stream_reader_done_r <= stream_reader_done_r;
  end
end

assign crtl_result_write = (s_state != S_IDLE) & result_pipeline_tvalid & !result_buffer_full;
// 记录写结果的个数
example_counter #(
  .C_WIDTH ( 32                     ) ,
  .C_INIT  ( {32{1'b0}}             )
)
write_result_reminder_cntr (
  .clk        ( aclk                ) ,
  .clken      ( 1'b1                ) ,
  .rst        ( areset              ) ,
  .load       ( start | done        ) ,
  .incr       ( crtl_result_write   ) ,
  .decr       ( 1'b0                ) ,
  .load_value ( {32{1'b0}}          ) ,
  .count      ( write_result_num    ) ,
  .is_zero    ( dbg_no_result_write )
);
assign result_buffer_full = (write_result_num != 0) && (write_result_num == result_max_r);
//这里判断非0是防止result_max值错误时错发信号

//向result writer发ctrl_result_over信号,该信号高电平有效需要保持
always @(posedge aclk) begin
  if(areset | done)begin
    result_over_r <= 1'b0;
  end else if(process_done | result_buffer_full) begin
    result_over_r <= 1'b1;
  end else begin
    result_over_r <= result_over_r;
  end
end
assign ctrl_result_over = result_over_r;

//记录result writer的done信号
always @(posedge aclk) begin
  if(areset | done)begin
    result_writer_done_r <= 1'b0;
  end else if(ctrl_result_done)begin
    result_writer_done_r <= 1'b1;
  end else begin
    result_writer_done_r <= result_writer_done_r;
  end
end

//stream、result都完成后,向info writer发start信号
always @(posedge aclk) begin
  if (areset | done) begin
    info_start_r <= 1'b0;
    info_start_reminder <= 1'b0;
  end
  else begin
    info_start_r <= info_start_r ? 
      0 : !info_start_reminder & (s_state == S_DONE) & (stream_reader_done_r & result_writer_done_r);
    info_start_reminder <= (s_state == S_DONE) & (stream_reader_done_r & result_writer_done_r) ? 1'b1 : info_start_reminder;
  end
end
assign ctrl_info_start = info_start_r;

assign device_info = { {(C_M_AXI_DATA_WIDTH-384){1'b0}},
   stream_r, window_r, result_r, info_r, stream_length_r, window_length_r, result_max_r, write_result_num};

//记录info writer的done信号
always @(posedge aclk) begin
  if(areset | done)begin
    info_wirter_done_r <= 1'b0;
  end else if(ctrl_info_done)begin
    info_wirter_done_r <= 1'b1;
  end else begin
    info_wirter_done_r <= info_wirter_done_r;
  end
end

//正常结束,非正常结束都要产生done脉冲
assign done = (s_state == S_DONE) & (invalid_input_r || info_wirter_done_r);
assign ctrl_done = done;

/*
//dbg模式, 改成无论输入正确与否都执行设备信息的写入
//stream、result都完成后,向info writer发start信号
always @(posedge aclk) begin
  if(areset | done)begin
    stream_result_done_r <= 2'b00;
  end else begin
    stream_result_done_r <= (stream_result_done_r | {stream_reader_done_r, result_writer_done_r});
  end
end

// info start logic
always @(posedge aclk) begin
  if (areset | done) begin
    info_start_r <= 1'b0;
    info_start_reminder <= 1'b0;
  end
  else begin
    info_start_r <= info_start_r ? 
      0 : !info_start_reminder & (s_state == S_DONE) & (invalid_input_r | &stream_result_done_r);
    info_start_reminder <= (s_state == S_DONE) & (invalid_input_r | &stream_result_done_r) ? 1'b1 : info_start_reminder;
  end
end
assign ctrl_info_start = info_start_r;

assign device_info = { {(C_M_AXI_DATA_WIDTH-384){1'b0}},
   stream_r, window_r, result_r, info_r, stream_length_r, window_length_r, result_max_r, write_result_num};

//记录info writer的done信号
always @(posedge aclk) begin
  if(areset | done)begin
    info_wirter_done_r <= 1'b0;
  end else if(ctrl_info_done)begin
    info_wirter_done_r <= 1'b1;
  end else begin
    info_wirter_done_r <= info_wirter_done_r;
  end
end

//正常结束,非正常结束都要写入设备信息,都要产生done脉冲
assign ctrl_done =  done;
assign done = (s_state == S_DONE) & (info_wirter_done_r);
*/

/////////////////////////////////////////////////////////////////////////////
// State Machine
/////////////////////////////////////////////////////////////////////////////
always @ (posedge aclk) begin
    if (areset) begin
        s_state <= S_IDLE;
        busy_r <= 1'b0;
    end else begin
        case(s_state)
            S_IDLE: begin
                if(start) begin
                    busy_r <= 1'b1;
                    s_state <= S_INIT;
                end else begin
                    busy_r <= 1'b0;
                end
            end
            S_INIT: begin
                //检查输入合法,向stream reader发开始信号
                if(invalid_input_r) begin//不合法的输入
                    s_state <= S_DONE;
                end else begin
                    s_state <= S_LOAD;
                end
            end
            S_LOAD: begin
                //等待计数器表示装入结束,向window reader发开始信号
                if(start_join)begin
                    s_state <= S_JOIN;
                end
            end
            S_JOIN: begin
                //等待计数器和window reader都结束,发clear信号
                if(join_over)begin
                    s_state <= S_OVER;
                end
            end
            S_OVER: begin
                //等待判定是否要继续连接
                if(process_done) begin
                    s_state <= S_DONE;
                end else if(restart_join)begin
                    s_state <= S_LOAD;
                end
            end
            S_DONE: begin
                if (done) begin//结束脉冲
                    busy_r <= 1'b0;
                    s_state <= S_IDLE;
                end
            end
        endcase
    end
end

endmodule : Controller
`default_nettype wire