"""Regression checks for escaped buses, global supply pins and strict parsing."""
from pathlib import Path
import tempfile
import unittest

from lvs import parse_def, parse_verilog
from run_lvs_15ns import write_cdl, report_matches


class ParserTests(unittest.TestCase):
    def parse(self, parser, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture"
            path.write_text(text)
            return parser(path)

    def test_escaped_vector_connection_and_expanded_ports(self):
        instances, _, ports, design = self.parse(parse_verilog, r"""
module chip(a, y);
input [1:0] a;
output y;
wire [1:0] \stage.mem[0] ;
sky130_fd_sc_hd__inv_1 u (.A(\stage.mem[0] [1]), .Y(y));
endmodule
""")
        self.assertEqual(design, "chip")
        self.assertEqual(instances["u"][1]["A"], "stage.mem[0][1]")
        self.assertEqual(ports, [("a[0]", "INPUT"), ("a[1]", "INPUT"), ("y", "OUTPUT")])

    def test_def_power_wildcard_and_routing_are_distinct(self):
        instances, nets, ports, _ = self.parse(parse_def, r"""
DESIGN chip ;
COMPONENTS 1 ;
- u sky130_fd_sc_hd__inv_1 + PLACED ( 0 0 ) N ;
END COMPONENTS
PINS 1 ;
- y + NET y + DIRECTION OUTPUT ;
END PINS
NETS 2 ;
- stage.mem\[0\][1] ( u A ) + ROUTED met1 ( 1 2 ) ( 3 4 ) ;
- y ( PIN y ) ( u Y ) ;
END NETS
SPECIALNETS 1 ;
- VDD ( * VPWR ) + USE POWER ;
END SPECIALNETS
""")
        self.assertEqual(instances["u"][1], {"A": "stage.mem[0][1]", "Y": "y", "VPWR": "VDD"})
        self.assertEqual(nets["stage.mem[0][1]"], [("u", "A")])
        self.assertIn(("VDD", "INOUT"), ports)

    def test_reject_unsupported_logic_instead_of_skipping_it(self):
        with self.assertRaises(ValueError):
            self.parse(parse_verilog, "module chip(a,y); input a; output y; assign y=~a; endmodule")

    def test_reject_truncated_def(self):
        with self.assertRaisesRegex(ValueError, "expected 2 records"):
            self.parse(parse_def, "DESIGN chip ;\nCOMPONENTS 2 ;\n- u inv ;\nEND COMPONENTS\n")

    def test_missing_supply_is_not_guessed(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "Missing LAYOUT pin u/VPWR"):
                write_cdl(Path(directory) / "test.cdl", "LAYOUT",
                          {"u": ("inv", {"A": "a", "Y": "y"})}, [], "chip",
                          {"inv": ["A", "Y", "VPWR"]})

    def test_confirmed_floating_output_has_its_own_node(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.cdl"
            write_cdl(path, "LAYOUT", {"u": ("inv", {"A": "a"})}, [], "chip",
                      {"inv": ["A", "Y"]}, open_pins={("u", "Y")})
            self.assertIn("Xu a __OPEN_u_Y inv", path.read_text())

    def test_subcell_match_does_not_override_top_level_mismatch(self):
        self.assertFalse(report_matches("Netlists match uniquely.\nFinal result: Netlists do not match.\n"))
        self.assertTrue(report_matches("Final result: Circuits match uniquely.\n"))
        self.assertFalse(report_matches("Netlists match uniquely.\n"))


if __name__ == "__main__":
    unittest.main()
