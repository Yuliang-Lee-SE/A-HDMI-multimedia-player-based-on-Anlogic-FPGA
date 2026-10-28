`timescale 1ns/1ps
module frame_read_write_dual
#
(
	parameter MEM_DATA_BITS          = 32,
	parameter READ_DATA_BITS         = 32,
	parameter WRITE_DATA_BITS        = 32,
	parameter ADDR_BITS              = 21,
	parameter BURST_BITS             = 9,//
	parameter BURST_SIZE             = 256,
	parameter WRITE_V_FLIP           = 1,      // 1: vertical flip when writing TF/BMP frame into SDRAM
	parameter FRAME_WIDTH            = 640,
	parameter FRAME_HEIGHT           = 480
) 
(
	input                            rst,
    input                            write_abort,
    output                           write_abort_done,
	input                            mem_clk,                    // external memory controller user interface clock
	input							 Sdr_init_done,
	input							 Sdr_init_ref_vld,
    input							 Sdr_busy,
	
    /*
    output                           rd_burst_req,               // to external memory controller,send out a burst read request
	output[BURST_BITS - 1:0]         rd_burst_len,               // to external memory controller,data length of the burst read request, not bytes
	output[ADDR_BITS - 1:0]          rd_burst_addr,              // to external memory controller,base address of the burst read request 
	input                            rd_burst_data_valid,        // from external memory controller,read data valid 
	input[MEM_DATA_BITS - 1:0]       rd_burst_data,              // from external memory controller,read request data
	input                            rd_burst_finish,            // from external memory controller,burst read finish
	*/
	output							 App_rd_en,
	output[ADDR_BITS - 1:0]			 App_rd_addr,
	input							 Sdr_rd_en,					 //read_data_valid
	input[MEM_DATA_BITS - 1:0]		 Sdr_rd_dout,
	
	input                            read_clk,                   // data read module clock
	input                            read_req,                   // data read module read request,keep '1' until read_req_ack = '1'
	input                            read_dual,                  // compose A/B into one sequential slide frame
	input                            read_blinds,                // select horizontal blinds instead of slide
	input                            read_fade,                  // select per-pixel A/B crossfade
	output                           read_req_ack,               // data read module read request response
	output                           read_finish,                // data read module read request finish
	input[ADDR_BITS - 1:0]           read_addr_a,
	input[ADDR_BITS - 1:0]           read_addr_b,
	input[ADDR_BITS - 1:0]           read_len,                   // data read module read request data length
	input [8:0]                      read_progress,
	input                            read_en_a,
	input                            read_en_b,
	output[READ_DATA_BITS  - 1:0]    read_data_a,
	output[READ_DATA_BITS  - 1:0]    read_data_b,
	output                           read_empty_a,
	output                           read_empty_b,
	/*
	output                           wr_burst_req,               // to external memory controller,send out a burst write request
	output[BURST_BITS - 1:0]         wr_burst_len,               // to external memory controller,data length of the burst write request, not bytes
	output[ADDR_BITS - 1:0]          wr_burst_addr,              // to external memory controller,base address of the burst write request 
	input                            wr_burst_data_req,          // from external memory controller,write data request ,before data 1 clock
	output[MEM_DATA_BITS - 1:0]      wr_burst_data,              // to external memory controller,write data
	input                            wr_burst_finish,            // from external memory controller,burst write finish
	*/
	output							 App_wr_en,
	output[ADDR_BITS - 1:0]			 App_wr_addr,
	output[MEM_DATA_BITS - 1:0]	 App_wr_din,
	output[3:0]						 App_wr_dm,
	
	//
	input                            write_clk,                  // data write module clock
	input                            write_req,                  // data write module write request,keep '1' until read_req_ack = '1'
	output                           write_req_ack,              // data write module write request response
	output                           write_finish,               // data write module write request finish
	input[ADDR_BITS - 1:0]           write_addr_0,               // data write module write request base address 0, used when write_addr_index = 0
	input[ADDR_BITS - 1:0]           write_addr_1,               // data write module write request base address 1, used when write_addr_index = 1
	input[ADDR_BITS - 1:0]           write_addr_2,               // data write module write request base address 1, used when write_addr_index = 2
	input[ADDR_BITS - 1:0]           write_addr_3,               // data write module write request base address 1, used when write_addr_index = 3
	input[1:0]                       write_addr_index,           // select valid base address from write_addr_0 write_addr_1 write_addr_2 write_addr_3
	input[ADDR_BITS - 1:0]           write_len,                  // data write module write request data length
	input                            write_en,                   // data write module write request for one data
	input[WRITE_DATA_BITS - 1:0]     write_data,                // write data
    output                           write_ready                // write_clk domain

);
wire[BURST_BITS - 1:0]                           rdusedw;
wire[BURST_BITS - 1:0]                           rdusedw_a;
wire[BURST_BITS - 1:0]                           wrusedw_fifo;
wire                                             read_we_a;
wire                                             compose_app_en;
wire [ADDR_BITS-1:0]                             compose_app_addr;
wire                                             compose_app_busy;
wire                                             compose_req_ack;
wire                                             compose_finish;
wire                                             compose_aclr;
wire                                             compose_fifo_we;
wire [31:0]                                      compose_fifo_data;

wire 								 App_rd_busy;
wire								 App_wr_busy;

wire                                 read_fifo_aclr_a;
wire                                 write_fifo_aclr;            // fifo Asynchronous clear

wire O_wr_busy;
wire write_fifo_full;
localparam integer WRITE_STOP_LEVEL = (1 << BURST_BITS) - 9;
reg write_ready_q;

// Only one FIFO and one memory read FSM exist in every mode. Slide frames are
// composed in SDRAM address order, so there is no mode-change ownership race.
assign App_rd_en        = compose_app_en;
assign App_rd_addr      = compose_app_addr;
assign App_rd_busy      = compose_app_busy;
assign read_req_ack     = compose_req_ack;
assign read_finish      = compose_finish;
assign read_we_a        = compose_fifo_we;
assign read_fifo_aclr_a = compose_aclr;
assign read_data_b      = {READ_DATA_BITS{1'b0}};
assign read_empty_b     = 1'b1;
reg write_reset_first;
reg [1:0] write_reset_release;
wire write_fifo_reset = rst || write_fifo_aclr;
reg write_reset_mem_hold;
// Register the combined reset locally before its write-clock CDC. This
// removes reset OR logic from the short inter-clock recovery path, and
// captures even a sub-cycle pulse. Adds at most one memory clock of hold.
always @(posedge mem_clk or posedge write_fifo_reset)
    if(write_fifo_reset) write_reset_mem_hold <= 1'b1;
    else write_reset_mem_hold <= 1'b0;
// Asynchronous assertion, synchronous release in the FIFO write domain.
always @(posedge write_clk or posedge write_reset_mem_hold)
    if (write_reset_mem_hold) write_reset_first <= 1'b1;
    else write_reset_first <= 1'b0;
// Only the first stage has asynchronous reset fanout. Later stages sample
// it synchronously; raw reset and stage zero mask them until initialized.
always @(posedge write_clk)
    write_reset_release <= {write_reset_release[0],write_reset_first};
// Register the almost-full calculation. Eight spare words preserve safety for
// the one-cycle delayed deassertion while cutting the long pointer/full path
// into the BMP scaler.
always @(posedge write_clk) begin
    if (write_reset_first || (|write_reset_release))
        write_ready_q <= 1'b0;
    else
        write_ready_q <= (wrusedw_fifo < WRITE_STOP_LEVEL);
end
assign write_ready = write_ready_q;

assign App_wr_busy = O_wr_busy;//下个时钟写指令拉高
assign App_wr_dm = 4'b0000;

//instantiate an asynchronous FIFO 
wfifo_32_32_512 write_buf
	(
	.clkr                      	(mem_clk                  ),          // Read side clock
	.clkw                      	(write_clk                ),          // Write side clock
	.rst                       	(write_fifo_aclr          ),          // Asynchronous clear
	.we                      	(write_en                 ),          // Write Request
	.re                      	(App_wr_en        		  ),          // Read Request
	.di                       	(write_data               ),          // Input Data
	.empty_flag                 (                         ),          // Read side Empty flag
	.full_flag                  (write_fifo_full          ),          // Write side Full flag
	.wrusedw                	(wrusedw_fifo             ),          // Read Used Words
	.rdusedw                	(rdusedw                  ),          // Write Used Words
	.dout                       (App_wr_din		          )
);

frame_fifo_write
#
(
	.MEM_DATA_BITS              (MEM_DATA_BITS            ),
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.BURST_SIZE                 (BURST_SIZE               ),
	.WRITE_V_FLIP               (WRITE_V_FLIP             ),
	.FRAME_WIDTH                (FRAME_WIDTH              ),
	.FRAME_HEIGHT               (FRAME_HEIGHT             )
) 
frame_fifo_write_m0              
(  
	.rst                        (rst                      ),
    .abort_req                  (write_abort),
    .abort_done                 (write_abort_done),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
	.App_rd_busy				(App_rd_busy),
    .O_wr_busy					(O_wr_busy),
	
	.App_wr_en					(App_wr_en),
    .App_wr_addr				(App_wr_addr),
	.write_req                  (write_req                ),
	.write_req_ack              (write_req_ack            ),
	.write_finish               (write_finish             ),
	.write_addr_0               (write_addr_0             ),
	.write_addr_1               (write_addr_1             ),
	.write_addr_2               (write_addr_2             ),
	.write_addr_3               (write_addr_3             ),
	.write_addr_index           (write_addr_index         ),    
	.write_len                  (write_len                ),
	.fifo_aclr                  (write_fifo_aclr          ),
	.rdusedw                 	(rdusedw                  )
);

rfifo_32_32_512 read_buf_a
	(
	.clkr                     	(read_clk                   ),          // Read side clock
	.clkw                     	(mem_clk                    ),          // Write side clock
	.rst                      	(read_fifo_aclr_a           ),          // Asynchronous clear
	.we                     	(read_we_a                  ),          // Write Request
	.re                     	(read_en_a                  ),          // Read Request
	.di                      	(compose_fifo_data          ),          // Input Data
	.empty_flag					(read_empty_a               ),          // Read side Empty flag
	.full_flag					(                           ),          // Write side Full flag
	.wrusedw                	(rdusedw_a                  ),          // Read Used Words
	.rdusedw                	(                  			 ),          // Write Used Words
	.dout						(read_data_a                )
);

frame_compose_read
#
(
	.ADDR_BITS                  (ADDR_BITS                ),
	.BURST_BITS                 (BURST_BITS               ),
	.BURST_SIZE                 (BURST_SIZE               ),
	.FIFO_DEPTH                 (512                      ),
	.H_ACTIVE                   (FRAME_WIDTH              ),
	.V_ACTIVE                   (FRAME_HEIGHT             )
)
frame_compose_read_m0
(
	.rst                        (rst                      ),
	.mem_clk                    (mem_clk                  ),
    .Sdr_init_done				(Sdr_init_done),
	.Sdr_init_ref_vld			(Sdr_init_ref_vld),
    .Sdr_busy					(Sdr_busy),
    .Sdr_rd_en					(Sdr_rd_en),
	.Sdr_rd_dout				(Sdr_rd_dout),
	.App_wr_busy				(App_wr_busy),
	
    .O_rd_busy					(compose_app_busy),
    .App_rd_en					(compose_app_en),
    .App_rd_addr				(compose_app_addr),
	.read_req                   (read_req                 ),
	.read_req_ack               (compose_req_ack          ),
	.read_finish                (compose_finish           ),
	.read_slide                 (read_dual                ),
	.read_blinds                (read_blinds              ),
	.read_fade                  (read_fade                ),
	.read_base_a                (read_addr_a              ),
	.read_base_b                (read_addr_b              ),
	.read_len                   (read_len                 ),
	.read_progress              (read_progress            ),
	.fifo_aclr                  (compose_aclr             ),
	.wrusedw                    (rdusedw_a                ),
	.fifo_we                    (compose_fifo_we          ),
	.fifo_data                  (compose_fifo_data        )
);

endmodule
