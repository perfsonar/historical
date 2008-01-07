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

	perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/perfsonar
	awk "{gsub(/XXX_LIBDIR_XXX/,\"$(INSTALLSITELIB)\"); print}" $(INSTALLBIN)/perfsonar > $(INSTALLBIN)/perfsonar.new
	mv -f $(INSTALLBIN)/perfsonar.new $(INSTALLBIN)/perfsonar
	awk "{gsub(/XXX_CONFDIR_XXX/,\"$(sysconfdir)\"); print}" $(INSTALLBIN)/perfsonar > $(INSTALLBIN)/perfsonar.new
	mv -f $(INSTALLBIN)/perfsonar.new $(INSTALLBIN)/perfsonar
	chmod +x ($INSTALLBIN)/perfsonar
';}
