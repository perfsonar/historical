use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Services::MA::SNMP',
    'VERSION_FROM' => 'lib/perfSONAR_PS/Services/MA/SNMP.pm',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
        "version" => 0.50,
	"perfSONAR_PS::Common" => "v0.01",
	"perfSONAR_PS::Transport" => "v0.01",
	"perfSONAR_PS::Messages" => "v0.01",
	"perfSONAR_PS::DB::SQL" => "v0.01",
	"perfSONAR_PS::DB::File" => "v0.01",
	"perfSONAR_PS::DB::RRD" => "v0.01",
	"perfSONAR_PS::Services::MA::General" => "v0.01",
	"perfSONAR_PS::XML::Document_string" => "v0.01",
	"perfSONAR_PS::Error_compat" => "v0.01",
	"Log::Log4perl" => 1.00,
	"Module::Load" => 0.10,
    }
);
