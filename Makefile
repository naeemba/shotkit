PREFIX ?= /usr/local
DESTDIR ?=
BINDIR = $(DESTDIR)$(PREFIX)/bin
SHAREDIR = $(DESTDIR)$(PREFIX)/share/shotkit

.PHONY: install uninstall test

install:
	install -Dm755 shotkit $(BINDIR)/shotkit
	install -Dm755 scroll-stitch.py $(SHAREDIR)/scroll-stitch.py
	install -Dm644 overlay/shell.qml $(SHAREDIR)/overlay/shell.qml
	install -Dm644 overlay/geometry.js $(SHAREDIR)/overlay/geometry.js
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/shotkit/LICENSE

uninstall:
	rm -f $(BINDIR)/shotkit
	rm -rf $(SHAREDIR) $(DESTDIR)$(PREFIX)/share/licenses/shotkit

test:
	tests/shotkit.test.sh
	python3 tests/scroll-stitch.test.py
	node --test tests/geometry.test.mjs
