use ExtUtils::MakeMaker;

my @exe_files = ( "perfsonar", "psConfigureDaemon" );

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::Daemon',
    'VERSION_FROM' => 'perfsonar',
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
	"perfSONAR_PS::Messages" => "v0.01",
	"perfSONAR_PS::Error_compat" => "v0.01",
	"perfSONAR_PS::XML::Document_string" => "v0.01",
	"HTTP::Daemon" => 1.35,
	"Params::Validate" => 0.70,
	"XML::LibXML" => 1.60,
	"XML::XPath" => 1.13,
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

	if [ ! -f $(sysconfdir)/perfsonar/daemon.conf ]; then \
	    touch $(sysconfdir)/perfsonar/daemon.conf; \
	fi;

	if [ ! -f $(sysconfdir)/perfsonar/logger.conf ]; then \
	    install -c -D -m 0644 logger.conf $(sysconfdir)/perfsonar/logger.conf; \
	else \
	    echo "Old configuration file exists at $(sysconfdir)/perfsonar/logger.conf: not overwritten."; \
	fi;

	if [ -d $(sysconfdir)/init.d ]; then \
	    mkdir -p $(sysconfdir)/init.d; \
	fi;

	install -c -D -m 0755 perfsonar-daemon.init $(sysconfdir)/init.d/perfsonar-daemon
	awk "{gsub(/^BINDIR=.*/,\"BINDIR=$(INSTALLBIN)\"); gsub(/^PREFIX=.*/,\"PREFIX=$(PREFIX)\"); gsub(/^CONFDIR=.*/,\"CONFDIR=$(sysconfdir)\"); print}" $(sysconfdir)/init.d/perfsonar-daemon > $(sysconfdir)/init.d/perfsonar-daemon.new
	mv -f $(sysconfdir)/init.d/perfsonar-daemon.new $(sysconfdir)/init.d/perfsonar-daemon
	chmod +x $(sysconfdir)/init.d/perfsonar-daemon

	perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/perfsonar
	awk "{gsub(/XXX_LIBDIR_XXX/,\"$(INSTALLSITELIB)\"); gsub(/XXX_CONFDIR_XXX/,\"$(sysconfdir)/perfsonar\"); print}" $(INSTALLBIN)/perfsonar > $(INSTALLBIN)/perfsonar.new
	mv -f $(INSTALLBIN)/perfsonar.new $(INSTALLBIN)/perfsonar
	chmod +x ($INSTALLBIN)/perfsonar

	perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/psConfigureDaemon
	awk "{gsub(/XXX_DEFAULT_XXX/,\"$(sysconfdir)/perfsonar/daemon.conf\"); print}" $(INSTALLBIN)/psConfigureDaemon > $(INSTALLBIN)/psConfigureDaemon.new
	mv -f $(INSTALLBIN)/psConfigureDaemon.new $(INSTALLBIN)/psConfigureDaemon
	chmod +x $(INSTALLBIN)/psConfigureDaemon
';}
