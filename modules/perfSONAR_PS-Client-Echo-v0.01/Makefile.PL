use ExtUtils::MakeMaker;

my @exe_files = ( "psping" );

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Client::Echo',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Client/Echo.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
	"perfSONAR_PS::Common" => 0.04,
	"perfSONAR_PS::Transport" => 0.04,
	"perfSONAR_PS::Messages" => 0.04,
	"perfSONAR_PS::XML::Document_string" => 0.04,
	"Log::Log4perl" => 1.00,
	"Test::More" => 0,
	"Time::HiRes" => 1.85,
    },

    EXE_FILES => \@exe_files,
);

package MY;

sub postamble {'

install ::

	perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/psping
	awk "{gsub(/XXX_LIBDIR_XXX/,\"$(INSTALLSITELIB)\"); print}" $(INSTALLBIN)/psping > $(INSTALLBIN)/psping.new
	mv -f $(INSTALLBIN)/psping.new $(INSTALLBIN)/psping
	chmod +x ($INSTALLBIN)/psping
';}
