`timescale 1ns / 1ps
`include "para.v"
`default_nettype none

module JoinPipeline#(
    parameter integer WINDOW_TUPLE_WIDTH = `PARA_WINDOW_TUPLE_WIDTH,
    parameter integer STREAM_TUPLE_WIDTH = `PARA_STREAM_TUPLE_WIDTH,
    parameter integer RESULT_PAIR_WIDTH  = `PARA_RESULT_PAIR_WIDTH,
    parameter integer STAGE_NUMS         = `PARA_PIPELINE_STAGE_NUMS
)
(
    aclk,
    stream_stage_full_output,
    stream_stage_clear_input,
    stream_stage_clear_output,
    stream_tuple_input,
    stream_tuple_output,
    window_stage_full_output,
    window_tuple_input,
    window_tuple_output,
	this_result_pair,
    result_stage_feedback_input,
    result_stage_feedback_output
);

input  wire                             aclk;
output wire                             stream_stage_full_output;//低电平表示该周期采样流元组
input  wire                             stream_stage_clear_input;//清空信号输入
output wire                             stream_stage_clear_output;//尾部清空信号观察位
input  wire  [STREAM_TUPLE_WIDTH-1:0]   stream_tuple_input;//流元组输入
output wire  [STREAM_TUPLE_WIDTH-1:0]   stream_tuple_output;//尾部流元组观察位
output wire                             window_stage_full_output;//低电平表示该周期采样窗口元组
input  wire  [WINDOW_TUPLE_WIDTH-1:0]   window_tuple_input;//窗口元组输入
output wire  [WINDOW_TUPLE_WIDTH-1:0]   window_tuple_output;//尾部窗口元祖观察位
output wire  [RESULT_PAIR_WIDTH-1:0]    this_result_pair;//尾部结果元组输出,每个结果只保持一个周期
input  wire                             result_stage_feedback_input;//尾部结果反压暂停信号输入
output wire                             result_stage_feedback_output;//头部反压信号观察位

wire                             stream_stage_full  [0:STAGE_NUMS];
wire                             stream_stage_clear [0:STAGE_NUMS];
wire  [STREAM_TUPLE_WIDTH-1:0]   stream_tuple       [0:STAGE_NUMS];
wire                             window_stage_full  [0:STAGE_NUMS];
wire  [WINDOW_TUPLE_WIDTH-1:0]   window_tuple       [0:STAGE_NUMS];
wire  [RESULT_PAIR_WIDTH-1:0]    result_pair        [0:STAGE_NUMS];
wire                             result_feedback    [0:STAGE_NUMS];
assign  stream_stage_full[STAGE_NUMS] = 1;//尾部阻塞
assign  stream_stage_full_output = stream_stage_full[0];

assign  stream_stage_clear[0] = stream_stage_clear_input;//清空指令
assign  stream_stage_clear_output = stream_stage_clear[STAGE_NUMS];

assign  stream_tuple[0] = stream_tuple_input;//新流元组输入
assign  stream_tuple_output = stream_tuple[STAGE_NUMS];

assign  window_stage_full[STAGE_NUMS] = 0;//尾部开放
assign  window_stage_full_output = window_stage_full[0];

assign  window_tuple[0] = window_tuple_input;//窗口元组输入
assign  window_tuple_output = window_tuple[STAGE_NUMS];

assign  result_pair[0] = 0;//首段无结果
assign  this_result_pair = result_pair[STAGE_NUMS];

assign  result_feedback[STAGE_NUMS] = result_stage_feedback_input;//结果反压输入
assign  result_stage_feedback_output = result_feedback[0];

    genvar i;
    generate for (i = 0; i < STAGE_NUMS; i = i + 1) begin
    JoinCoreStage #(
        .WINDOW_TUPLE_WIDTH(WINDOW_TUPLE_WIDTH),
        .STREAM_TUPLE_WIDTH(STREAM_TUPLE_WIDTH),
        .RESULT_PAIR_WIDTH(RESULT_PAIR_WIDTH)
    )_JoinCoreStage
    (
        .aclk(aclk),
        .stream_stage_full_input(stream_stage_full[i+1]),
        .stream_stage_full_output(stream_stage_full[i]),
        .stream_stage_clear_input(stream_stage_clear[i]),
        .stream_stage_clear_output(stream_stage_clear[i+1]),
        .stream_tuple_input(stream_tuple[i]),
        .this_stream_tuple_output(stream_tuple[i+1]),
        .window_stage_full_input(window_stage_full[i+1]),
        .window_stage_full_output(window_stage_full[i]),
        .window_tuple_input(window_tuple[i]),
        .window_tuple_output(window_tuple[i+1]),
        .result_pair_input(result_pair[i]),
        .this_result_pair(result_pair[i+1]),
        .result_stage_feedback_input(result_feedback[i+1]),
        .result_stage_feedback_output(result_feedback[i])
    );
    end endgenerate
endmodule
