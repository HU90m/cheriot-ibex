// Copyright Microsoft Corporation
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0


module cheri_tbre_wrapper #(
  parameter bit          CHERIoTEn   = 1'b1,
  parameter bit          CheriTBRE   = 1'b1,
  parameter bit          CheriStkClr = 1'b1,
  parameter int unsigned MMRegDinW   = 128,
  parameter int unsigned MMRegDoutW  = 64
  
) (
   // Clock and Reset
  input  logic          clk_i,
  input  logic          rst_ni,

  // MMIO register interface 
  input  logic [MMRegDinW-1:0]  mmreg_corein_i,
  output logic [MMRegDoutW-1:0] mmreg_coreout_o,

  // LSU req/resp interface (to be multiplixed/qualified)
  input  logic          lsu_tbre_resp_valid_i,
  input  logic          lsu_tbre_resp_err_i,
  input  logic          lsu_tbre_resp_is_wr_i,
  input  logic [32:0]   lsu_tbre_raw_lsw_i,   
  input  logic          lsu_tbre_req_done_i,   
  input  logic          lsu_tbre_addr_incr_i,
  output logic          tbre_lsu_req_o,
  output logic          tbre_lsu_is_cap_o,
  output logic          tbre_lsu_we_o,
  output logic [31:0]   tbre_lsu_addr_o,
  output logic [32:0]   tbre_lsu_wdata_o,

  // LSU snoop interface
  input  logic          snoop_lsu_req_done_i,   
  input  logic          snoop_lsu_req_i,
  input  logic          snoop_lsu_is_cap_i,
  input  logic          snoop_lsu_we_i,
  input  logic          snoop_lsu_cheri_err_i,
  input  logic [31:0]   snoop_lsu_addr_i,

  // trvk interface
  input  logic          trvk_en_i,
  input  logic          trvk_clrtag_i,

  // Stack fast-clearing signals
  input  logic          csr_stkclr_ptr_wr_i,
  input  logic [31:0]   csr_stkclr_ptr_wdata_i,
  input  logic [31:0]   csr_mshwm_i,

  input  logic          unmasked_intr_i,

  output logic          stkclr_active_o,
  output logic          stkclr_abort_o,
  output logic [31:0]   stkclr_ptr_o,
  output logic [31:0]   stkclr_base_o
);

  localparam nMSTR = 2;

  logic          lsu_blk1_resp_valid;    
  logic          lsu_blk1_req_done;   
  logic          blk1_lsu_req;
  logic          blk1_lsu_is_cap;
  logic          blk1_lsu_we;
  logic [31:0]   blk1_lsu_addr;
  logic [32:0]   blk1_lsu_wdata;

  logic          lsu_blk0_resp_valid;    
  logic          lsu_blk0_req_done;   
  logic          blk0_lsu_req;
  logic          blk0_lsu_is_cap;
  logic          blk0_lsu_we;
  logic [31:0]   blk0_lsu_addr;
  logic [32:0]   blk0_lsu_wdata;


  logic          tbre_stat, tbre_err, stkclr_err;

  assign mmreg_coreout_o = {{(MMRegDoutW-2){1'b0}}, stkclr_err, tbre_err, tbre_stat};

  if (CHERIoTEn & CheriTBRE) begin : g_tbre
    logic [65:0] tbre_ctrl_vec;

    assign tbre_ctrl_vec      = mmreg_corein_i[65:0];

    cheri_tbre #(
      .FifoSize (4), 
      .AddrHi   (23)
    ) cheri_tbre_i (
     // Clock and Reset
      .clk_i                   (clk_i),                 
      .rst_ni                  (rst_ni),
      .tbre_ctrl_vec_i         (tbre_ctrl_vec),
      .tbre_stat_o             (tbre_stat),
      .tbre_err_o              (tbre_err),
      .lsu_tbre_resp_valid_i   (lsu_blk1_resp_valid),
      .lsu_tbre_resp_err_i     (lsu_tbre_resp_err_i),
      .lsu_tbre_resp_is_wr_i   (lsu_tbre_resp_is_wr_i),
      .lsu_tbre_raw_lsw_i      (lsu_tbre_raw_lsw_i),   
      .lsu_tbre_req_done_i     (lsu_blk1_req_done),   
      .lsu_tbre_addr_incr_i    (lsu_tbre_addr_incr_i),
      .tbre_lsu_req_o          (blk1_lsu_req),
      .tbre_lsu_is_cap_o       (blk1_lsu_is_cap),
      .tbre_lsu_we_o           (blk1_lsu_we),
      .tbre_lsu_addr_o         (blk1_lsu_addr),
      .tbre_lsu_wdata_o        (blk1_lsu_wdata),
      .snoop_lsu_req_done_i    (snoop_lsu_req_done_i),  
      .snoop_lsu_req_i         (snoop_lsu_req_i),
      .snoop_lsu_is_cap_i      (snoop_lsu_is_cap_i),
      .snoop_lsu_we_i          (snoop_lsu_we_i),
      .snoop_lsu_cheri_err_i   (snoop_lsu_cheri_err_i),
      .snoop_lsu_addr_i        (snoop_lsu_addr_i),
      .trvk_en_i               (trvk_en_i),
      .trvk_clrtag_i           (trvk_clrtag_i)          
      );
  end else begin
    assign tbre_stat       = 1'b0;
    assign tbre_err        = 1'b0;
    assign blk1_lsu_req    = 1'b0;
    assign blk1_lsu_is_cap = 1'b0;
    assign blk1_lsu_we     = 1'b0;
    assign blk1_lsu_addr   = 32'h0;
    assign blk1_lsu_wdata  = 33'h0;
  end

  if (CHERIoTEn & CheriStkClr) begin : g_stkclr
    cheri_stkclr cheri_stkclr_i (
      .clk_i                    (clk_i                  ),
      .rst_ni                   (rst_ni                 ),
      .csr_stkclr_ptr_wr_i      (csr_stkclr_ptr_wr_i    ),
      .csr_stkclr_ptr_wdata_i   (csr_stkclr_ptr_wdata_i ),
      .csr_mshwm_i              (csr_mshwm_i            ),
      .unmasked_intr_i          (unmasked_intr_i        ),
      .stkclr_active_o          (stkclr_active_o        ),
      .stkclr_abort_o           (stkclr_abort_o         ),
      .stkclr_ptr_o             (stkclr_ptr_o           ),
      .stkclr_base_o            (stkclr_base_o          ),
      .stkclr_err_o             (stkclr_err             ),
      .lsu_stkclr_resp_valid_i  (lsu_blk0_resp_valid    ),
      .lsu_stkclr_resp_err_i    (lsu_tbre_resp_err_i    ),
      .lsu_stkclr_req_done_i    (lsu_blk0_req_done      ),
      .stkclr_lsu_req_o         (blk0_lsu_req           ),
      .stkclr_lsu_we_o          (blk0_lsu_we            ),
      .stkclr_lsu_is_cap_o      (blk0_lsu_is_cap        ),
      .stkclr_lsu_addr_o        (blk0_lsu_addr          ),
      .stkclr_lsu_wdata_o       (blk0_lsu_wdata         ),
      .snoop_lsu_req_done_i     (snoop_lsu_req_done_i   )
      );

  end else begin
    assign stkclr_active_o = 1'b0;
    assign stkclr_abort_o  = 1'b0;
    assign stkclr_ptr_o    = 32'h3;     // use this to flag stkclr feature doesn't exist
    assign stkclr_base_o   = 32'h0;
    assign stkclr_err      = 1'b0;

    assign blk0_lsu_req    = 1'b0;
    assign blk0_lsu_is_cap = 1'b0;
    assign blk0_lsu_we     = 1'b0;
    assign blk0_lsu_addr   = 32'h0;
    assign blk0_lsu_wdata  = 33'h0;
  end

  //
  // Arbitration for LSU interface between tbre and stkclr engines
  //  reuse the obimux logic
  //
  logic [nMSTR-1:0] mstr_arbit, mstr_arbit_q, mstr_arbit_comb;
  logic [nMSTR-1:0] mstr_req, mstr_gnt;
  logic             req_pending, req_pending_q;
  logic             slv_req, slv_gnt;

  assign slv_req = |mstr_req;
  assign mstr_gnt = {nMSTR{slv_gnt}} & mstr_arbit_comb;

  // arbitration by strict priority assignment - mst_req[0] == highest priority
  for (genvar i = 0; i < nMSTR; i++) begin
    logic [7:0] pri_mask;
    assign pri_mask = 8'hff >> (8-i);      // max 8 masters, should be enough 
    assign mstr_arbit[i] = mstr_req[i] & ~(|(mstr_req & pri_mask));
  end

  // make the next arbiration decision immediately when receiving grant so that
  // the address/wdata/ctrl can be hold steady when presenting the next request 
  // to the slave (otherwise may violate the obi protocol?)
  assign mstr_arbit_comb = req_pending_q ? mstr_arbit_q : mstr_arbit;
  assign req_pending = |mstr_req & ~slv_gnt;

  always @(posedge clk_i or negedge rst_ni) begin
    if(~rst_ni) begin
      req_pending_q  <= 1'b0;
      mstr_arbit_q   <= 0;
    end else begin
      req_pending_q <= req_pending;
      if (req_pending) mstr_arbit_q <= mstr_arbit;
    end
  end

  // muxing the outgoing control signals
  assign slv_gnt  = lsu_tbre_req_done_i;
  assign mstr_req = {blk1_lsu_req,  blk0_lsu_req};

  assign tbre_lsu_req_o     = slv_req;
  assign tbre_lsu_is_cap_o  = mstr_arbit_comb[1] ? blk1_lsu_is_cap : blk0_lsu_is_cap;
  assign tbre_lsu_we_o      = mstr_arbit_comb[1] ? blk1_lsu_we : blk0_lsu_we;
  assign tbre_lsu_addr_o    = mstr_arbit_comb[1] ? blk1_lsu_addr : blk0_lsu_addr;
  assign tbre_lsu_wdata_o   = mstr_arbit_comb[1] ? blk1_lsu_wdata : blk0_lsu_wdata;

  assign lsu_blk1_req_done  = mstr_arbit_comb[1] & lsu_tbre_req_done_i; 
  assign lsu_blk0_req_done  = mstr_arbit_comb[0] & lsu_tbre_req_done_i; 

  // 
  logic resp_sel_q;
  always @(posedge clk_i or negedge rst_ni) begin
    if(~rst_ni) begin
      resp_sel_q <= 1'b0;
    end else if (lsu_tbre_req_done_i) begin
      resp_sel_q <= (mstr_arbit_comb[1]);
    end
  end

  assign lsu_blk0_resp_valid = ~resp_sel_q & lsu_tbre_resp_valid_i;
  assign lsu_blk1_resp_valid =  resp_sel_q & lsu_tbre_resp_valid_i;


endmodule