`timescale 1ns / 1ps
`include "para.v"

//定义变量的位范围
`define UNSIGNED_INT_WIDTH 32
`define _longtitude 63:32
`define _latitude 31:0
`define _ts 127:64
`define join_distance_threshold 20

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

reg          [WINDOW_TUPLE_WIDTH-1:0]          window_tuple_reg2  = 0;


wire         stream_tuple_full;
wire         window_tuple_reg0_full;
wire         window_tuple_reg1_full;
wire         window_tuple_reg2_full;
wire         window_tuple_input_valid;
wire         input_to_reg0;
wire         reg0_to_reg1;
wire         reg1_to_reg2;
wire         reg2_to_output;
wire         result_pair_valid;
wire         join_predicate;

reg          [UNSIGNED_INT_WIDTH-1:0]             delta_longtitude_reg        = 0;
reg          [UNSIGNED_INT_WIDTH-1:0]             delta_latitude_reg          = 0;
reg          [UNSIGNED_INT_WIDTH-1:0]             manhattan_distance_reg      = 0;
wire         [UNSIGNED_INT_WIDTH-1:0]             delta_longtitude_wire;
wire         [UNSIGNED_INT_WIDTH-1:0]             delta_latitude_wire;
wire         [UNSIGNED_INT_WIDTH-1:0]             manhattan_distance_wire;

assign window_stage_full_output = window_tuple_reg0_full;
assign this_window_tuple        = window_tuple_reg2;
assign result_pair              = {result_pair_valid, this_stream_tuple[`_stream_tuple], window_tuple_reg2[`_window_tuple]};
assign result_pair_valid        = stream_tuple_full & window_tuple_reg2_full & join_predicate; 

assign stream_tuple_full        = this_stream_tuple [STREAM_TUPLE_WIDTH - 1];
assign window_tuple_reg0_full   = window_tuple_reg0 [WINDOW_TUPLE_WIDTH - 1];
assign window_tuple_reg1_full   = window_tuple_reg1 [WINDOW_TUPLE_WIDTH - 1];
assign window_tuple_reg2_full   = window_tuple_reg2 [WINDOW_TUPLE_WIDTH - 1];
assign window_tuple_input_valid = window_tuple_input[WINDOW_TUPLE_WIDTH - 1];

assign input_to_reg0  = !window_tuple_reg0_full & window_tuple_input_valid;
assign reg0_to_reg1   = !window_tuple_reg1_full & window_tuple_reg0_full;
assign reg1_to_reg2   = !window_tuple_reg2_full & window_tuple_reg1_full;
assign reg2_to_output = window_tuple_flow_enable; //最后一段的流动由流水线框架控制

//计算的中间结果wire
assign delta_longtitude_wire = (this_stream_tuple[`_longtitude] > window_tuple_reg0[`_longtitude] )?
  (this_stream_tuple[`_longtitude] - window_tuple_reg0[`_longtitude]):(window_tuple_reg0[`_longtitude] - this_stream_tuple[`_longtitude]);
assign delta_latitude_wire = (this_stream_tuple[`_latitude] > window_tuple_reg0[`_latitude] )?
  (this_stream_tuple[`_latitude] - window_tuple_reg0[`_latitude]):(window_tuple_reg0[`_latitude] - this_stream_tuple[`_latitude]);

assign manhattan_distance_wire = delta_longtitude_reg + delta_latitude_reg;
//连接成功生成结果的条件
assign join_predicate = manhattan_distance_reg < `join_distance_threshold;

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
      window_tuple_reg1  <= window_tuple_reg0;
      delta_longtitude_reg <= delta_longtitude_wire;
      delta_latitude_reg <= delta_latitude_wire;
  end else if (reg1_to_reg2) begin
      window_tuple_reg1 <= 0;
      delta_longtitude_reg <= 0;
      delta_latitude_reg  <= 0;
  end else begin
      window_tuple_reg1  <= window_tuple_reg1;
  end 
end

always @(posedge aclk) begin
  if (reg1_to_reg2) begin 
      window_tuple_reg2  <= window_tuple_reg1;
      manhattan_distance_reg <= manhattan_distance_wire;
  end else if (reg2_to_output) begin
      window_tuple_reg2  <= 0;
      manhattan_distance_reg <= 0;
  end else begin
      window_tuple_reg2 <= window_tuple_reg2;
  end 
end
endmodule