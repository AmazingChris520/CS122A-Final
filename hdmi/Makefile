.PHONY: clean

%.sim: tb/%_tb.sv #src/*.sv
	iverilog -g2012 -o build/$@ $<
	vvp build/$@
	gtkwave build/$*.vcd

%.bit: src/*.sv
	yosys -p "synth_ecp5 -json build/$*.json" $^
	nextpnr-ecp5 --25k --package CABGA256 --speed 6 --json build/$*.json --textcfg build/$*.cfg --lpf $*.lpf --freq 65 --lpf-allow-unconstrained
	ecppack --svf build/$*.svf build/$*.cfg build/$@

clean:
	rm -f build/*