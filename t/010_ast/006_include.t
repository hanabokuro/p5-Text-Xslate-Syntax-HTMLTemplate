#!perl -w

use strict;
use warnings;

use Test::More;

use t::lib::Util;

my $tx = Text::Xslate->new(syntax => 'Metakolon');

compare_ast(<<'END;', <<'END;', {});
[% include "x.tx" %]
END;
<TMPL_INCLUDE "x.tx">
END;


done_testing;
