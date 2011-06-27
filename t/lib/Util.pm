package t::lib::Util;
use strict;

use base qw(Exporter);
our @EXPORT = qw(compare_ast compare_render);

use Test::More;

use Text::Xslate;
use Text::Xslate::Syntax::Metakolon;
use Text::Xslate::Compiler::HTP;
use Text::Xslate::Syntax::HTP;

use YAML;

sub compare_ast {
    my($template_metakolon, $template_htp, $params) = @_;

    my $parser_metakolon = Text::Xslate::Syntax::Metakolon->new();
    my $parser_htp       = Text::Xslate::Syntax::HTP->new();

    my $ast_metakolon = $parser_metakolon->parse($template_metakolon);
    my $ast_htp       = $parser_htp->parse($template_htp);

    my $yaml_metakolon = YAML::Dump($ast_metakolon);
    my $yaml_htp       = YAML::Dump($ast_htp);
    foreach my $yaml (\$yaml_metakolon, \$yaml_htp){
        $$yaml =~ s/^.*(
                        can_be_modifier |
                        column |
                        is_defined |
                        is_reserved |
                        is_value |
                        lbp |
                        led |
                        line |
                        nud |
                        ubp |
                        std
                    ):.*\n//gmx;
    }
    {
        require Text::Diff;
        my $diff = Text::Diff::diff(\$yaml_metakolon, \$yaml_htp);
        if($yaml_metakolon ne $yaml_htp){
            print STDERR "XXX ast_metakolon:", $yaml_metakolon;
            print STDERR "XXX ast_htp:", $yaml_htp;
            print STDERR "==== diff begin ====\n", $diff, "\n==== diff end ====\n";
        }
    }
    is($yaml_metakolon, $yaml_htp);

    compare_render($template_metakolon, $template_htp, $params);
}

sub compare_render {
    my($template_metakolon, $template_htp, $params) = @_;

    my $tx_metakolon = Text::Xslate->new(syntax => 'Metakolon', path => [ 't/template' ]);
    my $tx_htp       = Text::Xslate->new(compiler => Text::Xslate::Compiler::HTP->new, path => [ 't/template' ]);

    is($tx_metakolon->render_string($template_metakolon, $params),
       $tx_htp->render_string($template_htp, $params));
}

1;
