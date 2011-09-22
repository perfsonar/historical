PACKAGE=perfSONAR_PS-PingER-GUI
ROOTPATH=/opt/perfsonar_ps/PingER-GUI
VERSION=3.2.1
RELEASE=3
ARCH=i386

default:
	@echo No need to build the package. Just run \"make install\"

dist:
	mkdir /tmp/$(PACKAGE)-$(VERSION).$(RELEASE).$(ARCH)
	tar ch -T MANIFEST | tar x -C /tmp/$(PACKAGE)-$(VERSION).$(RELEASE).$(ARCH)
	cd /tmp/$(PACKAGE)-$(VERSION).$(RELEASE).$(ARCH) && ln -s doc/LICENSE LICENSE
	cd /tmp/$(PACKAGE)-$(VERSION).$(RELEASE).$(ARCH) && ln -s doc/INSTALL INSTALL
	cd /tmp/$(PACKAGE)-$(VERSION).$(RELEASE).$(ARCH) && ln -s doc/README README
	tar czf $(PACKAGE)-$(VERSION).$(RELEASE).$(ARCH).tar.gz -C /tmp $(PACKAGE)-$(VERSION).$(RELEASE).$(ARCH)
	rm -rf /tmp/$(PACKAGE)-$(VERSION).$(RELEASE).$(ARCH)
rpm:    dist
	mkdir -p ~/rpmbuild/SOURCES ~/rpmbuild/RPMS ~/rpmbuild/SPEC ~/rpmbuild/SRPMS  ~/rpmbuild/tmp  ~/rpmbuild/BUILD
	cp $(PACKAGE)-$(VERSION).$(RELEASE).$(ARCH).tar.gz  ~/rpmbuild/SOURCES/
	/usr/bin/rpmbuild  -ba --sign  -D 'arch $(ARCH)' perl-perfSONAR_PS-PingER-GUI.spec

upgrade:
	mkdir /tmp/$(PACKAGE)-$(VERSION).$(RELEASE)
	tar ch --exclude=etc/* -T MANIFEST | tar x -C /tmp/$(PACKAGE)-$(VERSION).$(RELEASE)
	tar czf $(PACKAGE)-$(VERSION).$(RELEASE)-upgrade.tar.gz -C /tmp $(PACKAGE)-$(VERSION).$(RELEASE)
	rm -rf /tmp/$(PACKAGE)-$(VERSION).$(RELEASE)

install:
	for i in `ls ./scripts`; do sed -i "s|/opt/perfsonar_ps/PingER-GUI|${ROOTPATH}|g" ./scripts/$${i}; done
	mkdir -p ${ROOTPATH}
	tar ch --exclude=etc/* --exclude=*spec --exclude=MANIFEST --exclude=Makefile -T MANIFEST | tar x -C ${ROOTPATH}
	for i in `cat MANIFEST | grep ^etc`; do  mkdir -p `dirname $(ROOTPATH)/$${i}`; if [ -e $(ROOTPATH)/$${i} ]; then install -m 640 -c $${i} $(ROOTPATH)/$${i}.new; else install -m 640 -c $${i} $(ROOTPATH)/$${i}; fi; done
