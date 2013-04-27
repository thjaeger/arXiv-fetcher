.SUFFIXES:
.SECONDARY:
.PHONY:	all clean

BINARY     := arXiv-fetcher
PACKAGES   := glib-2.0 gtk+-3.0 gee-1.0 libsoup-2.4 libxml-2.0
VALAFILES  := $(wildcard *.vala)
VAPIFILES  := $(patsubst %.vala,%.vapi,$(VALAFILES))
VAPISTAMPS := $(addsuffix .stamp,$(VAPIFILES))
DEPFILES   := $(patsubst %.vala,%.dep,$(VALAFILES))
DEPSTAMPS  := $(addsuffix .stamp,$(DEPFILES))
OFILES     := $(patsubst %.vala,%.o,$(VALAFILES))
CFILES     := $(patsubst %.vala,%.c,$(VALAFILES))
PKGFLAGS   := $(addprefix --pkg ,$(PACKAGES))
LIBS       := `pkg-config $(PACKAGES) --libs`
INCLUDES   := `pkg-config $(PACKAGES) --cflags`

all:	$(BINARY)

arXiv-fetcher:	$(OFILES)
	gcc $(OFILES) -o $@ $(LIBS)

%.vapi.stamp:	%.vala
	valac --fast-vapi=$*.vapi $< && touch $@

%.dep.stamp:	%.vala | $(VAPISTAMPS)
	valac -C $(PKGFLAGS) --deps=$*.dep $(addprefix --use-fast-vapi=,$(patsubst $*.vapi,,$(VAPIFILES))) $< && touch $@

%.o:	%.dep.stamp
	gcc -w $(INCLUDES) -o $@ -c $*.c

include $(wildcard *.dep)

clean:
	$(RM) $(BINARY) $(VAPIFILES) $(VAPISTAMPS) $(OFILES) $(DEPFILES) $(DEPSTAMPS) $(CFILES)
