#!perl -w

use strict;
use warnings;

use Test::More;

use t::lib::Util;

my $tx = Text::Xslate->new(syntax => 'Metakolon');

compare_render(qq{plain text}, qq{plain text}, {});
compare_render(qq{plain text\nline 2}, qq{plain text\nline 2}, {});
compare_render(qq{plain text\nline 2}, qq{plain text\nline 2}, {});
compare_render(qq{123}, qq{123}, {});
compare_render(qq{a\tb\n\tc}, qq{a\tb\n\tc}, {});

done_testing;
