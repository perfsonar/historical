use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Client::Topology::MA',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Client/Topology/MA.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "version" => 0.50,
	"perfSONAR_PS::Common" => "v0.01",
	"perfSONAR_PS::Transport" => "v0.01",
	"Log::Log4perl" => 1.00,
    }
);
