// Copyright (c) 2010 Gregory Estrade (greg@torlus.com)
// Copyright (c) 2018 Sorgelig
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Please report bugs to the author, but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.

module system
(
	input         RESET_N,
	input         MCLK,

	input   [1:0] LPF_MODE,
	input         ENABLE_FM,
	input         ENABLE_PSG,
	output [15:0] DAC_LDATA,
	output [15:0] DAC_RDATA,

	input         LOADING,
	input         PAL,
	input         EXPORT,
	input         FAST_FIFO,
	input         SRAM_QUIRK,
	input         EEPROM_QUIRK,
	input         NORAM_QUIRK,
	input         PIER_QUIRK,
	input         TTN2_QUIRK,

	input   [1:0] TURBO,

	input         GG_RESET,
	input         GG_EN,
	input [128:0] GG_CODE,
	output        GG_AVAILABLE,

	input  [14:0] BRAM_A,
	input  [15:0] BRAM_DI,
	output [15:0] BRAM_DO,
	input         BRAM_WE,
	output        BRAM_CHANGE,

	output  [3:0] RED,
	output  [3:0] GREEN,
	output  [3:0] BLUE,
	output        VS,
	output        HS,
	output        HBL,
	output        VBL,
	output        CE_PIX,

	output        INTERLACE,
	output        FIELD,

	input         J3BUT,
	input  [11:0] JOY_1,
	input  [11:0] JOY_2,
	input  [11:0] JOY_3,
	input  [11:0] JOY_4,
	input   [1:0] MULTITAP,

	input  [24:0] MOUSE,
	input   [2:0] MOUSE_OPT,

	input  [24:1] ROMSZ,
	output [24:1] ROM_ADDR,
	input  [15:0] ROM_DATA,
	output reg    ROM_REQ,
	input         ROM_ACK,
	input         EN_HIFI_PCM
);

reg reset;
always @(posedge MCLK) if(M68K_CLKENn) reset <= ~RESET_N | LOADING;

//--------------------------------------------------------------
// CLOCK ENABLERS
//--------------------------------------------------------------
wire M68K_CLKEN = M68K_CLKENp;
reg  M68K_CLKENp, M68K_CLKENn;
reg  Z80_CLKEN, PSG_CLKEN;
reg  FM_CLKEN;

always @(negedge MCLK) begin
	reg [3:0] FCLKCNT = 0;
	reg [3:0] VCLKCNT = 0;
	reg [3:0] ZCLKCNT = 0;
	reg [3:0] PCLKCNT = 0;
	reg [3:0] ZCLKMAX = 0;
	reg [3:0] VCLKMAX = 0;
	reg [3:0] VCLKMID = 0;

	if(~RESET_N | LOADING) begin
		VCLKCNT <= 0;
		PCLKCNT <= 0;
		FCLKCNT <= 0;
		Z80_CLKEN <= 1;
		PSG_CLKEN <= 1;
		M68K_CLKENp <= 1;
		M68K_CLKENn <= 1;
		ZCLKMAX <= TTN2_QUIRK ? 4'd13 : 4'd14;
		VCLKMAX = 6;
		VCLKMID = 3;
	end
	else begin
		Z80_CLKEN <= 0;
		ZCLKCNT <= ZCLKCNT + 1'b1;
		if (ZCLKCNT == ZCLKMAX) begin
			ZCLKCNT <= 0;
			Z80_CLKEN <= 1;
		end

		PSG_CLKEN <= 0;
		PCLKCNT <= PCLKCNT + 1'b1;
		if (PCLKCNT == 14) begin
			PCLKCNT <= 0;
			PSG_CLKEN <= 1;
		end

		M68K_CLKENp <= 0;
		VCLKCNT <= VCLKCNT + 1'b1;
		if (VCLKCNT == VCLKMAX) begin
			VCLKCNT <= 0;
			M68K_CLKENp <= 1;
			VCLKMAX <= (TURBO == 2) ? 4'd1 : (TURBO == 1) ? 4'd3 : 4'd6;
			VCLKMID <= (TURBO == 2) ? 4'd0 : (TURBO == 1) ? 4'd1 : 4'd3;
		end

		M68K_CLKENn <= 0;
		if (VCLKCNT == VCLKMID) begin
			M68K_CLKENn <= 1;
		end

		FM_CLKEN <= 0;
		FCLKCNT <= FCLKCNT + 1'b1;
		if (FCLKCNT == 6) begin
			FCLKCNT <= 0;
			FM_CLKEN <= 1;
		end
	end
end

reg [15:1] ram_rst_a;
always @(posedge MCLK) ram_rst_a <= ram_rst_a + LOADING;


//--------------------------------------------------------------
// CPU 68000
//--------------------------------------------------------------
wire [23:1] M68K_A;
wire [15:0] M68K_DO;
wire        M68K_AS_N;
wire        M68K_UDS_N;
wire        M68K_LDS_N;
wire        M68K_RNW;
wire  [2:0] M68K_FC;
wire        M68K_BG_N;
wire        M68K_BR_N;
wire        M68K_BGACK_N;

reg   [2:0] M68K_IPL_N;
always @(posedge MCLK) begin
	reg       old_as;
	reg [1:0] scnt;
	
	if(reset) M68K_IPL_N <= 3'b111;
	else if (M68K_CLKEN) begin
		old_as <= M68K_AS_N;
		scnt <= scnt + 1'd1;
		if(~M68K_AS_N) scnt <= 0;
		if((~old_as & M68K_AS_N) || &scnt) begin
			if (M68K_VINT) M68K_IPL_N <= 3'b001;
			else if (M68K_HINT) M68K_IPL_N <= 3'b011;
			else M68K_IPL_N <= 3'b111;
		end
	end
end

wire M68K_INTACK = &M68K_FC;

fx68k M68K
(
	.clk(MCLK),
	.extReset(reset),
	.pwrUp(reset),
	.enPhi1(M68K_CLKENp),
	.enPhi2(M68K_CLKENn),

	.eRWn(M68K_RNW),
	.ASn(M68K_AS_N),
	.UDSn(M68K_UDS_N),
	.LDSn(M68K_LDS_N),

	.FC0(M68K_FC[0]),
	.FC1(M68K_FC[1]),
	.FC2(M68K_FC[2]),

	.BGn(M68K_BG_N),
	.BRn(M68K_BR_N),
	.BGACKn(M68K_BGACK_N),

	.DTACKn(M68K_MBUS_DTACK_N),
	.VPAn(~M68K_INTACK),
	.BERRn(1),
	.IPL0n(M68K_IPL_N[0]),
	.IPL1n(M68K_IPL_N[1]),
	.IPL2n(M68K_IPL_N[2]),
	.iEdb(genie_ovr ? genie_data : M68K_MBUS_D),
	.oEdb(M68K_DO),
	.eab(M68K_A)
);

//--------------------------------------------------------------
// CHEAT CODES
//--------------------------------------------------------------

wire genie_ovr;
wire [15:0] genie_data;

CODES #(.ADDR_WIDTH(24), .DATA_WIDTH(16)) codes (
	.clk(MCLK),
	.reset(LOADING | GG_RESET),
	.enable(~GG_EN),
	.addr_in({M68K_A[23:1], 1'b0}),
	.data_in(M68K_MBUS_D),
	.code(GG_CODE),
	.available(GG_AVAILABLE),
	.genie_ovr(genie_ovr),
	.genie_data(genie_data)
);

//--------------------------------------------------------------
// CPU Z80
//--------------------------------------------------------------
reg         Z80_RESET_N;
reg         Z80_BUSRQ_N;
wire        Z80_MREQ_N;
wire        Z80_RD_N;
wire        Z80_WR_N;
wire [15:0] Z80_A;
wire  [7:0] Z80_DO;
wire        Z80_IO = ~Z80_MREQ_N & (~Z80_RD_N | ~Z80_WR_N);

T80s #(.T2Write(1)) Z80
(
	.RESET_n(Z80_RESET_N),
	.CLK(MCLK),
	.CEN(Z80_CLKEN & Z80_BUSRQ_N),
	.WAIT_n(~Z80_MBUS_DTACK_N | ~Z80_ZBUS_DTACK_N | ~Z80_IO),
	.INT_n(~Z80_VINT),
	.MREQ_n(Z80_MREQ_N),
	.RD_n(Z80_RD_N),
	.WR_n(Z80_WR_N),
	.A(Z80_A),
	.DI((~Z80_ZBUS_DTACK_N) ? Z80_ZBUS_D : Z80_MBUS_D),
	.DO(Z80_DO)
);

wire        CTRL_F  = (MBUS_A[11:8] == 1) ? Z80_BUSRQ_N : (MBUS_A[11:8] == 2) ? Z80_RESET_N : NO_DATA[8];
wire [15:0] CTRL_DO = {NO_DATA[15:9], CTRL_F, NO_DATA[7:0]};
reg         CTRL_SEL;
always @(posedge MCLK) begin
	if (reset) begin
		Z80_BUSRQ_N <= 1;
		Z80_RESET_N <= 0;
	end
	else if(CTRL_SEL & ~MBUS_RNW & ~MBUS_UDS_N) begin
		if (MBUS_A[11:8] == 1) Z80_BUSRQ_N <= ~MBUS_DO[8];
		if (MBUS_A[11:8] == 2) Z80_RESET_N <=  MBUS_DO[8];
	end
end


//--------------------------------------------------------------
// VDP + PSG
//--------------------------------------------------------------
reg         VDP_SEL;
wire [15:0] VDP_DO;
wire        VDP_DTACK_N;

wire [23:0] VBUS_A;
wire        VBUS_SEL;

wire        M68K_HINT;
wire        M68K_VINT;
wire        Z80_VINT;

wire        vram_req;
wire        vram_we_u = vram_we & ~vram_u_n;
wire        vram_we_l = vram_we & ~vram_l_n;
wire        vram_we;
wire        vram_u_n;
wire        vram_l_n;
wire [15:1] vram_a;
wire [15:0] vram_d;
wire [15:0] vram_q;

dpram #(15) vram_l
(
	.clock(MCLK),
	.address_a(vram_a),
	.data_a(vram_d[7:0]),
	.wren_a(vram_we_l & (vram_ack ^ vram_req)),
	.q_a(vram_q[7:0]),

	.address_b(ram_rst_a),
	.wren_b(LOADING)
);

dpram #(15) vram_u
(
	.clock(MCLK),
	.address_a(vram_a),
	.data_a(vram_d[15:8]),
	.wren_a(vram_we_u & (vram_ack ^ vram_req)),
	.q_a(vram_q[15:8]),

	.address_b(ram_rst_a),
	.wren_b(LOADING)
);

reg vram_ack;
always @(posedge MCLK) vram_ack <= vram_req;

wire VDP_hs, VDP_vs;
assign HS = ~VDP_hs;
assign VS = ~VDP_vs;

vdp vdp
(
	.RST_n(~reset),
	.CLK(MCLK),

	.SEL(VDP_SEL),
	.A({MBUS_A[4:1], 1'b0}),
	.RNW(MBUS_RNW),
	.DI(MBUS_DO),
	.DO(VDP_DO),
	.DTACK_n(VDP_DTACK_N),

	.VRAM_req(vram_req),
	.VRAM_ack(vram_ack),
	.VRAM_we(vram_we),
	.VRAM_u_n(vram_u_n),
	.VRAM_l_n(vram_l_n),
	.VRAM_a(vram_a),
	.VRAM_d(vram_d),
	.VRAM_q(vram_q),

	.HINT(M68K_HINT),
	.VINT_TG68(M68K_VINT),
	.INTACK(M68K_INTACK),

	.VINT_T80(Z80_VINT),

	.VBUS_addr(VBUS_A),
	.VBUS_data(VDP_MBUS_D),
	.VBUS_sel(VBUS_SEL),
	.VBUS_dtack_n(VDP_MBUS_DTACK_N),

	.BG_N(M68K_BG_N),
	.BR_N(M68K_BR_N),
	.BGACK_N(M68K_BGACK_N),

	.VRAM_SPEED(~(FAST_FIFO|TURBO)),
	.VSCROLL_BUG(0),

	.FIELD_OUT(FIELD),
	.INTERLACE(INTERLACE),

	.PAL(PAL),
	.R(RED),
	.G(GREEN),
	.B(BLUE),
	.HS(VDP_hs),
	.VS(VDP_vs),
	.CE_PIX(CE_PIX),
	.HBL(HBL),
	.VBL(VBL)
);

// PSG 0x10-0x17 in VDP space
wire [10:0] PSG_SND;
jt89 psg
(
	.rst(reset),
	.clk(MCLK),
	.clk_en(PSG_CLKEN),

	.wr_n(MBUS_RNW | ~VDP_SEL | ~MBUS_A[4] | MBUS_A[3]),
	.din(MBUS_DO[15:8]),

	.sound(PSG_SND)
);


//--------------------------------------------------------------
// I/O
//--------------------------------------------------------------
reg         IO_SEL;
wire  [7:0] IO_DO;
wire        IO_DTACK_N;

reg         JCART_SEL;
wire [15:0] JCART_DO;
wire        JCART_DTACK_N;

multitap multitap
(
	.RESET(reset),
	.CLK(MCLK),
	.CE(M68K_CLKEN),

	.J3BUT(J3BUT),

	.P1_UP(~JOY_1[3]),
	.P1_DOWN(~JOY_1[2]),
	.P1_LEFT(~JOY_1[1]),
	.P1_RIGHT(~JOY_1[0]),
	.P1_A(~JOY_1[4]),
	.P1_B(~JOY_1[5]),
	.P1_C(~JOY_1[6]),
	.P1_START(~JOY_1[7]),
	.P1_MODE(~JOY_1[8]),
	.P1_X(~JOY_1[9]),
	.P1_Y(~JOY_1[10]),
	.P1_Z(~JOY_1[11]),

	.P2_UP(~JOY_2[3]),
	.P2_DOWN(~JOY_2[2]),
	.P2_LEFT(~JOY_2[1]),
	.P2_RIGHT(~JOY_2[0]),
	.P2_A(~JOY_2[4]),
	.P2_B(~JOY_2[5]),
	.P2_C(~JOY_2[6]),
	.P2_START(~JOY_2[7]),
	.P2_MODE(~JOY_2[8]),
	.P2_X(~JOY_2[9]),
	.P2_Y(~JOY_2[10]),
	.P2_Z(~JOY_2[11]),

	.P3_UP(~JOY_3[3]),
	.P3_DOWN(~JOY_3[2]),
	.P3_LEFT(~JOY_3[1]),
	.P3_RIGHT(~JOY_3[0]),
	.P3_A(~JOY_3[4]),
	.P3_B(~JOY_3[5]),
	.P3_C(~JOY_3[6]),
	.P3_START(~JOY_3[7]),
	.P3_MODE(~JOY_3[8]),
	.P3_X(~JOY_3[9]),
	.P3_Y(~JOY_3[10]),
	.P3_Z(~JOY_3[11]),

	.P4_UP(~JOY_4[3]),
	.P4_DOWN(~JOY_4[2]),
	.P4_LEFT(~JOY_4[1]),
	.P4_RIGHT(~JOY_4[0]),
	.P4_A(~JOY_4[4]),
	.P4_B(~JOY_4[5]),
	.P4_C(~JOY_4[6]),
	.P4_START(~JOY_4[7]),
	.P4_MODE(~JOY_4[8]),
	.P4_X(~JOY_4[9]),
	.P4_Y(~JOY_4[10]),
	.P4_Z(~JOY_4[11]),
	
	.FOURWAY_EN(MULTITAP == 1),
	.TEAMPLAYER_EN(MULTITAP == 2),

	.MOUSE(MOUSE),
	.MOUSE_OPT(MOUSE_OPT),

	.PAL(PAL),
	.EXPORT(EXPORT),

	.SEL(IO_SEL),
	.A(MBUS_A[4:1]),
	.RNW(MBUS_RNW),
	.DI(MBUS_DO[7:0]),
	.DO(IO_DO),
	.DTACK_N(IO_DTACK_N),

	.JCART_SEL(JCART_SEL),
	.JCART_DO(JCART_DO),
	.JCART_DTACK_N(JCART_DTACK_N)
);


//-----------------------------------------------------------------------
// ROM
//-----------------------------------------------------------------------

wire [23:0] pier_bank = (MBUS_A[23:1] - 23'h140000);
always_comb begin
	case(BANK_MODE)
		2'h2: ROM_ADDR = {BANK_REG[MBUS_A[21:19]], MBUS_A[18:1]};
		2'h3: ROM_ADDR = {BANK_REG[pier_bank[20:18]], MBUS_A[18:1]};
		default: ROM_ADDR = MBUS_A;
	endcase
end

//-----------------------------------------------------------------------
// 64KB SRAM
//-----------------------------------------------------------------------
reg SRAM_SEL;
wire [15:0] sram_addr;
wire [7:0] sram_di;
wire sram_wren;

always_comb begin
	if (PIER_QUIRK) begin
		sram_addr = {4'b0000, m95_addr};
		sram_di = m95_di;
		sram_wren = m95_rnw;
	end else begin
		sram_addr = MBUS_A[16:1];
		sram_di = MBUS_DO[7:0];
		sram_wren = (SRAM_SEL & ~MBUS_RNW);
	end
end

dpram_dif #(16,8,15,16) sram
(
	.clock(MCLK),
	.address_a(sram_addr),
	.data_a(sram_di),
	.wren_a(sram_wren),
	.q_a(sram_q[7:0]),

	.address_b(LOADING ? ram_rst_a : BRAM_A),
	.data_b(LOADING ? 16'h0000 : BRAM_DI),
	.wren_b(LOADING | BRAM_WE),
	.q_b(BRAM_DO)
);

wire [7:0] sram_q;
assign BRAM_CHANGE = sram_wren;

//-----------------------------------------------------------------------
// EEPROM Handling
//-----------------------------------------------------------------------
reg ep_si, m95_so, ep_sck, ep_hold, ep_cs;
wire [7:0] m95_di, m95_q;
wire [11:0] m95_addr;
wire m95_rnw;

STM95XXX pier_eeprom
(
	.clk(MCLK),
	.enable(PIER_QUIRK),
	.so(m95_so),
	.si(ep_si),
	.sck(ep_sck),
	.hold_n(ep_hold),
	.cs_n(ep_cs),
	.wp_n(1'b1),
	.ram_addr(m95_addr),
	.ram_q(sram_q[7:0]),
	.ram_di(m95_di),
	.ram_RnW(m95_rnw)
);

//-----------------------------------------------------------------------
// 68K RAM
//-----------------------------------------------------------------------
reg RAM_SEL;

dpram #(15) ram68k_u
(
	.clock(MCLK),
	.address_a(MBUS_A[15:1]),
	.data_a(MBUS_DO[15:8]),
	.wren_a(RAM_SEL & ~MBUS_RNW & ~MBUS_UDS_N),
	.q_a(ram68k_q[15:8]),

	.address_b(ram_rst_a),
	.wren_b(LOADING)
);

dpram #(15) ram68k_l
(
	.clock(MCLK),
	.address_a(MBUS_A[15:1]),
	.data_a(MBUS_DO[7:0]),
	.wren_a(RAM_SEL & ~MBUS_RNW & ~MBUS_LDS_N),
	.q_a(ram68k_q[7:0]),

	.address_b(ram_rst_a),
	.wren_b(LOADING)
);
wire [15:0] ram68k_q;

//-----------------------------------------------------------------------
// MBUS Handling
//-----------------------------------------------------------------------
reg        M68K_MBUS_DTACK_N;
reg        Z80_MBUS_DTACK_N;
reg        VDP_MBUS_DTACK_N;

reg [15:0] M68K_MBUS_D;
reg  [7:0] Z80_MBUS_D;
reg [15:0] VDP_MBUS_D;

reg [23:1] MBUS_A;
reg [15:0] MBUS_DO;

reg        MBUS_RNW;
reg        MBUS_UDS_N;
reg        MBUS_LDS_N;

reg [4:0]  BANK_REG[0:7];
reg [2:0]  BANK_MODE; //0 = none, 1 = BANK SRAM, 2 = BANK ROM



always @(posedge MCLK) begin
	reg  [3:0] mstate;
	reg  [1:0] msrc;
	reg [15:0] data;
	reg  [3:0] pier_count;
	
	localparam	MSRC_NONE = 0,
					MSRC_M68K = 1,
					MSRC_Z80  = 2,
					MSRC_VDP  = 3;

	localparam 	MBUS_IDLE     = 0,
					MBUS_SELECT   = 1,
					MBUS_RAM_READ = 2,
					MBUS_ROM_READ = 3,
					MBUS_VDP_READ = 4,
					MBUS_IO_READ  = 5,
					MBUS_JCRT_READ= 6,
					MBUS_SRAM_READ= 7,
					MBUS_ZBUS_PRE = 8,
					MBUS_ZBUS_READ= 9,
					MBUS_FINISH   = 10;

	if (reset) begin
		M68K_MBUS_DTACK_N <= 1;
		Z80_MBUS_DTACK_N  <= 1;
		VDP_MBUS_DTACK_N  <= 1;
		VDP_SEL <= 0;
		IO_SEL <= 0;
		ZBUS_SEL <= 0;
		BANK_MODE <= 0;
		mstate <= MBUS_IDLE;
		pier_count <= 0;
		MBUS_RNW <= 1;

		if(PIER_QUIRK) BANK_REG <= '{0,0,0,0,0,0,0,0};
		else BANK_REG <= '{0,1,2,3,4,5,6,7};
	end
	else begin
		if (M68K_AS_N) M68K_MBUS_DTACK_N <= 1;
		if (~Z80_IO)   Z80_MBUS_DTACK_N  <= 1;
		if (~VBUS_SEL) VDP_MBUS_DTACK_N  <= 1;

		case(mstate)
		MBUS_IDLE:
			begin
				CTRL_SEL <= 0;
				SRAM_SEL <= 0;
				RAM_SEL <= 0;
				MBUS_RNW <= 1;
				MBUS_UDS_N <= 1;
				MBUS_LDS_N <= 1;
				if(~M68K_AS_N & M68K_MBUS_DTACK_N & M68K_CLKENn) begin
					msrc <= MSRC_M68K;
					MBUS_A <= M68K_A[23:1];
					data <= NO_DATA;
					MBUS_DO <= M68K_DO;
					MBUS_RNW <= M68K_RNW;
					mstate <= MBUS_SELECT;
				end
				else if(Z80_IO & ~Z80_ZBUS & Z80_MBUS_DTACK_N & M68K_BR_N & M68K_BGACK_N) begin
					msrc <= MSRC_Z80;
					MBUS_A <= Z80_A[15] ? {BAR[23:15],Z80_A[14:1]} : {16'hC000, Z80_A[7:1]};
					data <= 16'hFFFF;
					MBUS_DO <= {Z80_DO,Z80_DO};
					MBUS_RNW <= Z80_WR_N;
					mstate <= MBUS_SELECT;
				end
				else if(VBUS_SEL & VDP_MBUS_DTACK_N) begin
					msrc <= MSRC_VDP;
					MBUS_A <= VBUS_A[23:1];
					data <= NO_DATA;
					MBUS_DO <= 0;
					mstate <= MBUS_SELECT;
				end
			end
			
		MBUS_SELECT:
			begin
				//NO DEVICE (usually lockup on real HW)
				mstate <= MBUS_FINISH;

				if(MBUS_A[23:20]<'hA || (msrc == MSRC_Z80 && MBUS_A[23:20]<'hE && ROMSZ[24:20]>='hA)) begin
					//ROM: 000000-9FFFFF (A00000-DFFFFF)
					if (BANK_MODE == 2'h1 && MBUS_A[23:21] == 1) begin
						// 200000-3FFFFF SRAM overrides ROM when bank is selected
						SRAM_SEL <= 1;
						mstate <= MBUS_SRAM_READ;
					end
					else if (PIER_QUIRK && ({MBUS_A,1'b0} == 'h0015E6 || {MBUS_A,1'b0} == 'h0015E8)) begin
						if (pier_count < 'h6) begin
							pier_count <= pier_count + 1'h1;
							data <= MBUS_A[1] ? 16'h0 : 16'h0010;
						end else begin
							data <= MBUS_A[1] ? 16'h0001 : 16'h8010;
						end
					end
					else if (EEPROM_QUIRK && {MBUS_A,1'b0} == 'h200000) begin
						data <= 0;
						mstate <= MBUS_FINISH;
					end
					else if (SRAM_QUIRK && {MBUS_A,1'b0} == 'h200000) begin
						SRAM_SEL <= 1;
						mstate <= MBUS_SRAM_READ;
					end
					else if (MBUS_A < ROMSZ) begin
						if (PIER_QUIRK) BANK_MODE <= (MBUS_A >= 23'h140000) ? 3'h3 : 3'h0;
						ROM_REQ <= ~ROM_ACK;
						mstate <= MBUS_ROM_READ;
					end
					else if ((MULTITAP == 3) && ({MBUS_A,1'b0} == 'h3FFFFE || {MBUS_A,1'b0} == 'h38FFFE)) begin
						JCART_SEL <= 1;
						mstate <= MBUS_JCRT_READ;
					end
					else if(MBUS_A[23:21] == 1 && ~&MBUS_A[20:19] && ~NORAM_QUIRK) begin
						// 200000-37FFFF
						SRAM_SEL <= 1;
						mstate <= MBUS_SRAM_READ;
					end
					else begin
						data <= 0;
						mstate <= MBUS_FINISH;
					end
				end
				else begin
					//ZBUS: A00000-A07FFF (A08000-A0FFFF)
					if(MBUS_A[23:16] == 'hA0) mstate <= MBUS_ZBUS_PRE;

					//I/O: A10000-A1001F (+mirrors)
					if(MBUS_A[23:5] == {16'hA100, 3'b000}) begin
						IO_SEL <= 1;
						mstate <= MBUS_IO_READ;
					end

					//CTL: A11100, A11200
					if(MBUS_A[23:12] == 12'hA11 && !MBUS_A[7:1]) begin
						CTRL_SEL <= 1;
						data <= CTRL_DO;
						mstate <= MBUS_FINISH;
					end

					// BANK Register A13XXX
					if (MBUS_A[23:8] == 'hA130) begin
						if (~MBUS_RNW) begin
							if (ROMSZ > 'h200000) begin // SSF2/Pier Solar ROM banking
								if (MBUS_A[3:1]) begin
									if (~PIER_QUIRK) begin // SSF2
										BANK_REG[MBUS_A[3:1]] <= MBUS_DO[4:0];
										BANK_MODE <= 2'h2;
									end else if (MBUS_A[3:1] == 'h4) begin // Pier EEPROM
										{ep_cs, ep_hold , ep_sck, ep_si} <= MBUS_DO[3:0];
									end else if (~MBUS_A[3]) begin // Pier Banks
										BANK_REG[MBUS_A[3:1] - 1'b1] <= {1'b0, MBUS_DO[3:0]};
									end
								end
							end else begin // SRAM Banking
								BANK_MODE <= {1'b0, MBUS_DO[0]};
							end
						end else if (PIER_QUIRK && MBUS_A[3:1] == 'h5) begin
							data <= {15'h7FFF, m95_so};
						end
						mstate <= MBUS_FINISH;
					end

					//VDP: C00000-C0001F (+mirrors)
					if(MBUS_A[23:21] == 3'b110 && !MBUS_A[18:16] && !MBUS_A[7:5]) begin
						VDP_SEL <= 1;
						mstate <= MBUS_VDP_READ;
					end
				end


				//RAM: E00000-FFFFFF
				if(&MBUS_A[23:21]) begin
					RAM_SEL <= 1;
					mstate <= MBUS_RAM_READ;
				end
			end
			
		MBUS_ZBUS_PRE:
			case(msrc)
			MSRC_M68K:
				if(M68K_AS_N | (~M68K_UDS_N | ~M68K_LDS_N)) begin
					MBUS_UDS_N <= M68K_UDS_N;
					MBUS_LDS_N <= M68K_LDS_N;
					ZBUS_SEL <= 1;
					mstate <= MBUS_ZBUS_READ;
				end

			MSRC_Z80:
				begin
					MBUS_UDS_N <= Z80_A[0];
					MBUS_LDS_N <= ~Z80_A[0];
					ZBUS_SEL <= 1;
					mstate <= MBUS_ZBUS_READ;
				end

			MSRC_VDP:
				begin
					MBUS_UDS_N <= 0;
					MBUS_LDS_N <= 0;
					ZBUS_SEL <= 1;
					mstate <= MBUS_ZBUS_READ;
				end
			endcase

		MBUS_ZBUS_READ:
			if(~MBUS_ZBUS_DTACK_N) begin
				ZBUS_SEL <= 0;
				data <= {MBUS_ZBUS_D, MBUS_ZBUS_D};
				mstate <= MBUS_FINISH;
			end

		MBUS_RAM_READ:
			begin
				data <= ram68k_q;
				mstate <= MBUS_FINISH;
			end

		MBUS_ROM_READ:
			if (ROM_REQ == ROM_ACK) begin
				data <= ROM_DATA;
				mstate <= MBUS_FINISH;
			end

		MBUS_SRAM_READ:
			begin
				data <= {sram_q,sram_q};
				mstate <= MBUS_FINISH;
			end

		MBUS_VDP_READ:
			if (~VDP_DTACK_N) begin
				VDP_SEL <= 0;
				data <= VDP_DO;
				mstate <= MBUS_FINISH;
			end

		MBUS_IO_READ:
			if(~IO_DTACK_N) begin
				IO_SEL <= 0;
				data <= {IO_DO, IO_DO};
				mstate <= MBUS_FINISH;
			end

		MBUS_JCRT_READ:
			if(~JCART_DTACK_N) begin
				JCART_SEL <= 0;
				data <= JCART_DO & 16'h3F7F;
				mstate <= MBUS_FINISH;
			end

		MBUS_FINISH:
			begin
				case(msrc)
				MSRC_M68K:
					begin
						M68K_MBUS_D <= data;
						M68K_MBUS_DTACK_N <= 0;
						if(M68K_AS_N | MBUS_RNW | ~M68K_UDS_N | ~M68K_LDS_N) begin
							MBUS_UDS_N <= M68K_UDS_N;
							MBUS_LDS_N <= M68K_LDS_N;
							mstate <= MBUS_IDLE;
						end
					end

				MSRC_Z80:
					begin
						Z80_MBUS_D <= Z80_A[0] ? data[7:0] : data[15:8];
						Z80_MBUS_DTACK_N <= 0;
						MBUS_UDS_N <= Z80_A[0];
						MBUS_LDS_N <= ~Z80_A[0];
						mstate <= MBUS_IDLE;
					end

				MSRC_VDP:
					begin
						VDP_MBUS_D <= data;
						VDP_MBUS_DTACK_N <= 0;
						mstate <= MBUS_IDLE;
					end
				endcase;
			end
		endcase;
	end
end


//-----------------------------------------------------------------------
// ZBUS Handling
//-----------------------------------------------------------------------
// Z80:   0000-7EFF
// 68000: A00000-A07FFF (A08000-A0FFFF)

wire       Z80_ZBUS  = ~Z80_A[15] && ~&Z80_A[14:8];

reg        ZBUS_SEL;
reg [14:0] ZBUS_A;
reg        ZBUS_WE;
reg  [7:0] ZBUS_DO;
wire [7:0] ZBUS_DI = ZRAM_SEL ? ZRAM_DO : FM_SEL ? FM_DO : 8'hFF;

reg  [7:0] MBUS_ZBUS_D;
reg  [7:0] Z80_ZBUS_D;

reg        MBUS_ZBUS_DTACK_N;
reg        Z80_ZBUS_DTACK_N;

wire       Z80_ZBUS_SEL = Z80_ZBUS & Z80_IO;
wire       ZBUS_FREE = ~Z80_BUSRQ_N & Z80_RESET_N;

// RAM 0000-1FFF (2000-3FFF)
wire ZRAM_SEL = ~ZBUS_A[14];

wire  [7:0] ZRAM_DO;
dpram #(13) ramZ80
(
	.clock(MCLK),
	.address_a(ZBUS_A[12:0]),
	.data_a(ZBUS_DO),
	.wren_a(ZBUS_WE & ZRAM_SEL),
	.q_a(ZRAM_DO)
);

always @(posedge MCLK) begin
	reg [1:0] zstate;
	reg [1:0] zsrc;

	localparam 	ZSRC_MBUS = 0,
					ZSRC_Z80  = 1;

	localparam	ZBUS_IDLE   = 0,
					ZBUS_READ   = 1,
					ZBUS_FINISH = 2;

	ZBUS_WE <= 0;
	
	if (reset) begin
		MBUS_ZBUS_DTACK_N <= 1;
		Z80_ZBUS_DTACK_N  <= 1;
		zstate <= ZBUS_IDLE;
	end
	else begin
		if (~ZBUS_SEL)     MBUS_ZBUS_DTACK_N <= 1;
		if (~Z80_ZBUS_SEL) Z80_ZBUS_DTACK_N  <= 1;

		case (zstate)
		ZBUS_IDLE:
			if (ZBUS_SEL & MBUS_ZBUS_DTACK_N) begin
				ZBUS_A <= {MBUS_A[14:1], MBUS_UDS_N};
				ZBUS_DO <= (~MBUS_UDS_N) ? MBUS_DO[15:8] : MBUS_DO[7:0];
				ZBUS_WE <= ~MBUS_RNW & ZBUS_FREE;
				zsrc <= ZSRC_MBUS;
				zstate <= ZBUS_READ;
			end
			else if (Z80_ZBUS_SEL & Z80_ZBUS_DTACK_N) begin
				ZBUS_A <= Z80_A[14:0];
				ZBUS_DO <= Z80_DO;
				ZBUS_WE <= ~Z80_WR_N;
				zsrc <= ZSRC_Z80;
				zstate <= ZBUS_READ;
			end

		ZBUS_READ:
			zstate <= ZBUS_FINISH;

		ZBUS_FINISH:
			begin
				case(zsrc)
				ZSRC_MBUS:
					begin
						MBUS_ZBUS_D <= ZBUS_FREE ? ZBUS_DI : 8'hFF;
						MBUS_ZBUS_DTACK_N <= 0;
					end

				ZSRC_Z80:
					begin
						Z80_ZBUS_D <= ZBUS_DI;
						Z80_ZBUS_DTACK_N <= 0;
					end
				endcase
				zstate <= ZBUS_IDLE;
			end
		endcase
	end
end


//-----------------------------------------------------------------------
// Z80 BANK REGISTER
//-----------------------------------------------------------------------
// 6000-60FF

wire BANK_SEL = ZBUS_A[14:8] == 7'h60;
reg [23:15] BAR;

always @(posedge MCLK) begin
	if (reset) BAR <= 0;
	else if (BANK_SEL & ZBUS_WE) BAR <= {ZBUS_DO[0], BAR[23:16]};
end


//--------------------------------------------------------------
// YM2612
//--------------------------------------------------------------
// 4000-4003 (4000-5FFF)

wire        FM_SEL = ZBUS_A[14:13] == 2'b10;
wire  [7:0] FM_DO;
wire [15:0] FM_right;
wire [15:0] FM_left;
wire signed [15:0] FM_LPF_right;
wire signed [15:0] FM_LPF_left;
wire signed [15:0] FM_PREMIX_L;
wire signed [15:0] FM_PREMIX_R;
wire signed [15:0] PRE_LPF_L;
wire signed [15:0] PRE_LPF_R;

jt12 fm
(
	.rst(~Z80_RESET_N),
	.clk(MCLK),
	.cen(FM_CLKEN),

	.cs_n(0),
	.addr(ZBUS_A[1:0]),
	.wr_n(~(FM_SEL & ZBUS_WE)),
	.din(ZBUS_DO),
	.dout(FM_DO),
    .en_hifi_pcm( EN_HIFI_PCM ),
	.snd_left(FM_left),
	.snd_right(FM_right)
);

jt12_genmix genmix
(
	.rst(~Z80_RESET_N),
	.clk(MCLK),
	.fm_left(FM_PREMIX_L),
	.fm_right(FM_PREMIX_R),
	.psg_snd(PSG_SND),
	.fm_en(ENABLE_FM),
	.psg_en(ENABLE_PSG),
	.snd_left(PRE_LPF_L),
	.snd_right(PRE_LPF_R)
);

//Low-pass FM separately for Model 2 Genesis filter
assign FM_PREMIX_L = (LPF_MODE == 2'b01) ? FM_LPF_left : FM_left; 
assign FM_PREMIX_R = (LPF_MODE == 2'b01) ? FM_LPF_right : FM_right;

genesis_fm_lpf fm_lpf_l
(
	.clk(MCLK),
	.reset(~Z80_RESET_N),
	.in(FM_left),
	.out(FM_LPF_left)
);

genesis_fm_lpf fm_lpf_r
(
	.clk(MCLK),
	.reset(~Z80_RESET_N),
	.in(FM_right),
	.out(FM_LPF_right)
);

genesis_lpf lpf_right(
	.clk(MCLK),
	.reset(~Z80_RESET_N),
	.lpf_mode(LPF_MODE[1:0]),
	.in(PRE_LPF_R),
	.out(DAC_RDATA)
);

genesis_lpf lpf_left(
	.clk(MCLK),
	.reset(~Z80_RESET_N),
	.lpf_mode(LPF_MODE[1:0]),
	.in(PRE_LPF_L),
	.out(DAC_LDATA)
);

//-----------------------------------------------------------------------
// BUS NOISE GENERATOR
//-----------------------------------------------------------------------
reg [15:0] NO_DATA;
always @(posedge MCLK) begin
	reg [16:0] lfsr;

	if (M68K_CLKEN) begin
		lfsr <= {(lfsr[0] ^ lfsr[2] ^ !lfsr), lfsr[16:1]};
		NO_DATA <= {NO_DATA[14:0], lfsr[0]};
	end
end

endmodule