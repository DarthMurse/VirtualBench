# VirtualBench task runner. The benchmarks use standard off-the-shelf tools, so there
# is nothing to compile — these targets just wrap the common workflows.
LABEL  ?= local
CONFIG ?= config.json

.PHONY: help deps smoke run analyze clean

help:
	@echo "VirtualBench targets:"
	@echo "  make deps                 install Linux benchmark tools (apt; needs sudo)"
	@echo "  make smoke                fast end-to-end smoke test (config.smoke.json)"
	@echo "  make run LABEL=virtualbox run full benchmark with LABEL (CONFIG=config.json)"
	@echo "  make analyze              aggregate results/ into a comparison table"
	@echo "  make clean                remove scratch test dirs"

deps:
	sudo apt-get update
	sudo apt-get install -y sysbench fio iperf3 p7zip-full jq bc

# Spins up a loopback iperf3 server so the network module has a target, then runs
# the Linux runner with tiny parameters and prints the analysis.
smoke:
	@command -v iperf3 >/dev/null 2>&1 && (pgrep -x iperf3 >/dev/null || iperf3 -s -D) || true
	bash scripts/run_linux.sh --label wsl-smoke --config config.smoke.json
	python3 analyze/analyze.py results

run:
	bash scripts/run_linux.sh --label $(LABEL) --config $(CONFIG)

analyze:
	python3 analyze/analyze.py results

clean:
	rm -rf fio_testdir app_testdir
