use ExtUtils::MakeMaker; 

my @exe_files = ( "perfsonar-collector", "psConfigureCollectors" );

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Collectors::Daemon',
    'VERSION_FROM' => 'perfsonar-collector',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"Log::Log4perl" => 1.00,
	"Getopt::Long" => 0,
	"POSIX" => 0,
	"Fcntl" => 0,
	"Cwd" => 0,
	"File::Basename" => 0,
	"Module::Load" => 0.10,
	"Time::HiRes" => 1.85,
	"Config::General" => 2.30,
	"perfSONAR_PS::Common" => 0.04,
    },

    EXE_FILES => \@exe_files,
);

package MY;

sub postamble {'

sysconfdir	= $(PREFIX)/etc

install ::

	if [ "$(sysconfdir)" = "/usr/etc" ]; then \
		if [ ! -d /etc/perfsonar ]; then \
		    mkdir -p /etc/perfsonar; \
		fi; \
		\
		if [ ! -f /etc/perfsonar/collector.conf ]; then \
		    touch /etc/perfsonar/collector.conf; \
		fi; \
		\
		if [ ! -f /etc/perfsonar/logger.conf ]; then \
		    install -c -D -m 0644 logger.conf /etc/perfsonar/logger.conf; \
		else \
		    echo "Old configuration file exists at /etc/perfsonar/logger.conf: not overwritten."; \
		fi; \
		\
		if [ -d /etc/init.d ]; then \
		    mkdir -p /etc/init.d; \
		fi; \
		\
		install -c -D -m 0755 perfsonar-collector.init /etc/init.d/perfsonar-collector; \
		awk "{gsub(/^BINDIR=.*/,\"BINDIR=$(INSTALLBIN)\"); gsub(/^PREFIX=.*/,\"PREFIX=$(PREFIX)\"); gsub(/^CONFDIR=.*/,\"CONFDIR=/etc\"); print}" /etc/init.d/perfsonar-collector > /etc/init.d/perfsonar-collector.new; \
		mv -f /etc/init.d/perfsonar-collector.new /etc/init.d/perfsonar-collector; \
		chmod +x /etc/init.d/perfsonar-collector; \
		\
		perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/perfsonar; \
		awk "{gsub(/XXX_LIBDIR_XXX/,\"$(INSTALLSITELIB)\"); gsub(/XXX_CONFDIR_XXX/,\"/etc/perfsonar\"); print}" $(INSTALLBIN)/perfsonar > $(INSTALLBIN)/perfsonar.new; \
		mv -f $(INSTALLBIN)/perfsonar.new $(INSTALLBIN)/perfsonar; \
		chmod +x $(INSTALLBIN)/perfsonar; \
		\
		perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/psConfigureCollectors; \
		awk "{gsub(/XXX_DEFAULT_XXX/,\"/etc/perfsonar/collector.conf\"); print}" $(INSTALLBIN)/psConfigureCollectors > $(INSTALLBIN)/psConfigureCollectors.new; \
		mv -f $(INSTALLBIN)/psConfigureCollectors.new $(INSTALLBIN)/psConfigureCollectors; \
		chmod +x $(INSTALLBIN)/psConfigureCollectors; \
	else \
		if [ ! -d $(sysconfdir)/perfsonar ]; then \
		    mkdir -p $(sysconfdir)/perfsonar; \
		fi; \
		\
		if [ ! -f $(sysconfdir)/perfsonar/collector.conf ]; then \
		    touch $(sysconfdir)/perfsonar/collector.conf; \
		fi; \
		\
		if [ ! -f $(sysconfdir)/perfsonar/logger.conf ]; then \
		    install -c -D -m 0644 logger.conf $(sysconfdir)/perfsonar/logger.conf; \
		else \
		    echo "Old configuration file exists at $(sysconfdir)/perfsonar/logger.conf: not overwritten."; \
		fi; \
		\
		if [ -d $(sysconfdir)/init.d ]; then \
		    mkdir -p $(sysconfdir)/init.d; \
		fi; \
		\
		install -c -D -m 0755 perfsonar-collector.init $(sysconfdir)/init.d/perfsonar-collector; \
		awk "{gsub(/^BINDIR=.*/,\"BINDIR=$(INSTALLBIN)\"); gsub(/^PREFIX=.*/,\"PREFIX=$(PREFIX)\"); gsub(/^CONFDIR=.*/,\"CONFDIR=$(sysconfdir)\"); print}" $(sysconfdir)/init.d/perfsonar-collector > $(sysconfdir)/init.d/perfsonar-collector.new; \
		mv -f $(sysconfdir)/init.d/perfsonar-collector.new $(sysconfdir)/init.d/perfsonar-collector; \
		chmod +x $(sysconfdir)/init.d/perfsonar-collector; \
		\
		perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/perfsonar; \
		awk "{gsub(/XXX_LIBDIR_XXX/,\"$(INSTALLSITELIB)\"); gsub(/XXX_CONFDIR_XXX/,\"$(sysconfdir)/perfsonar\"); print}" $(INSTALLBIN)/perfsonar > $(INSTALLBIN)/perfsonar.new; \
		mv -f $(INSTALLBIN)/perfsonar.new $(INSTALLBIN)/perfsonar; \
		chmod +x $(INSTALLBIN)/perfsonar; \
		\
		perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/psConfigureCollectors; \
		awk "{gsub(/XXX_DEFAULT_XXX/,\"$(sysconfdir)/perfsonar/collector.conf\"); print}" $(INSTALLBIN)/psConfigureCollectors > $(INSTALLBIN)/psConfigureCollectors.new; \
		mv -f $(INSTALLBIN)/psConfigureCollectors.new $(INSTALLBIN)/psConfigureCollectors; \
		chmod +x $(INSTALLBIN)/psConfigureCollectors; \
	fi;
';}
