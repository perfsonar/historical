use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Client::Topology::MA',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Client/Topology/MA.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
	"perfSONAR_PS::Common" => 0.03,
	"perfSONAR_PS::Transport" => 0.03,
	"Log::Log4perl" => 1.00,
    }
);
