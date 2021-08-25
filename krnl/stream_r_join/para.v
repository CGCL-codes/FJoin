`timescale 1ns / 1ps
//定义流水线段数
`define PARA_PIPELINE_STAGE_NUMS 512
//定义元组实际位宽
`define _stream_tuple_width 128
`define _window_tuple_width 128
//计算流水线使用位宽
`define PARA_WINDOW_TUPLE_WIDTH (`_window_tuple_width + 1)
`define PARA_STREAM_TUPLE_WIDTH (`_stream_tuple_width + 1)
`define PARA_RESULT_PAIR_WIDTH (`PARA_WINDOW_TUPLE_WIDTH + `PARA_STREAM_TUPLE_WIDTH - 1)
`define _stream_tuple `PARA_STREAM_TUPLE_WIDTH-2:0
`define _window_tuple `PARA_WINDOW_TUPLE_WIDTH-2:0
