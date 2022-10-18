// Copyright Microsoft Corporation
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module cheri_trvk_stage #(
  parameter int unsigned HeapBase,
  parameter int unsigned TSMapSize
) (
   // Clock and Reset
  input  logic                clk_i,
  input  logic                rst_ni,

  input  logic                rf_trsv_en_i,
  input  logic [4:0]          rf_trsv_addr_i,

  // from wb_stage
  input  logic                lsu_resp_valid_i,
  input  logic                lsu_resp_err_i,
  input  logic [31:0]         rf_wdata_lsu_i,
  input  cheri_pkg::reg_cap_t rf_wcap_lsu_i,

  output logic [4:0]          rf_trvk_addr_o,
  output logic                rf_trvk_en_o,
  output logic                rf_trvk_clrtag_o,

  output logic                tsmap_cs_o,
  output logic [15:0]         tsmap_addr_o,
  input  logic [31:0]         tsmap_rdata_i
);

  import cheri_pkg::*;

  reg_cap_t    in_cap_q;
  logic [31:0] in_data_q;

  logic        op_active;
  logic [2:0]  op_valid_q, cap_good_q;
  logic [4:0]  trsv_addr;
  logic [4:0]  trsv_addr_q[2:0];
  logic        trvk_status;

  logic [31:0] base32;
  logic [31:0] tsmap_ptr;
  logic  [4:0] bitpos, bitpos_q;    // bit index in a 32-bit word
  logic        range_ok;
  logic  [2:1] range_ok_q;

  assign base32    = get_bound33(in_cap_q.base, in_cap_q.base_cor, in_cap_q.exp, in_data_q);
  assign tsmap_ptr = (base32 - HeapBase) >> 3;

  assign tsmap_addr_o  = tsmap_ptr[15:5];
  assign range_ok      = (tsmap_addr_o <= TSMapSize);
  assign tsmap_cs_o    = op_valid_q[0] & cap_good_q[0];

  assign rf_trvk_en_o     =  op_valid_q[2];
  assign rf_trvk_clrtag_o =  trvk_status & cap_good_q[2] & range_ok_q[2];
  assign rf_trvk_addr_o   =  trsv_addr_q[2];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      op_active <= 1'b0;
      trsv_addr  <= 4'h0;
    end else begin
      if (rf_trsv_en_i) op_active <= 1'b1;
      else if (lsu_resp_valid_i) op_active <= 1'b0;

      if (rf_trsv_en_i)  trsv_addr <= rf_trsv_addr_i;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    int i;
    if (!rst_ni) begin
      op_valid_q  <= 0;
      cap_good_q  <= 0;
      in_cap_q    <= NULL_REG_CAP;
      in_data_q   <= 32'h0;
      bitpos_q    <= 0;
      trvk_status <= 1'b0;
      range_ok_q  <= 0;
      trsv_addr_q <= {'0, '0, '0};
    end else begin
      // control signal per stage
      op_valid_q  <= {op_valid_q[1:0], op_active & lsu_resp_valid_i};
      cap_good_q  <= {cap_good_q[1:0], op_active & lsu_resp_valid_i & ~lsu_resp_err_i & rf_wcap_lsu_i.valid};
      trsv_addr_q[0] <= trsv_addr;
      trsv_addr_q[1] <= trsv_addr_q[0];
      trsv_addr_q[2] <= trsv_addr_q[1];

      // stage 0 status: register loaded cap
      if (op_active & lsu_resp_valid_i & ~lsu_resp_err_i) begin
        in_cap_q    <= rf_wcap_lsu_i;
        in_data_q   <= rf_wdata_lsu_i;
      end

      // stage 1 status:
      bitpos_q      <= tsmap_ptr[4:0];
      range_ok_q[1] <= range_ok;

      // stage 2: index map data
      range_ok_q[2] <= range_ok_q[1];
      trvk_status   <= tsmap_rdata_i[bitpos_q];
    end
  end

endmodule