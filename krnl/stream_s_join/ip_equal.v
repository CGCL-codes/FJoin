`timescale 1ns / 1ps
`include "para.v"

//定义变量的位范围
`define UNSIGNED_INT_WIDTH 32
`define _des 63:32
`define _src 31:0
`define _ts 127:64
`define diff 32'd1024
`default_nettype none
module JoinCore#(
    parameter integer WINDOW_TUPLE_WIDTH = `PARA_WINDOW_TUPLE_WIDTH,
    parameter integer STREAM_TUPLE_WIDTH = `PARA_STREAM_TUPLE_WIDTH,
    parameter integer RESULT_PAIR_WIDTH  = `PARA_RESULT_PAIR_WIDTH,
    parameter integer UNSIGNED_INT_WIDTH = `UNSIGNED_INT_WIDTH
)
(
    aclk,
    window_stage_full_output,
    window_tuple_input,
    this_window_tuple,
    window_tuple_flow_enable,
    this_stream_tuple,
    result_pair
);
input  wire                                    aclk;
output wire                                    window_stage_full_output;
input  wire  [WINDOW_TUPLE_WIDTH-1:0]          window_tuple_input;
output wire  [WINDOW_TUPLE_WIDTH-1:0]          this_window_tuple;
input  wire                                    window_tuple_flow_enable;
input  wire  [STREAM_TUPLE_WIDTH-1:0]          this_stream_tuple;
output wire  [RESULT_PAIR_WIDTH-1:0]           result_pair;

reg          [WINDOW_TUPLE_WIDTH-1:0]          window_tuple_reg0  = 0;
reg          [WINDOW_TUPLE_WIDTH-1:0]          window_tuple_reg1  = 0;


wire         stream_tuple_full;
wire         window_tuple_reg0_full;
wire         window_tuple_reg1_full;

wire         window_tuple_input_valid;
wire         input_to_reg0;
wire         reg0_to_reg1;
wire         reg1_to_output;

wire         result_pair_valid;
wire         join_predicate;

reg                                            src_equal_reg      = 0;
reg                                            des_equal_reg      = 0;
wire                                           src_equal_wire;
wire                                           des_equal_wire;

assign window_stage_full_output = window_tuple_reg0_full;
assign this_window_tuple        = window_tuple_reg1;
assign result_pair              = {result_pair_valid, this_stream_tuple[`_stream_tuple], window_tuple_reg1[`_window_tuple]};
assign result_pair_valid        = stream_tuple_full & window_tuple_reg1_full & join_predicate; 

assign stream_tuple_full        = this_stream_tuple [STREAM_TUPLE_WIDTH - 1];
assign window_tuple_reg0_full   = window_tuple_reg0 [WINDOW_TUPLE_WIDTH - 1];
assign window_tuple_reg1_full   = window_tuple_reg1 [WINDOW_TUPLE_WIDTH - 1];

assign window_tuple_input_valid = window_tuple_input[WINDOW_TUPLE_WIDTH - 1];

assign input_to_reg0  = !window_tuple_reg0_full & window_tuple_input_valid;
assign reg0_to_reg1   = !window_tuple_reg1_full & window_tuple_reg0_full;
assign reg1_to_output = window_tuple_flow_enable;//最后一段的流动由流水线框架控制

//计算的中间结果wire
assign src_equal_wire = (this_stream_tuple[`_src] ^ window_tuple_reg0[`_src]) < `diff;
assign des_equal_wire = (this_stream_tuple[`_des] ^ window_tuple_reg0[`_des]) < `diff;

//连接成功生成结果的条件
assign join_predicate = src_equal_reg | des_equal_reg;

always @(posedge aclk) begin
  if (input_to_reg0) begin
      window_tuple_reg0  <= window_tuple_input;
  end else if (reg0_to_reg1) begin
      window_tuple_reg0  <= 0;
  end else begin
      window_tuple_reg0  <= window_tuple_reg0;
  end 
end
//计算的中间结果reg
always @(posedge aclk) begin
  if (reg0_to_reg1) begin
      window_tuple_reg1 <= window_tuple_reg0;
      src_equal_reg     <= src_equal_wire;
      des_equal_reg     <= des_equal_wire;
  end else if (reg1_to_output) begin
      window_tuple_reg1 <= 0;
      src_equal_reg     <= 0;
      des_equal_reg     <= 0;
  end else begin
      window_tuple_reg1 <= window_tuple_reg1;
  end 
end

endmodule