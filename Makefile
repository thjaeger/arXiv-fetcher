all:	arXiv-fetcher

arXiv-fetcher:	arXiv-fetcher.vala
	valac -X -w $< --pkg glib-2.0 --pkg gtk+-3.0 --pkg gee-1.0 --pkg libsoup-2.4 --pkg libxml-2.0 -o $@
