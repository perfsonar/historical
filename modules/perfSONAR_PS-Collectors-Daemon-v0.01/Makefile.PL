use ExtUtils::MakeMaker; 

my @exe_files = ( "perfsonar-collector", "psConfigureCollectors" );

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Collectors::Daemon',
    'VERSION_FROM' => 'perfsonar-collector',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
        "version" => 0.50,
	"Log::Log4perl" => 1.00,
	"Getopt::Long" => 0,
	"POSIX" => 0,
	"Fcntl" => 0,
	"Cwd" => 0,
	"File::Basename" => 0,
	"Module::Load" => 0.10,
	"Time::HiRes" => 1.85,
	"Config::General" => 2.30,
	"perfSONAR_PS::Common" => "v0.01",
    },

    EXE_FILES => \@exe_files,
);

package MY;

sub postamble {'

sysconfdir	= $(PREFIX)/etc

install ::

	if [ ! -d $(sysconfdir)/perfsonar ]; then \
	    mkdir -p $(sysconfdir)/perfsonar; \
	fi;

	if [ ! -f $(sysconfdir)/perfsonar/collector.conf ]; then \
	    touch $(sysconfdir)/perfsonar/collector.conf; \
	fi;

	if [ ! -f $(sysconfdir)/perfsonar/logger.conf ]; then \
	    install -c -D -m 0644 logger.conf $(sysconfdir)/perfsonar/logger.conf; \
	else \
	    echo "Old configuration file exists at $(sysconfdir)/perfsonar/logger.conf: not overwritten."; \
	fi;

	if [ ! -d $(sysconfdir)/init.d ]; then \
	    mkdir $(sysconfdir)/init.d; \
	fi;

	install -c -D -m 0755 perfsonar-collector.init $(sysconfdir)/init.d/perfsonar-collector
	awk "{gsub(/^BINDIR=.*/,\"BINDIR=$(INSTALLBIN)\"); gsub(/^PREFIX=.*/,\"PREFIX=$(PREFIX)\"); gsub(/^CONFDIR=.*/,\"CONFDIR=$(sysconfdir)\"); print}" $(sysconfdir)/init.d/perfsonar-collector > $(sysconfdir)/init.d/perfsonar-collector.new
	mv -f $(sysconfdir)/init.d/perfsonar-collector.new $(sysconfdir)/init.d/perfsonar-collector
	chmod +x $(sysconfdir)/init.d/perfsonar-collector

	perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/perfsonar-collector
	awk "{gsub(/XXX_LIBDIR_XXX/,\"$(INSTALLSITELIB)\"); gsub(/XXX_CONFDIR_XXX/,\"$(sysconfdir)/perfsonar\"); print}" $(INSTALLBIN)/perfsonar-collector > $(INSTALLBIN)/perfsonar-collector.new
	mv -f $(INSTALLBIN)/perfsonar-collector.new $(INSTALLBIN)/perfsonar-collector
	chmod +x $(INSTALLBIN)/perfsonar-collector

	perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/psConfigureCollectors
	awk "{gsub(/XXX_DEFAULT_XXX/,\"$(sysconfdir)/perfsonar/collector.conf\"); print}" $(INSTALLBIN)/psConfigureCollectors > $(INSTALLBIN)/psConfigureCollectors.new
	mv -f $(INSTALLBIN)/psConfigureCollectors.new $(INSTALLBIN)/psConfigureCollectors
	chmod +x $(INSTALLBIN)/psConfigureCollectors
';}
