use ExtUtils::MakeMaker;

my @exe_files = ( "psLoadTopology" );

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::MA::Topology',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/MA/Topology.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"Log::Log4perl" => 1.00,
	"File::Basename" => 0,
	"Getopt::Long" => 0,
	"XML::LibXML" => 1.60,
	"perfSONAR_PS::Common" => 0.06,
	"perfSONAR_PS::Messages" => 0.06,
	"perfSONAR_PS::Services::Base" => 0.06,
	"perfSONAR_PS::Topology::Common" => 0.06,
	"perfSONAR_PS::Topology::ID" => 0.06,
	"perfSONAR_PS::Client::Topology::MA" => 0.06,
	"perfSONAR_PS::Client::Topology::XMLDB" => 0.06,
	"perfSONAR_PS::Client::LS::Remote" => 0.06,
    },

    EXE_FILES => \@exe_files,
);

package MY;

sub postamble {'

install ::

	perl -i -p -e "s/was_installed = 0/was_installed = 1/" $(INSTALLBIN)/psLoadTopology
	awk "{gsub(/XXX_LIBDIR_XXX/,\"$(INSTALLSITELIB)\"); print}" $(INSTALLBIN)/psLoadTopology > $(INSTALLBIN)/psLoadTopology.new
	mv -f $(INSTALLBIN)/psLoadTopology.new $(INSTALLBIN)/psLoadTopology
	chmod +x ($INSTALLBIN)/psLoadTopology
';}
