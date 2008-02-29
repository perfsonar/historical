use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::LS',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/LS/LS.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "base" => 0,
        "Digest::MD5" => 0,
        "Exporter" => 0,
        "fields" => 0,
	"Log::Log4perl" => 1.00,
	"Params::Validate" => 0.64,
	"perfSONAR_PS::Common" => 0.08,
	"perfSONAR_PS::DB::XMLDB" => 0.08,
	"perfSONAR_PS::Error_compat" => 0.08,
	"perfSONAR_PS::Messages" => 0.08,
	"perfSONAR_PS::Services::Base" => 0.08,
	"perfSONAR_PS::Services::MA::General" => 0.08,
        "strict" => 0,
	"Time::HiRes" => 1.85,
        "warnings" => 0,
    }
);
