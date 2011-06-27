#!perl -w

use strict;
use warnings;

use Test::More;

use t::lib::Util;

my $tx = Text::Xslate->new(syntax => 'Metakolon');

compare_ast('[% $foo * 2%]', '<TMPL_VAR EXPR="foo * 2">', { foo => 5});

compare_ast('[% 1 %]', '<TMPL_VAR EXPR=1>', {});
compare_ast('[% "abc" %]', q{<TMPL_VAR EXPR='"abc"'>}, {});
compare_ast('[% 1+2*3 %]', '<TMPL_VAR EXPR=1+2*3>', {});
compare_ast('[% $foo * 2%]', '<TMPL_VAR EXPR="foo * 2">', { foo => 5});

done_testing;


