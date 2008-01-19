use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::MA::SNMP',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/MA/SNMP.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"perfSONAR_PS::Common" => 0.03,
	"perfSONAR_PS::Transport" => 0.03,
	"perfSONAR_PS::Messages" => 0.03,
	"perfSONAR_PS::DB::SQL" => 0.03,
	"perfSONAR_PS::DB::File" => 0.03,
	"perfSONAR_PS::DB::RRD" => 0.03,
	"perfSONAR_PS::Services::Base" => 0.03,
	"perfSONAR_PS::Services::MA::General" => 0.03,
	"perfSONAR_PS::XML::Document_string" => 0.03,
	"perfSONAR_PS::Error_compat" => 0.03,
	"Log::Log4perl" => 1.00,
	"Module::Load" => 0.10,
    }
);
