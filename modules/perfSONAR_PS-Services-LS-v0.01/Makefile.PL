use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::LS',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/LS/LS.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
        "Exporter" => 0,
	"Log::Log4perl" => 1.00,
	"Time::HiRes" => 1.85,
	"perfSONAR_PS::Common" => 0.04,
	"perfSONAR_PS::Messages" => 0.04,
	"perfSONAR_PS::Services::Base" => 0.04,
	"perfSONAR_PS::Services::MA::General" => 0.04,
	"perfSONAR_PS::DB::XMLDB" => 0.04,
    }
);
