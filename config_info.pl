
require './virtual-server-lib.pl';

sub show_theme
{
local ($value, $desc, $type, $func, $name) = @_;
&foreign_require("webmin", "webmin-lib.pl");
return &ui_select($name, $value,
		  [ [ "*", $text{'config_deftheme'} ],
		    [ "", $text{'config_oldtheme'} ],
		    map { [ $_->{'dir'}, $_->{'desc'} ] }
			  &webmin::list_themes() ]);
}

sub parse_theme
{
local ($value, $desc, $type, $func, $name) = @_;
return $in{$name};
}

sub show_modules
{
local ($value, $desc, $type, $func, $name) = @_;
return &ui_textbox($name, $value, 40)." ".
       &modules_chooser_button($name, 1);
}

sub parse_modules
{
local ($value, $desc, $type, $func, $name) = @_;
return $in{$name};
}

sub show_shells
{
local ($value, $desc, $type, $func, $name) = @_;
local @shells = ("/bin/sh", "/bin/csh");
local $_;
open(SHELLS, "/etc/shells");
while(<SHELLS>) {
	s/\r|\n//g;
	s/#.*$//;
	push(@shells, $_) if (/\S/);
	}
close(SHELLS);
push(@shells, $value) if ($value);
@shells = &unique(@shells);
return &ui_select($name, $value,
		  [ map { [ $_, $shellname{$_} || $_ ] } @shells ]);
}

sub parse_shells
{
local ($value, $desc, $type, $func, $name) = @_;
return $in{$name};
}

1;

