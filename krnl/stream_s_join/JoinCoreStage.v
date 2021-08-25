
`timescale 1ns / 1ps
`include "para.v"
`default_nettype none

module JoinCoreStage#(
    parameter integer WINDOW_TUPLE_WIDTH = `PARA_WINDOW_TUPLE_WIDTH,
    parameter integer STREAM_TUPLE_WIDTH = `PARA_STREAM_TUPLE_WIDTH,
    parameter integer RESULT_PAIR_WIDTH = `PARA_RESULT_PAIR_WIDTH
)
(
    aclk,
    stream_stage_full_input,
    stream_stage_full_output,
    stream_stage_clear_input,
    stream_stage_clear_output,
    stream_tuple_input,
    this_stream_tuple_output,
    window_stage_full_input,
    window_stage_full_output,
    window_tuple_input,
    window_tuple_output,
    result_pair_input,
    this_result_pair,
    result_stage_feedback_input,
    result_stage_feedback_output
);
input  wire                             aclk;
input  wire                             stream_stage_full_input;
output wire                             stream_stage_full_output;
input  wire                             stream_stage_clear_input;
output wire                             stream_stage_clear_output;
input  wire  [STREAM_TUPLE_WIDTH-1:0]   stream_tuple_input;
output wire  [STREAM_TUPLE_WIDTH-1:0]   this_stream_tuple_output;
input  wire                             window_stage_full_input;
output wire                             window_stage_full_output;
input  wire  [WINDOW_TUPLE_WIDTH-1:0]   window_tuple_input;
output wire  [WINDOW_TUPLE_WIDTH-1:0]   window_tuple_output;
input  wire  [RESULT_PAIR_WIDTH-1:0]    result_pair_input;
output wire  [RESULT_PAIR_WIDTH-1:0]    this_result_pair;
input  wire                             result_stage_feedback_input;
output wire                             result_stage_feedback_output;

wire         [STREAM_TUPLE_WIDTH-1:0]   this_stream_tuple;
wire         [RESULT_PAIR_WIDTH-1:0]    result_pair_submit;
wire                                    result_pair_submit_ack;

assign this_stream_tuple_output = this_stream_tuple;

StreamStage #(
    .STREAM_TUPLE_WIDTH(STREAM_TUPLE_WIDTH)
)_StreamStage
(
    .aclk(aclk),
    .stream_stage_full_input(stream_stage_full_input),
    .stream_stage_full_output(stream_stage_full_output),
    .stream_stage_clear_input(stream_stage_clear_input),
    .stream_stage_clear_output(stream_stage_clear_output),
    .stream_tuple_input(stream_tuple_input),
    .this_stream_tuple(this_stream_tuple)
);

WindowStage #(
    .WINDOW_TUPLE_WIDTH(WINDOW_TUPLE_WIDTH),
    .STREAM_TUPLE_WIDTH(STREAM_TUPLE_WIDTH),
    .RESULT_PAIR_WIDTH(RESULT_PAIR_WIDTH)
)_WindowStage
(
    .aclk(aclk),
    .window_stage_full_input(window_stage_full_input),
    .window_stage_full_output(window_stage_full_output),
    .window_tuple_input(window_tuple_input),
    .window_tuple_output(window_tuple_output),
    .this_stream_tuple(this_stream_tuple),
    .result_pair_submit(result_pair_submit),
    .result_pair_submit_ack(result_pair_submit_ack)
);


ResultStage #(
    .RESULT_PAIR_WIDTH(RESULT_PAIR_WIDTH)
)_ResultStage
(
  .aclk(aclk),
  .result_pair_input(result_pair_input),
  .result_pair_submit(result_pair_submit),
  .result_pair_submit_ack(result_pair_submit_ack),
  .this_result_pair(this_result_pair),
  .result_stage_feedback_input(result_stage_feedback_input),
  .result_stage_feedback_output(result_stage_feedback_output)
);
endmodule
/*********************************************************************
**********************************************************************
*********************************************************************/
module StreamStage#(
    parameter integer STREAM_TUPLE_WIDTH = `PARA_STREAM_TUPLE_WIDTH
)
(
  aclk,
  stream_stage_full_input,
  stream_stage_full_output,
  stream_stage_clear_input,
  stream_stage_clear_output,
  stream_tuple_input,
  this_stream_tuple
);
input  wire                             aclk;
input  wire                             stream_stage_full_input;
output wire                             stream_stage_full_output;
input  wire                             stream_stage_clear_input;
output wire                             stream_stage_clear_output;
input  wire  [STREAM_TUPLE_WIDTH-1:0]   stream_tuple_input;
output wire  [STREAM_TUPLE_WIDTH-1:0]   this_stream_tuple;

reg          [STREAM_TUPLE_WIDTH-1:0]   stream_tuple_reg = 0;
reg                                     clear_reg = 0;

wire                                    stream_tuple_input_valid;
wire                                    stream_tuple_full;

assign stream_stage_full_output  = stream_tuple_full;
assign stream_stage_clear_output = clear_reg;
assign this_stream_tuple = stream_tuple_reg;

assign stream_tuple_input_valid = stream_tuple_input[STREAM_TUPLE_WIDTH-1];
assign stream_tuple_full = stream_tuple_reg[STREAM_TUPLE_WIDTH-1];

always @(posedge aclk) begin
  if (clear_reg | (stream_tuple_full & !stream_stage_full_input)) begin //清空信号 或 满且下段空
      stream_tuple_reg <= 0;
  end else if (!stream_tuple_full & stream_tuple_input_valid) begin // 空且有输入
      stream_tuple_reg <= stream_tuple_input;
  end else begin
      stream_tuple_reg <= stream_tuple_reg;
  end 
end

always @(posedge aclk) begin
  if (stream_stage_clear_input) begin // 清空信号
      clear_reg <= 1;
  end else begin //清空信号只保持一个周期
      clear_reg <= 0;
  end 
end

endmodule
/*********************************************************************
**********************************************************************
*********************************************************************/
module WindowStage#(
    parameter integer WINDOW_TUPLE_WIDTH = `PARA_WINDOW_TUPLE_WIDTH,
    parameter integer STREAM_TUPLE_WIDTH = `PARA_STREAM_TUPLE_WIDTH,
    parameter integer RESULT_PAIR_WIDTH  = `PARA_RESULT_PAIR_WIDTH
)
(
    aclk,
    window_stage_full_input,
    window_stage_full_output,
    window_tuple_input,
    window_tuple_output,
    this_stream_tuple,
    result_pair_submit,
    result_pair_submit_ack
);
input  wire                           aclk;
input  wire                           window_stage_full_input;
output wire                           window_stage_full_output;
input  wire  [WINDOW_TUPLE_WIDTH-1:0] window_tuple_input;
output wire  [WINDOW_TUPLE_WIDTH-1:0] window_tuple_output;
input  wire  [STREAM_TUPLE_WIDTH-1:0] this_stream_tuple;
output wire  [RESULT_PAIR_WIDTH-1:0]  result_pair_submit;
input  wire                           result_pair_submit_ack;

reg                                   joined_reg      = 0;

wire         [WINDOW_TUPLE_WIDTH-1:0] this_window_tuple;
wire                                  window_tuple_reg_full;
wire         [RESULT_PAIR_WIDTH-1:0]  result_pair;
wire                                  join_result_pair_valid;
wire                                  window_tuple_flow_enable;
wire                                  tuple_flow_valid;
wire                                  result_submit_valid;

assign window_tuple_output      = {tuple_flow_valid,this_window_tuple[WINDOW_TUPLE_WIDTH-2:0]};
assign window_tuple_reg_full    = this_window_tuple[WINDOW_TUPLE_WIDTH - 1];
assign result_pair_submit       = {result_submit_valid,result_pair[RESULT_PAIR_WIDTH-2:0]};
assign join_result_pair_valid   = result_pair[RESULT_PAIR_WIDTH - 1];
assign window_tuple_flow_enable = !window_stage_full_input & window_tuple_reg_full &
    (joined_reg | !(join_result_pair_valid & !result_pair_submit_ack)); 
    //下一段空，且提交过结果或不存在连接未能提交的情况下，可以流动
assign tuple_flow_valid         = window_tuple_reg_full & window_tuple_flow_enable;
assign result_submit_valid      = join_result_pair_valid & !joined_reg;

always @(posedge aclk) begin
    if (join_result_pair_valid & result_pair_submit_ack & !window_tuple_flow_enable) begin
        joined_reg <= 1;
    end else if(window_tuple_flow_enable) begin
        joined_reg <= 0;
    end else begin
        joined_reg <= joined_reg;
    end
end

JoinCore #(        
        .WINDOW_TUPLE_WIDTH(WINDOW_TUPLE_WIDTH),
        .STREAM_TUPLE_WIDTH(STREAM_TUPLE_WIDTH),
        .RESULT_PAIR_WIDTH(RESULT_PAIR_WIDTH)
        )
_JoinCore
    (
        .aclk(aclk),
        .window_stage_full_output(window_stage_full_output),
        .window_tuple_input(window_tuple_input),
        .this_window_tuple(this_window_tuple),
        .window_tuple_flow_enable(window_tuple_flow_enable),
        .this_stream_tuple(this_stream_tuple),
        .result_pair(result_pair)
    );

endmodule
/*********************************************************************
**********************************************************************
*********************************************************************/
module ResultStage#(
    parameter integer RESULT_PAIR_WIDTH = `PARA_RESULT_PAIR_WIDTH
)
(
  aclk,
  result_pair_input,
  result_pair_submit,
  result_pair_submit_ack,
  this_result_pair,
  result_stage_feedback_input,
  result_stage_feedback_output

);
input  wire                             aclk;
input  wire  [RESULT_PAIR_WIDTH-1:0]    result_pair_input;
input  wire  [RESULT_PAIR_WIDTH-1:0]    result_pair_submit;
output wire                             result_pair_submit_ack;
output wire  [RESULT_PAIR_WIDTH-1:0]    this_result_pair;
input  wire                             result_stage_feedback_input;
output wire                             result_stage_feedback_output;

reg          [RESULT_PAIR_WIDTH-1:0]    result_pair_reg = 0;
reg                                     feedback_stall  = 0;

wire result_pair_input_valid;
wire result_pair_submit_valid;
assign this_result_pair = result_pair_reg;
assign result_pair_submit_ack = result_pair_submit_valid & !result_pair_input_valid & !feedback_stall;
assign result_stage_feedback_output = feedback_stall;

assign result_pair_input_valid  = result_pair_input  [RESULT_PAIR_WIDTH-1];
assign result_pair_submit_valid = result_pair_submit [RESULT_PAIR_WIDTH-1];

always @(posedge aclk) begin
  if(result_pair_input_valid) begin //总会传递上一流水段的结果
    result_pair_reg <= result_pair_input;
  end else if(result_pair_submit_valid & !feedback_stall) begin
    result_pair_reg <= result_pair_submit;
  end else begin
    result_pair_reg <= 0;
  end
end

always @(posedge aclk) begin
  if (result_stage_feedback_input) begin // 暂停信号
      feedback_stall <= 1;
  end else begin //无暂停信号输入自动清空
      feedback_stall <= 0;
  end 
end

endmodule
`default_nettype wire