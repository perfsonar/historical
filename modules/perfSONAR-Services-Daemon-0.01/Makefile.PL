use ExtUtils::MakeMaker;

my @exe_files = ( "perfsonar.pl" );

WriteMakefile(
    'NAME' => 'perfSONAR_PS::Daemon',
    'VERSION_FROM' => 'perfsonar.pl',
    'AUTHOR' => 'Aaron Brown <aaron@internet2.edu>',
    'PREREQ_PM' => {
        "strict" => 0,
        "warnings" => 0,
	"Log::Log4perl" => 1.00,
	"Getopt::Long" => 0,
	"POSIX" => 0,
	"Fcntl" => 0,
	"Cwd" => 0,
	"Cwd" => 0,
	"File::Basename" => 0,
	"Module::Load" => 0.10,
	"Time::HiRes" => 1.9707,
	"Config::General" => 2.30,
	"perfSONAR_PS::Common" => 0.01,
	"perfSONAR_PS::Messages" => 0.01,
	"perfSONAR_PS::Transport" => 0.01,
	"perfSONAR_PS::XML::Document_string" => 0.01,
    },

    EXE_FILES => \@exe_files,
);
