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
if (!$@) {
	return XMLout($data, 'KeyAttr' => 1);
	}
}

sub create_json_format
{
my ($data) = @_;
}

1;

