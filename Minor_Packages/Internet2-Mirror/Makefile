PACKAGE=Internet2-Mirror
ROOTPATH=/opt/perfsonar_ps/Internet2-Mirror
VERSION=0.1
RELEASE=1

default:
	@echo No need to build the package. Just run \"make install\"

dist:
	mkdir /tmp/$(PACKAGE)-$(VERSION).$(RELEASE)
	tar ch -T MANIFEST | tar x -C /tmp/$(PACKAGE)-$(VERSION).$(RELEASE)
	cd /tmp/$(PACKAGE)-$(VERSION).$(RELEASE) && ln -s doc/LICENSE LICENSE
	cd /tmp/$(PACKAGE)-$(VERSION).$(RELEASE) && ln -s doc/INSTALL INSTALL
	cd /tmp/$(PACKAGE)-$(VERSION).$(RELEASE) && ln -s doc/README README
	tar czf $(PACKAGE)-$(VERSION).$(RELEASE).tar.gz -C /tmp $(PACKAGE)-$(VERSION).$(RELEASE)
	rm -rf /tmp/$(PACKAGE)-$(VERSION).$(RELEASE)

upgrade:
	mkdir /tmp/$(PACKAGE)-$(VERSION).$(RELEASE)
	tar ch --exclude=etc/* -T MANIFEST | tar x -C /tmp/$(PACKAGE)-$(VERSION).$(RELEASE)
	tar czf $(PACKAGE)-$(VERSION).$(RELEASE)-upgrade.tar.gz -C /tmp $(PACKAGE)-$(VERSION).$(RELEASE)
	rm -rf /tmp/$(PACKAGE)-$(VERSION).$(RELEASE)

rpminstall:
	mkdir -p ${ROOTPATH}
	tar ch --exclude=etc/* --exclude=*spec --exclude=MANIFEST --exclude=Makefile -T MANIFEST | tar x -C ${ROOTPATH}
	for i in `cat MANIFEST | grep ^etc`; do  mkdir -p `dirname $(ROOTPATH)/$${i}`; if [ -e $(ROOTPATH)/$${i} ]; then install -m 640 -c $${i} $(ROOTPATH)/$${i}.new; else install -m 640 -c $${i} $(ROOTPATH)/$${i}; fi; done

install:
	for i in `ls ./scripts`; do sed -i "s|/opt/perfsonar_ps/perfAdmin|${ROOTPATH}|g" ./scripts/$${i}; done
	mkdir -p ${ROOTPATH}
	tar ch --exclude=etc/* --exclude=*spec --exclude=MANIFEST --exclude=Makefile -T MANIFEST | tar x -C ${ROOTPATH}
	for i in `cat MANIFEST | grep ^etc`; do  mkdir -p `dirname $(ROOTPATH)/$${i}`; if [ -e $(ROOTPATH)/$${i} ]; then install -m 640 -c $${i} $(ROOTPATH)/$${i}.new; else install -m 640 -c $${i} $(ROOTPATH)/$${i}; fi; done
