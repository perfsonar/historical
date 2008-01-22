use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::MA::Status',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/MA/Status.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"Log::Log4perl" => 1.00,
	"perfSONAR_PS::Common" => 0.06,
	"perfSONAR_PS::Messages" => 0.06,
	"perfSONAR_PS::Client::LS::Remote" => 0.06,
	"perfSONAR_PS::Client::Status::SQL" => 0.06,
        "perfSONAR_PS::Services::Base" => 0.06,
    }
);
