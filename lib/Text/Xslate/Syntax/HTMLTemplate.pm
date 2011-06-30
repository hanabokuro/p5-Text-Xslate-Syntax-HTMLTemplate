package Text::Xslate::Syntax::HTMLTemplate;

use 5.008_001;

use strict;
use warnings FATAL => 'recursion';

our $VERSION = '0.1';

use Any::Moose;

extends qw(Text::Xslate::Parser);

use HTML::Template::Parser;
use Text::Xslate::Symbol;

our $before_parse_hook = undef;

before 'parse' => sub {
    if($before_parse_hook and ref($before_parse_hook) eq 'CODE'){
        my $self = shift;
        $before_parse_hook->($self);
    }
};

our %loop_context_vars = (
    __first__ => \&iterator_first,
    __odd__   => \&iterator_odd,
    __inner__ => \&iterator_inner,
    __last__  => \&iterator_last,
);

has parser => (
    is       => 'rw',
    required => 1,
    lazy     => 1,
    builder  => '_build_parser',
);

has use_has_value => (
    is => 'rw',
    default => 0,
);

has use_global_vars => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

has use_loop_context_vars => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

has has_value_function_name => (
    is => 'rw',
    default => '__has_value__',
);

has choise_global_var_function_name => (
    is => 'rw',
    default => '__choise_global_var__',
);

has loop_context_var_function_name => (
    is => 'rw',
    default => '__get_loop_context_var__',
);

has dummy_loop_item_name => (
    is       => 'rw',
    required => 1,
    default  => '__dummy_item__',
);

has loop_depth => (
    is => 'rw',
    isa => 'Int',
    default => 0,
);

has op_to_type_table => (
    is => 'rw',
    isa => 'HashRef',
    lazy => 1,
    builder  => '_build_op_to_type_table',
);

sub _build_parser {
    my($self) = @_;

    return HTML::Template::Parser->new;
}

sub _build_op_to_type_table {
    my %op_to_type_table = (
        'not' => 'not_sym',
        '!'   => 'not',
    );
    foreach my $bin_operator (qw(or and || && > >= < <= != == le ge eq ne lt gt + - * / % =~ !~)){
        $op_to_type_table{$bin_operator} = 'binary';
    }
    \%op_to_type_table;
}

sub parse {
    my($self, $input, %no_use) = @_;

    my $tree = $self->parser->parse($input);
    my @ast = $self->tree_to_ast($tree);
    \@ast;
}

sub tree_to_ast {
    my($self, $tree) = @_;

#    require YAML;print STDERR "XXX tree:", YAML::Dump($tree), '=' x 80,"\n"; # @@@

    $self->convert_children($tree->children);
}

sub convert_children {
    my($self, $children) = @_;

    my @ast;
    foreach my $node (@{ $children }){
        push(@ast, $self->convert_node($node));
    }
    @ast;
}


sub convert_node {
    my($self, $node) = @_;

    if($node->type eq 'string'){
        $self->convert_string($node);
    }elsif($node->type eq 'var'){
        $self->convert_tmpl_var($node);
    }elsif($node->type eq 'group'){
        $self->convert_group($node);
    }elsif($node->type eq 'include'){
        $self->convert_include($node);
    }else{
        die "not implemented [", $node->type, "]"; # @@@
    }
}

sub convert_string {
    my($self, $node) = @_;

    (my $id    = $node->text) =~ s/\n/\\n/g; # @@@

    $self->generate_print_raw($self->generate_literal($node->text, qq{"$id"}));
}

sub convert_tmpl_var {
    my($self, $node) = @_;

    my $expr = $self->convert_name_or_expr($node->name_or_expr);

    if(defined $node->{escape} and $node->{escape} == 0){
        $expr = $self->generate_call('mark_raw', [ $expr ]);
    }
    $self->generate_print($expr);
}

sub convert_group {
    my($self, $node) = @_;

    if($node->sub_type eq 'if' or $node->sub_type eq 'unless'){
        my @children = ( @{ $node->children } ); # copy
        pop @children; # remove Node::IfEnd

        my $if = $self->convert_if(\@children);
        $if;
    }elsif($node->sub_type eq 'loop'){
        my $loop = $self->convert_loop($node->children->[0]);
        $loop;
    }else{
        die "not implemented sub_type[", $node->sub_type, "]"; # @@@
    }
}

sub convert_if {
    my($self, $children) = @_;

    my $node = shift(@{ $children });
    if($node->type eq 'else'){
        return $self->convert_children($node->children),
    }
    my $type = $node->type;

    my $expr = $self->convert_name_or_expr($node->name_or_expr);
    if($self->use_has_value){
        $expr = $self->generate_call($self->has_value_function_name, [ $expr ]);
    }
    if($node->type eq 'unless'){
        $type = 'if';
        $expr = $self->generate_unary('!', $expr);
    }
    my $if = $self->generate_if($type, $expr, [ $self->convert_children($node->children) ]);
    if(@{$children}){
        $if->third([ $self->convert_if($children) ]);
    }
    $if;
}

sub convert_loop {
    my($self, $node) = @_;

    my $loop = $self->generate_for($self->convert_name_or_expr($node->name_or_expr));

    $self->loop_depth($self->loop_depth + 1);
    $loop->second([ $self->generate_variable('$'.$self->dummy_loop_item_name . $self->loop_depth) ]);
    $loop->third([ $self->convert_children($node->children) ]);
    $self->loop_depth($self->loop_depth - 1);

    $loop;
}

sub convert_include {
    my($self, $node) = @_;

    if($node->name_or_expr->[0] eq 'name'){
        # treat as string
        $node->name_or_expr->[0] = 'expr';
        $node->name_or_expr->[1][0] = 'string';
    }
    my $include = $self->generate_include($self->convert_name_or_expr($node->name_or_expr));

    if($self->loop_depth){
        $include->second([ $self->generate_variable('$'.$self->dummy_loop_item_name.$self->loop_depth) ]);
    }
    $include;
}

sub convert_name_or_expr {
    my($self, $name_or_expr) = @_;

    if($name_or_expr->[0] eq 'name'){
        $self->convert_name($name_or_expr->[1]);
    }else{ # expr
        $self->convert_expr($name_or_expr->[1]);
    }
}

sub convert_name {
    my($self, $name) = @_;

    if ($self->loop_depth) {
        if($self->is_loop_context_vars($name)){
            $self->convert_loop_context_vars($name);
        }elsif ($self->use_global_vars) {
            # __choise_global_var__($loop_item_1.name, $loop_item_2.name, .... $name);
            my $name = $name->[1];
            my @args;

            push(@args, $self->generate_variable($name));
            push(@args, $self->generate_literal($name));

            for (my $n = $self->loop_depth;$n > 0;$n --) {
                my $item_name = '$' . $self->dummy_loop_item_name . $n;
                push(@args, $self->generate_variable($item_name));
            }
            $self->generate_call($self->choise_global_var_function_name, \@args);
        } else {
            my $item_name = '$' . $self->dummy_loop_item_name . $self->loop_depth;
            $self->generate_field('.',
                                  $self->generate_variable($item_name),
                                  $self->generate_literal($name->[1]));
        }
    } else {
        $self->generate_variable('$' . $name->[1]);
    }
}

sub convert_expr {
    my($self, $expr) = @_;

    my $type = $expr->[0];
    if ($type eq 'op') {
        my $op_to_type = $self->op_to_type_table->{$expr->[1]};
        die "Unknown op_name[$expr->[1]]\n" unless $op_to_type;
        $type = $op_to_type;
    }

    if ($type eq 'variable') {
        $self->convert_name($expr);
    } elsif ($type eq 'number') {
        $self->generate_literal($expr->[1]);
    } elsif ($type eq 'string') {
        $self->generate_literal($expr->[1], '"'.$expr->[1].'"');
    } elsif ($type eq 'binary') {
        my %op_translate_table = (
            'eq'  => '==',
            'ne'  => '!=',
            'or'  => '||',
            'and' => '&&',
        );
        $self->generate_binary($op_translate_table{$expr->[1]} || $expr->[1],
                               $self->convert_expr($expr->[2]), $self->convert_expr($expr->[3]));
    } elsif ($type eq 'function') {
        my(undef, $name, @raw_args) = @{ $expr };
        my @args = map { $self->convert_expr($_) } @raw_args;
        $self->generate_call($name->[1], \@args);
    }elsif($type eq 'not_sym' or $type eq 'not'){
        $self->generate_unary('!', $self->convert_expr($expr->[2]));
    } else {
        die "not implemented yet [$expr->[0]]"; # @@@
    }
}

sub is_loop_context_vars {
    my($self, $name) = @_;

    $self->use_loop_context_vars and $loop_context_vars{$name->[1]};
}

sub convert_loop_context_vars {
    my($self, $name) = @_;

    if($self->loop_depth == 0){ # outside loop
        return $self->generate_literal(0);
    }

    my $var_name = $name->[1];
    my $iterator_name = '$~' . $self->dummy_loop_item_name . $self->loop_depth;
    my $item_name     = '$'  . $self->dummy_loop_item_name . $self->loop_depth;

    my $generator = $loop_context_vars{$var_name};
    return $generator->($self, $iterator_name, $item_name);
}

sub iterator_first {
    my($self, $iterator_name, $item_name) = @_;

    $self->generate_binary('==', $self->generate_iterator($iterator_name, $item_name), $self->generate_literal(0));
}

sub iterator_odd {
    my($self, $iterator_name, $item_name) = @_;

    $self->generate_binary('==',
                           $self->generate_binary('%',
                                                  $self->generate_iterator($iterator_name, $item_name),
                                                  $self->generate_literal(2)),
                           $self->generate_literal(0));
}

sub iterator_inner {
    my($self, $iterator_name, $item_name) = @_;

    $self->generate_unary('!', $self->generate_binary('||',
                                                      $self->iterator_first($iterator_name, $item_name),
                                                      $self->iterator_last($iterator_name, $item_name)));
}

sub iterator_last {
    my($self, $iterator_name, $item_name) = @_;

    $self->generate_binary('==',
                           $self->generate_iterator($iterator_name, $item_name),
                           $self->generate_iterator_max_index($iterator_name, $item_name));
}

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
sub generate_print {
    my($self, @args) = @_;

    Text::Xslate::Symbol->new(arity => 'print', first => [ @args ], id => 'print');
}

sub generate_print_raw {
    my($self, @args) = @_;

    Text::Xslate::Symbol->new(arity => 'print', first => [ @args ], id => 'print_raw');
}

sub generate_include {
    my($self, $first) = @_;
    Text::Xslate::Symbol->new(arity => 'include', id => 'include', first => $first, second => undef);
}

sub generate_literal {
    my($self, $value, $id) = @_;

    $id = $value if(not defined $id);
    Text::Xslate::Symbol->new(arity => 'literal', id => $id, value => $value);
}

sub generate_variable {
    my($self, $name) = @_;

    Text::Xslate::Symbol->new(arity => 'variable', id => $name);
}

sub generate_name {
    my($self, $name) = @_;

    Text::Xslate::Symbol->new(arity => 'name', id => $name);
}

sub generate_field {
    my($self, $id, $first, $second) = @_;

    Text::Xslate::Symbol->new(arity => 'field', id => $id, first => $first, second => $second);
}

sub generate_unary {
    my($self, $id, $expr) = @_;

    Text::Xslate::Symbol->new(arity => 'unary', id    => $id, first => $expr);
}

sub generate_call {
    my($self, $name, $args) = @_;

    Text::Xslate::Symbol->new(arity => 'call', id => '(', first => $self->generate_name($name), second => $args);
}

sub generate_binary {
    my($self, $id, $first, $second) = @_;
    Text::Xslate::Symbol->new(
        arity => 'binary',
        id => $id,
        first => $first,
        second => $second
    );
}

sub generate_if {
    my($self, $id, $first, $second) = @_;

    Text::Xslate::Symbol->new(arity => 'if', id => $id, first => $first, second => $second);
}

sub generate_for {
    my($self, $first) = @_;

    Text::Xslate::Symbol->new(arity => 'for', id => 'for', first => $first);
}

sub generate_iterator {
    my($self, $iterator_name, $item_name) = @_;

    Text::Xslate::Symbol->new(
        arity => 'iterator',
        id    => $item_name,
        first => $self->generate_variable($item_name),
    );
}

sub generate_iterator_max_index {
    my($self, $iterator_name, $item_name) = @_;

    $self->generate_unary('max_index', $self->generate_iterator_body($iterator_name, $item_name));
}

sub generate_iterator_body {
    my($self, $iterator_name, $item_name) = @_;

    Text::Xslate::Symbol->new(arity => 'iterator_body', id => $iterator_name,
                              first => $self->generate_iterator($iterator_name, $item_name),
                              second => $self->generate_iterator($iterator_name, $item_name),
                          );
}

sub generate_iterator_size {
    my($self, $iterator_name, $item_name) = @_;

    Text::Xslate::Symbol->new(arity => 'iterator_body', id => $iterator_name,
                              first => $self->generate_iterator($iterator_name, $item_name),
                              second => $self->generate_iterator($iterator_name, $item_name),
                          );
}

sub default_has_value {
    return 0 if(@_ == 0);
    return @{$_[0]} != 0 if($_[0] and ref($_[0]) eq 'ARRAY');
    $_[0];
}

sub default_choise_global_var {
    my($global, $name, @loop_var_list) = @_;
    foreach my $loop_var (@loop_var_list){
        if(exists $loop_var->{$name}){
            return $loop_var->{$name};
        }
    }
    $global;
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;

=head1 NAME

Text::Xslate::Syntax::HTMLTemplate - An alternative syntax compatible with HTML Template

=head1 SYNOPSIS

    use Text::Xslate;

    local $Text::Xslate::Syntax::HTP::before_parse_hook = sub {
        my $parser = shift;
        $parser->use_global_vars(1);
        $parser->use_loop_context_vars(1);
        $parser->use_has_value(1);
    };
    my $tx = Text::Xslate->new(syntax => 'HTMLTemplate', compiler => 'Text::Xslate::Compiler::HTMLTemplate',
                               function => {
                                 __choise_global_var__ => \&Text::Xslate::Syntax::HTMLTemplate::default_choise_global_var,
                                 __has_value__ => \&Text::Xslate::Syntax::HTMLTemplate::default_has_value,
                               }
                              );

    print $tx->render('hello.tx');

=head1 DESCRIPTION

B<Syntax::HTMLTemplate> is a parser for Text::Xslate.
It parse HTML::Template syntax template.

=head1 OPTIONS

=over

=item C<use_global_vars>

same as global_vars option of HTML::Template.
you have to register function to handle that.

=item C<use_loop_context_vars>

same as loop_context_vars option of HTML::Template.

=item C<use_has_value>

HTML::Template treats empty array referense as Flase.
But Xslate treats empty array referense as True.
when use_has_value is seted, Syntax::HTMLTemplate
you have to register function to handle that.

=back

=head1 AUTHOR

Shigeki Morimoto E<lt>Shigeki(at)Morimo.toE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2011, Shigeki, Morimoto. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
