PACKAGE=counters_webpage
PREFIX=/opt/perfsonar_ps/counters_webpage

default:
	@echo No need to build the package. Just run \"make install\"

dist:
	mkdir /tmp/$(PACKAGE)
	tar ch -T MANIFEST | tar x -C /tmp/$(PACKAGE)
	tar czf $(PACKAGE).tar.gz -C /tmp $(PACKAGE)
	rm -rf /tmp/$(PACKAGE)

upgrade:
	mkdir /tmp/$(PACKAGE)
	tar ch --exclude=etc/* -T MANIFEST | tar x -C /tmp/$(PACKAGE)
	tar czf $(PACKAGE)-upgrade.tar.gz -C /tmp $(PACKAGE)
	rm -rf /tmp/$(PACKAGE)

install:
	mkdir -p ${PREFIX}
	tar ch --exclude=etc/* --exclude=*spec --exclude=MANIFEST --exclude=Makefile -T MANIFEST | tar x -C ${PREFIX}
	for i in `cat MANIFEST | grep ^etc`; do  mkdir -p `dirname $(PREFIX)/$${i}`; if [ -e $(PREFIX)/$${i} ]; then install -m 640 -c $${i} $(PREFIX)/$${i}.new; else install -m 640 -c $${i} $(PREFIX)/$${i}; fi; done
