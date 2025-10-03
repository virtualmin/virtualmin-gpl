# Include the procmail log in the System Logs module

require 'virtual-server-lib.pl';

# syslog_getlogs()
# Returns a list of structures containing extra log files known to this module
sub syslog_getlogs
{
my @rv;
push(@rv, { 'file' => $procmail_log_file,
	    'desc' => $text{'syslog_procmail'},
	    'active' => 1 });
return @rv;
}
