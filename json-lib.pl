# Functions for converting API output into JSON or XML

# convert_remote_format(&output, exit-status, command, format)
# Converts output from some API command to JSON or XML format
sub convert_remote_format
{
my ($out, $ex, $cmd, $in, $format) = @_;

# Parse into a data structure
my $data = { 'command' => $cmd,
	     'status' => $ex ? 'failure' : 'success',
	   };
if ($ex) {
	# Failed, get error line
	my @lines = split(/\r?\n/, $out);
	my ($err) = grep { /\S/ } @lines;
	$data->{'error'} = $err;
	$data->{'full_error'} = $out;
	}
elsif ($cmd =~ /^list\-/ && defined($in{'multiline'})) {
	# Parse multiline output into data structure
	# XXX 
	}
else {
	# Just attach full output
	$data->{'output'} = $out;
	}

# Call formatting function
my $ffunc = "create_".$format."_format";
return &$ffunc($data);
}

1;

