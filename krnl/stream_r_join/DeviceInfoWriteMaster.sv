
// default_nettype of none prevents implicit wire declaration.
`default_nettype none

module DeviceInfoWriteMaster #(
  // Set to the address width of the interface
  parameter integer C_M_AXI_ADDR_WIDTH  = 64,
  // Set the data width of the interface
  // Range: 32, 64, 128, 256, 512, 1024
  parameter integer C_M_AXI_DATA_WIDTH  = 512
)
(
  // AXI Interface
  input  wire                            aclk,
  input  wire                            areset,
  // Control signals
  input  wire                            ctrl_start,       // Pulse high for one cycle to begin reading
  output wire                            ctrl_done,        // Pulses high for one cycle when transfer request is complete
  // The following ctrl signals are sampled when ctrl_start is asserted
  input  wire [C_M_AXI_ADDR_WIDTH-1:0]   ctrl_addr_offset, // Starting Address offset
  input  wire [C_M_AXI_DATA_WIDTH-1:0]   ctrl_device_info, // Length in number of bytes, limited by the address width.
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
  output wire                            m_axi_bready
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
/////////////////////////////////////////////////////////////////////////////
// Variables
/////////////////////////////////////////////////////////////////////////////
// Control
logic                                 done = 1'b0;
logic                                 ctrl_start_d1 = 1'b0;
logic [C_M_AXI_ADDR_WIDTH-1:0]        addr_offset_r = 0;
logic [C_M_AXI_DATA_WIDTH-1:0]        write_data_r  = 0;
logic                                 start    = 1'b0;
// Write data channel
logic                                 wxfer;       // Unregistered write data transfer
// --- state machine
localparam S_IDLE = 2'b00;
localparam S_ADDR = 2'b01;
localparam S_DATA = 2'b11;
localparam S_RESP = 2'b10;
logic [1: 0]                          s_state = S_IDLE;           
logic                                 busy_r = 1'b0;
logic                                 aw_valid_r = 1'b0;
logic [C_M_AXI_ADDR_WIDTH-1:0]        aw_addr_r = 0;
logic [7:0]                           aw_len_r = 0;
logic                                 b_ready_r = 1'b0;

/////////////////////////////////////////////////////////////////////////////
// Control logic
/////////////////////////////////////////////////////////////////////////////
assign ctrl_done = done;

// Count the number of transfers and assert done when the last m_axi_bvalid is received.
always @(posedge aclk) begin
  done <= m_axi_bready & m_axi_bvalid;
end

always @(posedge aclk) begin
  ctrl_start_d1 <= ctrl_start;
end

always @(posedge aclk) begin
  if (ctrl_start) begin
    // Align transfer to burst length to avoid AXI protocol issues if starting address is not correctly aligned.
    addr_offset_r <= ctrl_addr_offset & ~LP_ADDR_MASK;
    write_data_r <= ctrl_device_info;
  end
end

always @(posedge aclk) begin
  start <= ctrl_start_d1;
end

/////////////////////////////////////////////////////////////////////////////
// AXI Write Data Channel
/////////////////////////////////////////////////////////////////////////////
assign m_axi_wdata = write_data_r;
assign m_axi_wstrb  = {(C_M_AXI_DATA_WIDTH/8){1'b1}};//数据通道wstrb
assign m_axi_wvalid = (s_state == S_DATA);//数据通道wvalid
assign m_axi_wlast = (s_state == S_DATA);//数据通道wlast
assign wxfer = m_axi_wvalid & m_axi_wready;//发生一次数据传输
/////////////////////////////////////////////////////////////////////////////
// AXI Write Address Channel
/////////////////////////////////////////////////////////////////////////////
assign m_axi_awvalid = aw_valid_r;
assign m_axi_awaddr = aw_addr_r;
assign m_axi_awlen = aw_len_r;
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
                if(start) begin
                    busy_r <= 1'b1;
                    aw_valid_r <= 1'b1;
                    aw_addr_r <= addr_offset_r;
                    aw_len_r <= 0;
                    s_state <= S_ADDR;
                end else begin
                    busy_r <= 1'b0;
                end
            end
            S_ADDR: begin
                if(m_axi_awready) begin//地址握手
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
                    s_state <= S_IDLE;
                end
            end
        endcase
    end
end

endmodule : DeviceInfoWriteMaster

`default_nettype wire