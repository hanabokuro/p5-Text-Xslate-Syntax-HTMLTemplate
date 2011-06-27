use strict;
use warnings;

use inc::Module::Install;

all_from 'lib/Text/Xslate/Syntax/HTP.pm';

requires 'HTML::Template::Parser' => 0;
requires 'Text::Xslate' => 0;

tests_recursive;

WriteAll;


