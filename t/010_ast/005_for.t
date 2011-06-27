#!perl -w

use strict;
use warnings;

use Test::More;

use t::lib::Util;

my $tx = Text::Xslate->new(syntax => 'Metakolon');

compare_ast(<<'END;', <<'END;', {});
[% for $loop->$__dummy_item__ { %][% $name %][% } %]
END;
<TMPL_LOOP NAME=loop><TMPL_VAR NAME=name></TMPL_LOOP>
END;

compare_ast(<<'END;', <<'END;', {});
[% for $loop1->$__dummy_item__ { %][% for $loop2->$__dummy_item__ { %][% $name %][% } %][% } %]
END;
<TMPL_LOOP NAME=loop1><TMPL_LOOP NAME=loop2><TMPL_VAR NAME=name></TMPL_LOOP></TMPL_LOOP>
END;


done_testing;
