use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Client::LS::Remote',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Client/LS/Remote.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"Log::Log4perl" => 1.00,
	"perfSONAR_PS::Common" => 0.02,
	"perfSONAR_PS::Transport" => 0.02,
	"perfSONAR_PS::Messages" => 0.02,
	"perfSONAR_PS::Client::Echo" => 0.02,
    }
);
