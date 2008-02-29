use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::MA::SNMP',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/MA/SNMP.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
	"base" => 0,
	"Digest::MD5" => 0,
	"English" => 0,
	"fields" => 0,
	"Log::Log4perl" => 1.00,
	"Module::Load" => 0.10,
	"Params::Validate" => 0.64,
	"perfSONAR_PS::Client::LS::Remote" => 0.08,
	"perfSONAR_PS::Common" => 0.08,
	"perfSONAR_PS::DB::File" => 0.08,
	"perfSONAR_PS::DB::RRD" => 0.08,
	"perfSONAR_PS::DB::SQL" => 0.08,
	"perfSONAR_PS::Error_compat" => 0.08,
	"perfSONAR_PS::Messages" => 0.08,
	"perfSONAR_PS::Services::Base" => 0.08,
	"perfSONAR_PS::Services::MA::General" => 0.08,
        "strict" => 0,
        "warnings" => 0,
    }
);
