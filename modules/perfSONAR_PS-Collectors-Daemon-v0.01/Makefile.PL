use ExtUtils::MakeMaker; 
my @exe_files = ( "perfsonar-collector.pl" );

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Collectors::Daemon',
    'VERSION_FROM' => 'perfsonar-collector.pl',
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
	"Time::HiRes" => 1.9707,
	"Config::General" => 2.30,
	"perfSONAR_PS::Common" => "v0.01",
    },

    EXE_FILES => \@exe_files,
);

package MY;

sub postamble {'

sysconfdir	= $(prefix)/etc

install ::

	if [ ! -d $(sysconfdir)/perfsonar ]; then \
	    mkdir $(sysconfdir)/perfsonar; \
	fi;

	if [ ! -f $(sysconfdir)/perfsonar/collector.conf ]; then \
	    touch $(sysconfdir)/perfsonar/collector.conf; \
	fi;

	if [ ! -f $(sysconfdir)/perfsonar/logger.conf ]; then \
	    install -c -D -m 0644 logger.conf $(sysconfdir)/perfsonar/logger.conf; \
	else \
	    echo "Old configuration file exists at $(sysconfdir)/perfsonar/logger.conf: not overwritten."; \
	fi;
';}
