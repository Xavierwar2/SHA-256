`timescale 1ns/1ps
module sha256_gate_local_tb;
    reg clk = 0;
    always #7.5 clk = ~clk; // 15 ns clock; zero-delay functional cell models.
    reg rst = 0, soc = 0, rd = 0;
    reg [31:0] data_in = 0;
    wire [31:0] data_out;
    wire eoc, data_oe;
    SHA256 dut (.clk(clk), .rst(rst), .soc(soc), .rd(rd),
                .data_in(data_in), .data_out(data_out), .data_oe(data_oe), .eoc(eoc));
    initial begin
`ifndef SYNTH_GATE
        // OpenROAD exports VDD/VSS; Yosys synthesis omits supply pins.
        force dut.VDD = 1'b1;
        force dut.VSS = 1'b0;
`endif
        $dumpfile("gate.vcd");
        $dumpvars(1, sha256_gate_local_tb);
    end
    task check_message;
        input [511:0] block;
        input [255:0] expected;
        input [63:0] name;
        integer i, cycles;
        begin
            @(negedge clk);
            rd = 0; rst = 1; soc = 1; data_in = 0;
            repeat (3) @(negedge clk);
            rst = 0; soc = 0; data_in = block[511:480];
            for (i = 1; i < 16; i = i + 1) begin
                @(negedge clk);
                data_in = block[511-32*i -: 32];
            end
            @(negedge clk);
            data_in = 0;
            cycles = 0;
            while (eoc !== 1'b1) begin
                @(negedge clk);
                cycles = cycles + 1;
                if (cycles > 100) $fatal(1, "EOC timeout for %0s", name);
            end
            rd = 1;
            for (i = 0; i < 8; i = i + 1) begin
                #1;
                if (data_oe !== 1'b1 || data_out !== expected[255-32*i -: 32])
                    $fatal(1, "%0s word %0d: got %08h, expected %08h, oe=%b",
                           name, i, data_out, expected[255-32*i -: 32], data_oe);
                @(negedge clk);
            end
            rd = 0;
            $display("PASS [%0s]: all 8 hash words match", name);
        end
    endtask
    initial begin
        check_message({32'h80000000, 480'b0},
                      256'he3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855, "empty");
        check_message({32'h61626380, 448'b0, 32'h00000018},
                      256'hba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad, "abc");
`ifdef SYNTH_GATE
        $display("ALL POST-SYNTHESIS FUNCTIONAL TESTS PASSED");
`else
        $display("ALL POST-ROUTE FUNCTIONAL TESTS PASSED");
`endif
        $finish;
    end
    initial begin
        #20000;
        $fatal(1, "Global simulation timeout");
    end
endmodule
