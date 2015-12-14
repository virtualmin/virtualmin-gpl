
require 'virtual-server-lib.pl';

sub show_theme
{
local ($value, $desc, $type, $func, $name) = @_;
&foreign_require("webmin");
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
       &modules_chooser_button($name, 1,
		$current_theme eq "virtual-server-theme" ? 1 : 0);
}

sub parse_modules
{
local ($value, $desc, $type, $func, $name) = @_;
return $in{$name};
}

1;

