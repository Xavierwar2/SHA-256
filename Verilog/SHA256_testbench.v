/*!
* @file SHA256_testbench.v
* @brief SHA256 TestBench
* @author LDFranck
* @date February 2023
* @version v1
*
* @details
*  SHA256 testbench implementation in Verilog.
*  The test routine defaults to 'tb_data_abc.txt' (single-block abc).
*  Override with vvp sha256_sim +DATA=your_test_data.txt.
*  The original tb_data.txt needs multi-block chaining, unsupported by
*  the current wvar.v, which reloads IV on every soc pulse.
*  The test routine utilizes an external file
*  as input and verification data to the SHA256 hash function.
*  The file must be formatted as the provided example.
*  The binary padded message block and the final hexadecimal
*  hash can be obtained from: https://sha256algorithm.com/
*/

`define NULL 0
`timescale 1ns / 1ps	//!< <time unit> / <time precision>

module SHA256_testbench();

	// DUT:
	wire [31:0] wdata_out;
	wire wdata_oe, weoc;
	SHA256 dut (
		.data_in(rdata),
		.data_out(wdata_out),
		.data_oe(wdata_oe),
		.eoc(weoc),
		.clk(rclk),
		.rst(rrst),
		.soc(rsoc),
		.rd(rrd)
	);

	// TestBench:
	reg [8*1024-1:0] data_file;
	integer file;
	integer msg_blocks, i;

	reg [31:0] rdata, hash;
	reg rclk, rrst, rsoc, rrd;

	initial begin
		$display("TestBench Running...");

		if (!$value$plusargs("DATA=%s", data_file))
			data_file = "tb_data_abc.txt";
		file = $fopen(data_file, "r");

		if(file == `NULL) begin
			$fatal(1, "OPEN FILE ERROR: %0s", data_file);
		end

		if($fscanf(file, "msg_blocks=%d\n", msg_blocks) != 1) begin
			$fatal(1, "READ FILE ERROR");
		end

		if (msg_blocks != 1)
			$fatal(1, "Current RTL supports only one message block; got %0d", msg_blocks);

		rdata = 32'b0;
		rclk = 1'b0;
		rrst = 1'b0;
		rsoc = 1'b0;
		rrd  = 1'b0;

		#25 rrst = 1'b1;
		#50 rrst = 1'b0;

		for(i = 0; i < msg_blocks; i = i + 1) begin
			#50 rsoc = 1'b1;
			#50 rsoc = 1'b0;

			#50;
			if($fscanf(file, "%b\n", rdata) != 1) begin
				$fatal(1, "READ FILE ERROR");
			end
			repeat(15) #100
				if($fscanf(file, "%b\n", rdata) != 1) begin
					$fatal(1, "READ FILE ERROR");
				end
			#100 rdata = 32'b0;
			repeat(48) #100;
			#50;
		end

		if (weoc !== 1'b1)
			$fatal(1, "Calculation did not complete");
		#25 rrd = 1'b1;
		#1; // Allow output enable to settle before checking the first word.
		for(i = 0; i < 8; i = i + 1) begin
			if($fscanf(file, "%h\n", hash) != 1) begin
				$fatal(1, "READ FILE ERROR");
			end
			if (wdata_oe !== 1'b1 || hash !== wdata_out) begin
				$fatal(1, "HASH ERROR word %0d: expected %08h, got %08h (oe=%b)",
				       i, hash, wdata_out, wdata_oe);
			end
			#100;
		end

		$display("MSG SUCCESSFULLY HASHED");

		$fclose(file);
		$finish;
	end

	always #50 rclk = ~rclk;

endmodule
