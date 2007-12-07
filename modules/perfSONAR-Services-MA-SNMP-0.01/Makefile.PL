use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::MA::SNMP',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/MA/SNMP.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
	"perfSONAR_PS::Common" => 0.01,
	"perfSONAR_PS::Transport" => 0.01,
	"perfSONAR_PS::Messages" => 0.01,
	"perfSONAR_PS::DB::SQL" => 0.01,
	"perfSONAR_PS::DB::File" => 0.01,
	"perfSONAR_PS::DB::RRD" => 0.01,
	"perfSONAR_PS::Services::MA::General" => 0.01,
	"perfSONAR_PS::XML::Document_string" => 0.01,
	"Log::Log4perl" => 1.00,
	"Module::Load" => 0.10,
    }
);
