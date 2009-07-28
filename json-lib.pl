# Functions for converting API output into JSON or XML

# check_remote_format(format)
# Returns an error message if some format is not supported, undef if OK
sub check_remote_format
{
my ($format) = @_;
if ($format eq "xml") {
	eval "use XML::Simple";
	return "Missing XML::Simple Perl module" if ($@);
	}
elsif ($format eq "perl") {
	eval "use Data::Dumper";
	return "Missing Data::Dumper Perl module" if ($@);
	}
elsif ($format eq "json") {
	eval "use JSON::PP";
	return "Missing JSON::PP Perl module" if ($@);
	}
else {
	return "Unknown format $format";
	}
return undef;
}

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
	my @lines = split(/\r?\n/, $out);
	my $obj;
	my @data;
	foreach my $l (@lines) {
		if ($l =~ /^(\S.*)$/) {
			# Object name
			$obj = { };
			push(@data, { 'name' => $1,
				      'values' => $obj });
			}
		elsif ($l =~ /^\s+(\S[^:]+):\s*(.*)$/) {
			# Key and value within the object
			my ($k, $v) = ($1, $2);
			$k = lc($k);
			$k =~ s/\s/_/g;
			$obj->{$k} ||= [ ];
			push(@{$obj->{$k}}, $v);
			}
		}
	$data->{'data'} = \@data;
	}
elsif ($cmd eq "list-bandwidth" || $cmd eq "list-owner-bandwidth") {
	# Parse Cloudmin bandwidth table
	my @lines = split(/\r?\n/, $out);
        my $obj;
        my @data;
	foreach my $l (@lines) {
		if ($l =~ /^(\S.*)$/) {
			# Start of a system or owner
			$obj = [ ];
			push(@data, { 'name' => $1,
                                      'values' => $obj });
			}
		elsif ($l =~ /^\s+(\S+)\s+(\d+:\d+)\s+([0-9\.]+\s+\S+)\s+([0-9\.]+\s+\S+)\s+(\d+)\s+(\d+)\s*$/ ||
		       $l =~ /^\s+(\S+)\s+(\d+:\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$/) {
			# Value line
			push(@$obj, { 'date' => $1,
				      'time' => $2,
				      'in' => $3,
				      'out' => $4,
				      'inp' => $5,
				      'outp' => $6 });
			}
		}
	$data->{'data'} = \@data;
	}
else {
	# Just attach full output
	$data->{'output'} = $out;
	}

# Call formatting function
my $ffunc = "create_".$format."_format";
return &$ffunc($data);
}

# create_xml_format(&hash)
# Convert a hash into XML
sub create_xml_format
{
my ($data) = @_;
eval "use XML::Simple";
return XMLout($data, RootName => 'api');
}

# create_json_format(&hash)
# Convert a hash into JSON
sub create_json_format
{
my ($data) = @_;
eval "use JSON::PP";
my $coder = JSON::PP->new->pretty;
return $coder->encode($data)."\n";
}

# create_perl_format(&hash)
# Convert a hash into Perl variable format
sub create_perl_format
{
my ($data) = @_;
eval "use Data::Dumper";
return Dumper($data);
}

1;

