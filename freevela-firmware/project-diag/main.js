// Diagnostic main for QEMU: run the firmware main, reporting load errors.
import("main_real").then(() => trace("diag: main_real loaded\n"), (e) => trace(`diag: FAIL ${e}\n`));
