use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Client::Status::MA',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Client/Status/MA.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
	"perfSONAR_PS::Common" => 0.02,
	"perfSONAR_PS::Status::Link" => 0.02,
	"perfSONAR_PS::Status::Common" => 0.02,
	"perfSONAR_PS::Transport" => 0.02,
	"Log::Log4perl" => 1.00,
    }
);
