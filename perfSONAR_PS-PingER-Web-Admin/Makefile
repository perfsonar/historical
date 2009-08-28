PACKAGE=perfSONAR_PS-PingER-Web-Admin
PREFIX=/opt/perfsonar_ps/pinger_web_admin

dist:
	mkdir /tmp/$(PACKAGE)
	tar ch -T MANIFEST | tar x -C /tmp/$(PACKAGE)
	tar czf $(PACKAGE).tar.gz -C /tmp $(PACKAGE)
	rm -rf /tmp/$(PACKAGE)

install:
	mkdir -p ${PREFIX}
	tar ch --exclude=etc/* --exclude=*spec --exclude=MANIFEST --exclude=Makefile -T MANIFEST | tar x -C ${PREFIX}
	for i in `cat MANIFEST | grep ^etc`; do  mkdir -p `dirname $(PREFIX)/$${i}`; if [ -e $(PREFIX)/$${i} ]; then install -m 644 -c $${i} $(PREFIX)/$${i}.new; else install -m 644 -c $${i} $(PREFIX)/$${i}; fi; done
