# Compila los módulos en C dentro de bin/
CC      = gcc
CFLAGS  = -Wall -Wextra -O2
SRC     = src/modulos
BIN     = bin

PROGS   = $(BIN)/01_inventario $(BIN)/02_monitor $(BIN)/03_carga_cpu $(BIN)/04_carga_ram

all: $(BIN) $(PROGS)

$(BIN):
	mkdir -p $(BIN)

$(BIN)/%: $(SRC)/%.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -rf $(BIN)

.PHONY: all clean
