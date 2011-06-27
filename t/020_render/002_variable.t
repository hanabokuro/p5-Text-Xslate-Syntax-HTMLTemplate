#!perl -w

use strict;
use warnings;

use Test::More;

use t::lib::Util;

my $tx = Text::Xslate->new(syntax => 'Metakolon');

compare_render(q{[% $foo %]}, q{<TMPL_VAR NAME=foo>}, { foo => "this is foo" });

done_testing;
