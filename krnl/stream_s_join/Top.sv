`include "para.v"
// default_nettype of none prevents implicit wire declaration.
`default_nettype none
module fpga_join_example #(
  parameter integer C_M_AXI_ADDR_WIDTH  = 64,
  parameter integer C_M_AXI_DATA_WIDTH  = 512,
  parameter integer C_XFER_SIZE_WIDTH   = C_M_AXI_ADDR_WIDTH,
  parameter integer WINDOW_TUPLE_WIDTH  = `PARA_WINDOW_TUPLE_WIDTH,
  parameter integer STREAM_TUPLE_WIDTH  = `PARA_STREAM_TUPLE_WIDTH,
  parameter integer RESULT_PAIR_WIDTH   = `PARA_RESULT_PAIR_WIDTH,
  parameter integer STAGE_NUMS          = `PARA_PIPELINE_STAGE_NUMS,
  parameter integer C_MAX_OUTSTANDING   = 16,
  parameter integer C_INCLUDE_DATA_FIFO = 1
)
(
    // System Signals
  input  wire                              ap_clk         ,
  input  wire                              ap_rst_n       ,
  // AXI4 master interface m00_axi
  output wire                              m00_axi_awvalid,
  input  wire                              m00_axi_awready,
  output wire [C_M_AXI_ADDR_WIDTH-1:0]     m00_axi_awaddr ,
  output wire [8-1:0]                      m00_axi_awlen  ,
  output wire                              m00_axi_wvalid ,
  input  wire                              m00_axi_wready ,
  output wire [C_M_AXI_DATA_WIDTH-1:0]     m00_axi_wdata  ,
  output wire [C_M_AXI_DATA_WIDTH/8-1:0]   m00_axi_wstrb  ,
  output wire                              m00_axi_wlast  ,
  input  wire                              m00_axi_bvalid ,
  output wire                              m00_axi_bready ,
  output wire                              m00_axi_arvalid,
  input  wire                              m00_axi_arready,
  output wire [C_M_AXI_ADDR_WIDTH-1:0]     m00_axi_araddr ,
  output wire [8-1:0]                      m00_axi_arlen  ,
  input  wire                              m00_axi_rvalid ,
  output wire                              m00_axi_rready ,
  input  wire [C_M_AXI_DATA_WIDTH-1:0]     m00_axi_rdata  ,
  input  wire                              m00_axi_rlast  ,
  // AXI4 master interface m01_axi
  output wire                              m01_axi_awvalid,
  input  wire                              m01_axi_awready,
  output wire [C_M_AXI_ADDR_WIDTH-1:0]     m01_axi_awaddr ,
  output wire [8-1:0]                      m01_axi_awlen  ,
  output wire                              m01_axi_wvalid ,
  input  wire                              m01_axi_wready ,
  output wire [C_M_AXI_DATA_WIDTH-1:0]     m01_axi_wdata  ,
  output wire [C_M_AXI_DATA_WIDTH/8-1:0]   m01_axi_wstrb  ,
  output wire                              m01_axi_wlast  ,
  input  wire                              m01_axi_bvalid ,
  output wire                              m01_axi_bready ,
  output wire                              m01_axi_arvalid,
  input  wire                              m01_axi_arready,
  output wire [C_M_AXI_ADDR_WIDTH-1:0]     m01_axi_araddr ,
  output wire [8-1:0]                      m01_axi_arlen  ,
  input  wire                              m01_axi_rvalid ,
  output wire                              m01_axi_rready ,
  input  wire [C_M_AXI_DATA_WIDTH-1:0]     m01_axi_rdata  ,
  input  wire                              m01_axi_rlast  ,
  // Control Signals
  input  wire                              ap_start       ,
  output wire                              ap_done        ,
  input  wire [32-1:0]                     stream_length  ,
  input  wire [32-1:0]                     window_length  ,
  input  wire [32-1:0]                     result_max     ,
  input  wire [64-1:0]                     result         ,   
  input  wire [64-1:0]                     stream         ,
  input  wire [64-1:0]                     info           ,   
  input  wire [64-1:0]                     window         
);
timeunit 1ps;
timeprecision 1ps;

///////////////////////////////////////////////////////////////////////////////
// Local Parameters
///////////////////////////////////////////////////////////////////////////////
localparam integer LP_DW_BYTES          = C_M_AXI_DATA_WIDTH/8;
localparam integer LP_LOG_DW_BYTES      = $clog2(LP_DW_BYTES);
localparam integer C_M00_AXI_ADDR_WIDTH = C_M_AXI_ADDR_WIDTH;
localparam integer C_M00_AXI_DATA_WIDTH = C_M_AXI_DATA_WIDTH;
localparam integer C_M01_AXI_ADDR_WIDTH = C_M_AXI_ADDR_WIDTH;
localparam integer C_M01_AXI_DATA_WIDTH = C_M_AXI_DATA_WIDTH;

///////////////////////////////////////////////////////////////////////////////
// Wires and Variables
///////////////////////////////////////////////////////////////////////////////
logic                          areset                         = 1'b0;
logic                          ctrl_done;
logic [C_XFER_SIZE_WIDTH-1:0]  stream_xfer_bytes_r = 0;
logic [C_XFER_SIZE_WIDTH-1:0]  window_xfer_bytes_r = 0;

logic                          ctrl_stream_start;                             
logic                          ctrl_stream_done;                                                                                  
logic                          stream_reader_tvalid;                             
logic                          stream_pipeline_tready;                             
logic                          crtl_stream_load;                             
logic                          ctrl_stream_stage_clear;                             
logic [STREAM_TUPLE_WIDTH-2:0] stream_tuple_data;
logic [C_M_AXI_DATA_WIDTH-1:0] stream_tupe_tdata;
logic                          stream_stage_full_output;

logic                          ctrl_info_start;                             
logic                          ctrl_info_done;                                                          
logic [C_M_AXI_DATA_WIDTH-1:0] device_info;                             

logic                          ctrl_window_start;                             
logic                          ctrl_window_done;                                                                                   
logic                          window_reader_tvalid;                             
logic                          window_pipeline_tready;                             
logic                          crtl_window_load;                             
logic                          window_pipeline_tail_valid;                             
logic [WINDOW_TUPLE_WIDTH-2:0] window_tuple_data;
logic [WINDOW_TUPLE_WIDTH-2:0] window_tail_data;
logic [C_M_AXI_DATA_WIDTH-1:0] window_tupe_tdata;
logic                          window_stage_full_output;

logic                          ctrl_result_start;                             
logic                          ctrl_result_done;                                                                                   
logic                          ctrl_result_over;                             
logic                          result_pipeline_tvalid;                             
logic                          crtl_result_write;
logic [RESULT_PAIR_WIDTH-2:0]  result_pair_data;
logic [C_M_AXI_DATA_WIDTH-1:0] result_pair_tdata;
logic                          result_writer_tready;
//dbg
logic                          stream_stage_clear_output;
logic [STREAM_TUPLE_WIDTH-1:0] stream_tuple_output;
logic                          result_stage_feedback_output;
logic                          stream_reader_axis_tlast;
logic                          window_reader_axis_tlast;

// Register and invert reset signal.
always @(posedge ap_clk) begin
  areset <= ~ap_rst_n;
end

// Done logic
assign ap_done = ctrl_done;

//计算stream和window的传输字节数
always @(posedge ap_clk) begin
  if (areset | ap_done) begin
    stream_xfer_bytes_r <= 0;
  end
  else if(ap_start) begin
    stream_xfer_bytes_r <= stream_length << LP_LOG_DW_BYTES;
  end
end

always @(posedge ap_clk) begin
  if (areset | ap_done) begin
    window_xfer_bytes_r <= 0;
  end
  else if(ap_start) begin
    window_xfer_bytes_r <= window_length << LP_LOG_DW_BYTES;
  end
end

ResultWriteMaster #(
  .C_M_AXI_ADDR_WIDTH ( C_M_AXI_ADDR_WIDTH ),
  .C_M_AXI_DATA_WIDTH ( C_M_AXI_DATA_WIDTH ),
  .STAGE_NUMS         ( STAGE_NUMS         )
)_ResultWriteMaster
(
  .aclk             ( ap_clk               ),
  .areset           ( 1'b0                 ),
  //controller
  .ctrl_start       ( ctrl_result_start    ),// Pulse high for one cycle to begin reading
  .ctrl_done        ( ctrl_result_done     ),// Pulses high for one cycle when transfer request is complete
  .ctrl_addr_offset ( result               ),// Starting Address offset
  .ctrl_result_over ( ctrl_result_over     ), 
  //output axi signals
  .m_axi_awvalid    ( m00_axi_awvalid      ),
  .m_axi_awready    ( m00_axi_awready      ),
  .m_axi_awaddr     ( m00_axi_awaddr       ),
  .m_axi_awlen      ( m00_axi_awlen        ),
  .m_axi_wvalid     ( m00_axi_wvalid       ),
  .m_axi_wready     ( m00_axi_wready       ),
  .m_axi_wdata      ( m00_axi_wdata        ),
  .m_axi_wstrb      ( m00_axi_wstrb        ),
  .m_axi_wlast      ( m00_axi_wlast        ),
  .m_axi_bvalid     ( m00_axi_bvalid       ),
  .m_axi_bready     ( m00_axi_bready       ),
  //controller
  .s_axis_tvalid    ( crtl_result_write    ),
  .s_axis_tready    ( result_writer_tready ),
  //pipeline
  .s_axis_tdata     ( result_pair_tdata    )
);

example_axi_read_master #(
  .C_M_AXI_ADDR_WIDTH  ( C_M_AXI_ADDR_WIDTH  ),
  .C_M_AXI_DATA_WIDTH  ( C_M_AXI_DATA_WIDTH  ),
  .C_XFER_SIZE_WIDTH   ( C_M_AXI_ADDR_WIDTH  ),
  .C_MAX_OUTSTANDING   ( C_MAX_OUTSTANDING   ),
  .C_INCLUDE_DATA_FIFO ( C_INCLUDE_DATA_FIFO )
)_stream_axi_read_master
(
  .aclk                    ( ap_clk                   ),
  .areset                  ( 1'b0                     ),
  //controller
  .ctrl_start              ( ctrl_stream_start        ),// Pulse high for one cycle to begin reading
  .ctrl_done               ( ctrl_stream_done         ),// Pulses high for one cycle when transfer request is complete
  .ctrl_addr_offset        ( stream                   ),// Starting Address offset
  .ctrl_xfer_size_in_bytes ( stream_xfer_bytes_r      ),// Length in number of bytes(), limited by the address width.
  //output axi signals
  .m_axi_arvalid           ( m00_axi_arvalid          ),
  .m_axi_arready           ( m00_axi_arready          ),
  .m_axi_araddr            ( m00_axi_araddr           ),
  .m_axi_arlen             ( m00_axi_arlen            ),
  .m_axi_rvalid            ( m00_axi_rvalid           ),
  .m_axi_rready            ( m00_axi_rready           ),
  .m_axi_rdata             ( m00_axi_rdata            ),
  .m_axi_rlast             ( m00_axi_rlast            ),
  .m_axis_aclk             ( ap_clk                   ),
  .m_axis_areset           ( 1'b0                     ),
  //controller
  .m_axis_tvalid           ( stream_reader_tvalid     ),
  .m_axis_tready           ( crtl_stream_load         ),
  //pipeline
  .m_axis_tdata            ( stream_tupe_tdata        ),
  //drop
  .m_axis_tlast            ( stream_reader_axis_tlast )
);

DeviceInfoWriteMaster #(
  .C_M_AXI_ADDR_WIDTH ( C_M_AXI_ADDR_WIDTH ),
  .C_M_AXI_DATA_WIDTH ( C_M_AXI_DATA_WIDTH )
)_DeviceInfoWriteMaster
(
  .aclk             ( ap_clk          ),
  .areset           ( 1'b0            ),
  //controller
  .ctrl_start       ( ctrl_info_start ),// Pulse high for one cycle to begin reading
  .ctrl_done        ( ctrl_info_done  ),// Pulses high for one cycle when transfer request is complete
  .ctrl_addr_offset ( info            ),// Starting Address offset
  .ctrl_device_info ( device_info     ), 
  //output axi signals
  .m_axi_awvalid    ( m01_axi_awvalid ),
  .m_axi_awready    ( m01_axi_awready ),
  .m_axi_awaddr     ( m01_axi_awaddr  ),
  .m_axi_awlen      ( m01_axi_awlen   ),
  .m_axi_wvalid     ( m01_axi_wvalid  ),
  .m_axi_wready     ( m01_axi_wready  ),
  .m_axi_wdata      ( m01_axi_wdata   ),
  .m_axi_wstrb      ( m01_axi_wstrb   ),
  .m_axi_wlast      ( m01_axi_wlast   ),
  .m_axi_bvalid     ( m01_axi_bvalid  ),
  .m_axi_bready     ( m01_axi_bready  )
);

example_axi_read_master #(
  .C_M_AXI_ADDR_WIDTH  ( C_M_AXI_ADDR_WIDTH  ),
  .C_M_AXI_DATA_WIDTH  ( C_M_AXI_DATA_WIDTH  ),
  .C_XFER_SIZE_WIDTH   ( C_M_AXI_ADDR_WIDTH  ),
  .C_MAX_OUTSTANDING   ( C_MAX_OUTSTANDING   ),
  .C_INCLUDE_DATA_FIFO ( C_INCLUDE_DATA_FIFO )
)_window_axi_read_master
(
  .aclk                    ( ap_clk                   ),
  .areset                  ( 1'b0                     ),
  //controller
  .ctrl_start              ( ctrl_window_start        ),// Pulse high for one cycle to begin reading
  .ctrl_done               ( ctrl_window_done         ),// Pulses high for one cycle when transfer request is complete
  .ctrl_addr_offset        ( window                   ),// Starting Address offset
  .ctrl_xfer_size_in_bytes ( window_xfer_bytes_r      ),// Length in number of bytes(), limited by the address width.
  //output axi signals
  .m_axi_arvalid           ( m01_axi_arvalid          ),
  .m_axi_arready           ( m01_axi_arready          ),
  .m_axi_araddr            ( m01_axi_araddr           ),
  .m_axi_arlen             ( m01_axi_arlen            ),
  .m_axi_rvalid            ( m01_axi_rvalid           ),
  .m_axi_rready            ( m01_axi_rready           ),
  .m_axi_rdata             ( m01_axi_rdata            ),
  .m_axi_rlast             ( m01_axi_rlast            ),
  .m_axis_aclk             ( ap_clk                   ),
  .m_axis_areset           ( 1'b0                     ),
  //controller
  .m_axis_tvalid           ( window_reader_tvalid     ),
  .m_axis_tready           ( crtl_window_load         ),
  //pipeline
  .m_axis_tdata            ( window_tupe_tdata        ),
  //drop
  .m_axis_tlast            ( window_reader_axis_tlast )
);

JoinPipeline #(
  .WINDOW_TUPLE_WIDTH ( WINDOW_TUPLE_WIDTH ),
  .STREAM_TUPLE_WIDTH ( STREAM_TUPLE_WIDTH ),
  .RESULT_PAIR_WIDTH  ( RESULT_PAIR_WIDTH  ),
  .STAGE_NUMS         ( STAGE_NUMS         )
)_JoinPipeline
(
  .aclk                         ( ap_clk                                             ),
  .stream_stage_full_output     ( stream_stage_full_output                           ),//controller
  .stream_stage_clear_input     ( ctrl_stream_stage_clear                            ),//controller
  .stream_stage_clear_output    ( stream_stage_clear_output                          ),//drop
  .stream_tuple_input           ( { crtl_stream_load           , stream_tuple_data } ),//controller + sreader
  .stream_tuple_output          ( stream_tuple_output                                ),//drop
  .window_stage_full_output     ( window_stage_full_output                           ),//controller
  .window_tuple_input           ( { crtl_window_load           , window_tuple_data } ),//controller + wreader
  .window_tuple_output          ( { window_pipeline_tail_valid , window_tail_data  } ),//controller
  .this_result_pair             ( { result_pipeline_tvalid     , result_pair_data  } ),//controller + rwriter
  .result_stage_feedback_input  ( result_writer_tready                               ),//rwriter
  .result_stage_feedback_output ( result_stage_feedback_output                       ) //drop
);

assign result_pair_tdata = {{(C_M_AXI_DATA_WIDTH-(RESULT_PAIR_WIDTH-1)){1'b0}}, result_pair_data};
assign stream_tuple_data = stream_tupe_tdata[STREAM_TUPLE_WIDTH-2:0];
assign window_tuple_data = window_tupe_tdata[WINDOW_TUPLE_WIDTH-2:0];

Controller #(
  .C_M_AXI_ADDR_WIDTH ( C_M_AXI_ADDR_WIDTH ),
  .C_M_AXI_DATA_WIDTH ( C_M_AXI_DATA_WIDTH ),
  .STAGE_NUMS         ( STAGE_NUMS         )
)_Controller
(
  .aclk                       ( ap_clk                     ),
  .areset                     ( 1'b0                       ),
  .ctrl_start                 ( ap_start                   ),// Pulse high for one cycle to begin reading
  .ctrl_done                  ( ctrl_done                  ),// Pulses high for one cycle when transfer request is complete
  
  .ctrl_result_start          ( ctrl_result_start          ),
  .ctrl_result_done           ( ctrl_result_done           ),
  .result                     ( result                     ),
  .result_max                 ( result_max                 ),
  .ctrl_result_over           ( ctrl_result_over           ),
  .result_pipeline_tvalid     ( result_pipeline_tvalid     ),
  .crtl_result_write          ( crtl_result_write          ),

  .ctrl_stream_start          ( ctrl_stream_start          ),
  .ctrl_stream_done           ( ctrl_stream_done           ),
  .stream                     ( stream                     ),
  .stream_length              ( stream_length              ),
  .stream_reader_tvalid       ( stream_reader_tvalid       ),
  .stream_pipeline_tready     ( !stream_stage_full_output  ),
  .crtl_stream_load           ( crtl_stream_load           ),
  .ctrl_stream_stage_clear    ( ctrl_stream_stage_clear    ),

  .ctrl_info_start            ( ctrl_info_start            ),
  .ctrl_info_done             ( ctrl_info_done             ),
  .info                       ( info                       ),
  .device_info                ( device_info                ),

  .ctrl_window_start          ( ctrl_window_start          ),
  .ctrl_window_done           ( ctrl_window_done           ),
  .window                     ( window                     ),
  .window_length              ( window_length              ),
  .window_reader_tvalid       ( window_reader_tvalid       ),
  .window_pipeline_tready     ( !window_stage_full_output  ),
  .crtl_window_load           ( crtl_window_load           ),
  .window_pipeline_tail_valid ( window_pipeline_tail_valid )
);

endmodule : fpga_join_example
`default_nettype wire