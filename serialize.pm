package serialize;
use strict;
use vars qw(@ISA @EXPORT $VERSION);
@ISA     = qw(Exporter);
@EXPORT  = qw(serialize unserialize session_encode);
$VERSION = 0.92;

our $SERIALIZE_DBG = 0;

=pod
Perl implementation of PHP's native serialize(), unserialize(),
and session_encode() functions.

Planned for next version is session_decode()

@author Scott Hurring (scott at hurring dot com)
http://hurring.com/
Please be nice and send bugfixes and code improvements to me.

@version v0.92
@author Scott Hurring; scott at hurring dot com
@copyright Copyright (c) 2006 Scott Hurring
@license http://opensource.org/licenses/gpl-license.php GNU Public License

Most recent version can be found at:
http://hurring.com/code/perl/serialize/

=====================================================================

Unlike modules that make use of language-specific binary formats, the
output of serialize() is an ASCII string, meaning you can easily
manipulate it as you would any other string, i.e. sticking it
into a URL, a database, a file, etc...

Taken along with my python serialize implementation, this code will
enable you to transfer data between PHP, Python, and Perl using PHP's
data serialization format.

To serialize:
	# serialize an array into a string
	my $string = serialize(\@data);
	# or... serialize a hash into a string
	my $string = serialize(\%data);
	
Session encode:
	my $string = session_encode(\%data);

To unserialize:
	# unserialize some string into python data
	$hash_ref = unserialize($string)

Session decode:
	$hash_ref = session_decode($string);
	
PHP Serialization Format:
	NULL		N;
	Boolean		b:1;			b:$data;
	Integer		i:123;			i:$data;
	Double		d:1.23;			d:$data;
	String		s:5:"Hello"		s:$length:"$data";
	Array		a:1:{i:1;i:2}		a:$key_count:{$key;$value}
						$value can be any data type

Supported Perl Types:
	Serializing:
	NULL (\0), int, double, string, hash, array

	Unserializing:
	NULL (\0), int, double, string, hash

*array is unserialized as a hash, becuase PHP only has one array
type "array()", which is analagous to Perl hash's.  When you try to
serialize a perl array, it's automagically converted into a hash
with keys numbered from 0 up.

Type Translation Table:
	(Perl)	(serialize)	(PHP)	    (unserialize)  (Perl)
	NULL 	=>		NULL 			=> NULL
	int 	=>		int 			=> int
	double 	=>		double			=> double
	string 	=>		string			=> string
	hash 	=>		array			=> hash
	array 	=>		array			=> hash

====================================================================

Warning:

This code comes with absolutely NO warranty... it is a quick hack
that i sometimes work on in my spare time.  This code may or may
not melt-down your computer and give you nonsensical output.

Please, do not use this code in a production enviornment until
you've thoroughly tested it.

=====================================================================
=cut

=pod
Serialize a session hashref.
http://php.net/session_encode
=end
sub session_encode {
	my ($value) = @_;
	my $s = "";
	
	serialize_dbg("> session_encode: $value");
	
	if (ref($value) =~ /hash/i) {
		foreach my $k ( keys(%$value) ) {
			$s .= "$k|". serialize($$value{$k});
		}
	}

	elsif (ref($value) =~ /array/i) {
		serialize_dbg("array");
		for (my $k=0; $k < @$value; $k++ ) {
			# $k | $$value[$k]
			$s .= "$k|". serialize($$value[$k]);
		}
	}
	
	return $s;

}

=pod
Serialize a hash or array (or single value) PHP-style
http://php.net/serialize

* Only serializes data (scalar,hashref,arrayref)
* No references to code/objects are handled
* die() is called when unrecognized data is encountered

Usage:
$serialized_string = serialize(\%hash);
$serialized_string = serialize(\@array);
$serialized_string = serialize($value);
=cut

sub serialize {
	my ($value) = @_;
	return serialize_value($value);
}

=pod
Serialize a key.  Simpler rules.
=cut
sub serialize_key {
	my ($value) = @_;
	my $s;
	
	# Serialize this as an integer
	if ($value =~ /^\d+$/) {
		# Kevin Haidl - PHP can only handle (((2**32)/2) - 1) 
		# before value must be serialized as a double
		if (abs($value) > ((2**32)/2-1)) {
			$s = "d:$value;";
		}
		else {
			$s = "i:$value;";
		}
	}
	
	# Serialize everything else as a string
	else {
		my $vlen = length($value);
		$s = "s:$vlen:\"$value\";";
	}
	
	return $s;
}

=pod
Serialize a value.  Recurse on ref to hash or array.
=cut
sub serialize_value {
	my ($value) = @_;
	my $s;
	
	$value = defined($value) ? $value : '';
	
	# This is a hash ref
	if ( ref($value) =~ /hash/i) {
		#The data in the hashref
		my $num = keys(%{$value});
		$s .= "a:$num:{";
		foreach my $k ( keys(%$value) ) {
			$s .= serialize_key( $k );
			$s .= serialize_value( $$value{$k} );
		}
		$s .= "}";
	}

	# This is an array ref
	elsif ( ref($value) =~ /array/i) {
		#The data in the arrayref
		my $num = @{$value};
		$s .= "a:$num:{";
		for (my $k=0; $k < @$value; $k++ ) {
			$s .= serialize_key( $k );
			$s .= serialize_value( $$value[$k] );
		}
		$s .= "}";
	}

	# This is a double
	# Thanks to Konrad Stepien <konrad@interdata.net.pl>
	# for pointing out correct handling of negative numbers.
	elsif ($value =~ /^\-?(\d+)\.(\d+)$/) {
		$s = "d:$value;";
	}

	# This is an integer
	elsif ($value =~ /^\-?\d+$/) {
		# Kevin Haidl - PHP can only handle (((2**32)/2) - 1) 
		# before value must be serialized as a double
		if (abs($value) > ((2**32)/2-1)) {
			$s = "d:$value;";
		}
		else {
			$s = "i:$value;";
		}
	}
	
	# This is a NULL value
	#
	# Only values of "\0" will be serialized as NULL
	# Empty strings are not NULL, they are simply empty strings.
	# @note Differs from v0.7 where string "NULL" was serialized as "N;"
	elsif ($value eq "\0")  {
		$s = "N;";
	}
	
	# Anything else is interpreted as a string
	else {
		my $vlen = length($value);
		$s = "s:$vlen:\"$value\";";
	}
	
	return $s;
}





## ##################################################################
## ##################################################################

sub session_decode {
	my ($string) = @_;
	
	# Not implemented (yet)
	
	die("Not implemented.");
}


=pod
Unserializes a serialized string into its perl equivalent
http://php.net/unserialize

Returns a hashref (or single value) of the serialized text string

$hashref = unserialize($string);
$value = unserialize('s:5:"Hello";');
=cut
sub unserialize {
	my ($string) = @_;
	return unserialize_value($string);
}

sub unserialize_value {
	my ($value) = @_;
	
	# Thanks to Ron Grabowski [ronnie (at) catlover.com] for suggesting
	# the need for single-value unserialize code
	
	# This is an array
	if ($value =~ /^a:(\d+):\{(.*)\}$/) {
		serialize_dbg("Unserializing array");
		
		my @chars = split(//, $2);
		
		# Add one extra char at the end so that the loop has one extra
		# cycle to hit the 'set' state and set the final value
		# Otherwise it'll terminate before setting the last value
		push(@chars, ';');
		
		return unserialize_sub({}, $1*2, \@chars);
	}
	
	# This is a single string
	elsif ($value =~ /^s:(\d+):(.*);$/) {
		serialize_dbg("Unserializing single string ($value)");
		#$string =~ /^s:(\d+):/;
		return $2;
		#return substr($string, length($1) + 4, $1);
	}
		
	# This is a single integer or double value
	elsif ($value =~ /^(i|d):(\-?\d+\.?\d+?);$/) {
		serialize_dbg("Unserializing integer or double ($value)");
		return $2
		#substr($string, 2) + 0;
	}
	
	# This is a NULL value
	# Thanks to Julian Jares [jjares at uolsinectis.com.ar]
	elsif ($value == /^N;$/i) {
		serialize_dbg("Unserializing NULL value ($value)");
		return "\0";
	}
	
	# This is a boolean
	# Thanks to Charles M Hall (cmhall at hawaii dot edu)
	elsif ($value =~/^b:(\d+);$/) {
		serialize_dbg("Unserializing boolean value ($value)");
		return $1;
	}
	
	# Invalid data
	else {
		serialize_dbg("Unserializing BAD DATA!\n($value)");
		die("Trying to unserialize bad data!");
		return '';
	}

}

=pod
Resursive unserializing routine for a serialized hash or array.

This is implemented as a finite state machine.

Traverses the serialized text representation and builds a hash

Due to the way that an array is serialized in PHP, it's impractical
to return proper array/hash types in perl.  PHP makes no distinction
between an array and a hash (arrays are just hashes with numeric
keys and vice versa) -- so in this routine, everything is unserialized
as a hash.

@param
	$hashref	the hashref currently being built
	$keys		how many keys are in this hash ref
	$chars		arrayref of characters to process.

@return		unserialized hashref
  


This iterates through each character one-by-one
it's a state machine, it keeps the current state in "$mode"
switch $mode:
	case 'string'
		1) look for a digit, which is the length of the
		serialized string that we're about to see, save
		that as $strlen.
		2) after the next ':', $mode='readstring'
	case 'readstring'
		capture $strlen characters into $temp
		then, mode='set'
	case 'set'
		1) set $value=$temp and assign the current hash key=$value
		2) $mode='normal'
	case 'integer'
		1) put all digits into $temp, skip ":"
		2) at the first ";", $mode='set'
	case 'double'
		1) same as integer, only allows "." in input
		2) at the first ";", $mode='set'
	case 'null'
		1) null value, set $temp="\0"
		2) $mode='set'

=cut
sub unserialize_sub {
	my ($hashref, $keys, $chars) = @_;
	my ($temp, $keyname, $skip, $strlen);
	my $mode = 'normal';		#default mode
	
	serialize_dbg("> unserialize: $hashref, $keys, $chars");

	# Loop through the data char-by-char, eating them as we go...
	while ( defined(my $c = shift @{$chars}) )
	{
		serialize_dbg("\twhile [$mode] = $c (skip=$skip)");
	
		# Processing a serialized string
		# Format: s:length:"data"
		if ($mode eq 'string') {
			$skip = 1;	#how many chars should 'readstring' skip?
					#skip initial quote " at the beginning.
	
			#find out how many chars need to be read
			if ($c =~ /\d+/) {
				#get the length of string
				$strlen = $strlen . $c;
			}
	
			#if we already have a length, and see ':', we know that
			#the actual string is coming next (see format above)
	
			if (($strlen =~ /\d+/) && ($c eq ':')) {
				serialize_dbg("[string] length = $strlen");
				$mode = 'readstring';
			}
	
		}
		# Read $strlen number of characters into $temp
		elsif ($mode eq 'readstring') {
			next			if ($skip && ($skip-- > 0));
			$mode = 'set', next	if (!$strlen--);
	
			$temp .= $c;
	
		}
	
		# Process a serialized integer
		# Format: i:data
		elsif ($mode eq 'integer') {
			next 			if ($c eq ':');
			$mode = 'set', next	if ($c eq ';');
	
			# Grab the digits
			# Thanks to Konrad Stepien <konrad@interdata.net.pl>
			# for pointing out correct handling of negative numbers.
			if ($c =~ /\-|\d+/) {
				if ($c eq '-') {
					$temp .= $c unless $temp;
				} else {
					$temp .= $c;
				}
			}
		}
	
		# Process a serialized double
		# Format: d:data
		elsif ($mode eq 'double') {
			next 			if ($c eq ':');
			$mode = 'set', next	if ($c eq ';');
	
			# Grab the digits
			# Thanks to Konrad Stepien <konrad@interdata.net.pl>
			# for pointing out correct handling of negative numbers.
			if ($c =~ /\-|\d+|\./) {
				if ($c eq '-') {
					$temp .= $c unless $temp;
				} else {
					$temp .= $c;
				}
			}
		}
	
		# Process a serialized NULL value
		# Format: N
		# Thanks to Julian Jares [jjares at uolsinectis.com.ar]
		elsif ($mode eq 'null') {
	
			# Set $temp to something perl will recognize as null "\0"
			# Don't unserialize as an empty string, becuase PHP 
			# serializes empty srings as empty strings, not null.
			$temp = "\0";
	
			$mode = 'set', next;
		}
	
		# Process an array
		# Format: a:num_of_keys:{...}
		elsif ($mode eq 'array') {
	
			# Start of array definition, start processing it
			if ($c eq '{') {
	
				$temp = unserialize_sub( $$hashref{$keyname}, ($temp*2), $chars );

				# If temp is an empty array, change to {}
				# Thanks to Charles M Hall (cmhall at hawaii dot edu)
				if(!defined($temp) || $temp eq "") {
					$temp = {};
				}
				
				$mode = 'set', next;
			}
	
			# Reading in the number of keys in this array
			elsif ($c =~ /\d+/) {
				$temp = $temp . $c;
				serialize_dbg("array_length = $temp ($c)");
			}
		}
	
		# Do something with the $temp variable we read in.
		# It's either holding data for a key or a value.
		elsif ($mode eq 'set') {
	
			# The keyname has already been set, so that means
			# $temp holds the value
			if (defined($keyname)) {
				serialize_dbg("set [$keyname]=$temp");
	
				$$hashref{$keyname} = $temp;	
				
				# blank out keyname
				undef $keyname;
			}
	
			# $temp holds a keyname
			else {
				serialize_dbg("set KEY=$temp");
				$keyname = $temp;
			}
	
			undef $temp;
			$mode = 'normal';	# dont eat any chars
		}
	
		# Figure out what the upcoming value is and set the state for it.
		if ($mode eq 'normal') {
			# Blank out temp vars used by previous state.
			$strlen = $temp = '';
	
			if (!$keys) {
				serialize_dbg("return normally, finished processing keys");
				return $hashref;
			}
	
			# Upcoming information is integer
			if ($c eq 'i') {
				$mode = 'integer';
				$keys--;
			}
			# Upcoming information is a bool,
			# process the same as an integer
			if ($c eq 'b') {
				$mode = 'integer';
				$keys--;
			}
			# Upcoming information is a double
			if ($c eq 'd') {
				$mode = 'double';
				$keys--;
			}
			# Upcoming information is string
			if ($c eq 's') {
				$mode = 'string';
				$keys--;
			}
			# Upcoming information is array/hash
			if ($c eq 'a') {
				$mode = 'array';
				$keys--;
			}
			# Upcoming information is a null value
			if ($c eq 'N') {
				$mode = 'null';
				$keys--;
			}
		}

	} #while there are chars to process


	# You should never hit this point.
	# If you do hit this, it means that the code was expecting more 
	# characters than it was given.
	# Perhaps your data was unexpectedly truncated or mutilated?

	serialize_dbg("> unserialize_sub ran out of chars when it was expecting more.");
	die("unserialize_sub() ran out of characters when it was expecting more.");
	
	return 0;
}


## ##################################################################
## ##################################################################
## Some helper functions

# Output debug messages
sub serialize_dbg {
	my ($string) = @_;
	if ($SERIALIZE_DBG) {
		print $string ."\n";
	}
}

# Bootleg 'pretty print'
sub dump_hash {
	my ($hashref, $offset) = @_;
	#serialize_dbg("> dump_hash");
	
	foreach my $k (keys %{$hashref}) {
		print join ("",@$offset) . "$k = $$hashref{$k}\n";
		if (ref($$hashref{$k}) =~ /hash/i) {
			push (@$offset, "\t");
			&dump_hash($$hashref{$k}, $offset);
			pop @$offset;
		}
	}
	return 1;
}

1;
