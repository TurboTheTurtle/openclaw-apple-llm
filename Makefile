PREFIX ?= /usr/local

.PHONY: build release install uninstall clean

build:
	swift build

release:
	swift build -c release

install: release
	ln -sf $(shell pwd)/.build/release/apple-llm $(PREFIX)/bin/apple-llm

uninstall:
	rm -f $(PREFIX)/bin/apple-llm

clean:
	swift package clean
