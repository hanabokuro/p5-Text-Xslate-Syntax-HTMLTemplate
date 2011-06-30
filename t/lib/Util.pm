package t::lib::Util;
use strict;

use base qw(Exporter);
our @EXPORT = qw(compare_ast compare_render);

use Test::More;

use HTML::Template::Pro;
use Text::Xslate;
use Text::Xslate::Syntax::Metakolon;
use Text::Xslate::Compiler::HTMLTemplate;
use Text::Xslate::Syntax::HTMLTemplate;

use YAML;

sub compare_ast {
    my($template_metakolon, $template_htp, %args) = @_;

    my $parser_metakolon = Text::Xslate::Syntax::Metakolon->new();
    my $parser_htp       = Text::Xslate::Syntax::HTMLTemplate->new();

    my $ast_metakolon = $parser_metakolon->parse($template_metakolon);
    my $ast_htp       = $parser_htp->parse($template_htp);

    my $yaml_metakolon = YAML::Dump($ast_metakolon);
    my $yaml_htp       = YAML::Dump($ast_htp);

    my @unwatch_filed = qw/can_be_modifier
                           column
                           counterpart
                           is_defined
                           is_logical
                           is_reserved
                           is_value
                           lbp
                           led
                           line
                           nud
                           ubp
                           std/;
    push(@unwatch_filed, @{$args{unwatch_filed}}) if($args{unwatch_filed});
    my $unwatch_filed_re = join('|', (map { quotemeta($_) } @unwatch_filed));
    foreach my $yaml (\$yaml_metakolon, \$yaml_htp){
        $$yaml =~ s/^.*($unwatch_filed_re):.*\n//gmx;
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

    compare_render($template_htp, %args);
}

sub compare_render {
    my($template, %args) = @_;

    $args{function} ||= {};
    $args{use_global_vars}       = 0 if(not exists $args{use_global_vars});
    $args{use_has_value}         = 0 if(not exists $args{use_has_value});
    $args{use_loop_context_vars} = 0 if(not exists $args{use_loop_context_vars});
    $args{params} ||= {};

    my $htp = HTML::Template::Pro->new_scalar_ref(\$template,
                                                  path => [ 't/template' ],
                                                  functions => $args{function},
                                                  global_vars => $args{use_global_vars},
                                                  loop_context_vars => $args{use_loop_context_vars},,
                                              );
    $htp->param($args{params});
    my $htp_output = $htp->output();
    is($htp_output, $args{expected}, "htp == expected") if(exists $args{expected});

    $args{function}->{__has_value__} = \&Text::Xslate::Syntax::HTMLTemplate::default_has_value;
    $args{function}->{__choise_global_var__} = \&Text::Xslate::Syntax::HTMLTemplate::default_choise_global_var;
    local $Text::Xslate::Syntax::HTMLTemplate::before_parse_hook = sub {
        my $parser = shift;
        $parser->use_global_vars($args{use_global_vars});
        $parser->use_has_value($args{use_has_value});
        $parser->use_loop_context_vars($args{use_loop_context_vars});
    };

    my $tx = Text::Xslate->new(syntax => 'HTMLTemplate',
                               type => 'html',
                               compiler => 'Text::Xslate::Compiler::HTMLTemplate',
                               path => [ 't/template' ],
                               function => $args{function},
                           );
    my $tx_output = $tx->render_string($template, $args{params});
    is($tx_output,  $args{expected}, "tx == expected") if(exists $args{expected});

    is($tx_output, $htp_output, "tx == htp");
}

1;
