#!perl -w

use strict;
use warnings;

use Test::More;

use t::lib::Util;

my $tx = Text::Xslate->new(syntax => 'Metakolon');

compare_ast(qq{plain text}, qq{plain text}, {});
compare_ast(qq{123}, qq{123}, {});

done_testing;
