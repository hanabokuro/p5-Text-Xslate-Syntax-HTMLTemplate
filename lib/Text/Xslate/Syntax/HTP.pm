package Text::Xslate::Syntax::HTP;

use 5.008_001;

use strict;
use warnings FATAL => 'recursion';

our $VERSION = '0.1';

use Any::Moose;

use HTML::Template::Parser;
use Text::Xslate::Symbol;

has parser => (
    is       => 'rw',
    required => 1,
    lazy     => 1,
    builder  => '_build_parser',
);

has dummy_loop_item_name => (
    is       => 'rw',
    required => 1,
    default  => '__dummy_item__',
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

#    require YAML;print STDERR "XXX tree:", YAML::Dump($tree); # @@@

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
    Text::Xslate::Symbol->new(arity => 'print',
                              first => [
                                  Text::Xslate::Symbol->new(arity => 'literal',
                                                            id => qq{"$id"},
                                                            value => $node->text,
                                                        ),
                              ],
                              id => 'print_raw',
                          );
}

sub convert_tmpl_var {
    my($self, $node) = @_;

    Text::Xslate::Symbol->new(arity => 'print',
                              first => [ $self->convert_name_or_expr($node->name_or_expr), ],
                              id => 'print',
                          );
}

sub convert_group {
    my($self, $node) = @_;

    if($node->sub_type eq 'if'){
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
    my $if = Text::Xslate::Symbol->new(arity  => 'if',
                                       id     => $node->type,
                                       first  => $self->convert_name_or_expr($node->name_or_expr),
                                       second => [ $self->convert_children($node->children) ],
                                   );
    if(@{$children}){
        $if->third([ $self->convert_if($children) ]);
    }
    $if;
}

sub convert_loop {
    my($self, $node) = @_;

    my $loop = Text::Xslate::Symbol->new(arity  => 'for',
                                         id     => 'for',
                                         first  => $self->convert_name_or_expr($node->name_or_expr),
                                         second => [
                                             Text::Xslate::Symbol->new(arity => 'variable', id => '$'.$self->dummy_loop_item_name),
                                         ],
                                         third => [ $self->convert_children($node->children) ],
                                     );
    $loop;
}

sub convert_include {
    my($self, $node) = @_;

    if($node->name_or_expr->[0] eq 'name'){
        # treat as string
        $node->name_or_expr->[0] = 'expr';
        $node->name_or_expr->[1][0] = 'string';
    }
    my $include = Text::Xslate::Symbol->new(arity  => 'include',
                                            id     => 'include',
                                            first  => $self->convert_name_or_expr($node->name_or_expr),
                                            second => undef,
                                        );
    $include;
}

sub convert_name_or_expr {
    my($self, $name_or_expr) = @_;

    if($name_or_expr->[0] eq 'name'){
        Text::Xslate::Symbol->new(arity => 'variable', id => '$' . $name_or_expr->[1][1] );
    }else{ # expr
        $self->convert_expr($name_or_expr->[1]);
    }
}

sub convert_expr {
    my($self, $expr) = @_;

    my $type = $expr->[0];
    if($type eq 'op'){
        my $op_to_type = $self->op_to_type_table->{$expr->[1]};
        die "Unknown op_name[$expr->[1]]\n" unless $op_to_type;
        $type = $op_to_type;
    }

    if($type eq 'variable'){
        Text::Xslate::Symbol->new(arity => 'variable', id => '$' . $expr->[1] );
    }elsif($type eq 'number'){
        Text::Xslate::Symbol->new(arity => 'literal', id => $expr->[1], value => $expr->[1]);
    }elsif($type eq 'string'){
        Text::Xslate::Symbol->new(arity => 'literal', id => '"'.$expr->[1].'"', value => $expr->[1]);
    }elsif($type eq 'binary'){
        Text::Xslate::Symbol->new(arity => 'binary', id => $expr->[1],
                                  first => $self->convert_expr($expr->[2]),
                                  second => $self->convert_expr($expr->[3]));
    }else{
        # @@@ __odd__ __even__ __inner__ __counter__  __last__
        die "not implemented yet [$expr->[0]]"; # @@@
        }
    }


no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

