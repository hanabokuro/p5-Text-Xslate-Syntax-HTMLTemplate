package Text::Xslate::Compiler::HTP;

use 5.008_001;

use strict;
use warnings FATAL => 'recursion';

our $VERSION = '0.1';

use Any::Moose;

extends qw(Text::Xslate::Compiler);

has syntax => (
    is       => 'rw',

    default  => 'HTP',
);

sub _generate_call {
    my($self, $node) = @_;
    my $callable = $node->first; # function or macro
    my $args     = $node->second;

    my @code = $self->SUPER::_generate_call($node);

    if($callable->arity eq 'name'){
        my @code_fetch_symbol = $self->compile_ast($callable);
        @code = (
            $self->opcode( pushmark => undef, comment => $callable->id ),
            (map { $self->push_expr($_) } @{$args}),

            $self->opcode( fetch_s => $callable->value, line => $callable->line ),
            $self->opcode( 'or' => scalar(@code_fetch_symbol) + 1),

            @code_fetch_symbol,
            $self->opcode( 'funcall' )
        );
    };
    @code;
}

sub _generate_variable {
    my($self, $node) = @_;

    if(defined(my $lvar_id = $self->lvar->{$node->value})) {
        return $self->opcode( load_lvar => $lvar_id, symbol => $node );
    }
    else {
        my $name = $self->_variable_to_value($node);

        my @code;

        my @lvar_name_list =  sort { $self->lvar->{$b} <=> $self->lvar->{$a} } grep { /^\$/ } keys %{$self->lvar};
        my $index = 0;
        foreach my $lvar_name (@lvar_name_list){
            my $skip = 2 + (@lvar_name_list - ++$index)*3; # 3 means 'load_var','fetch_filed_s','or'.
            push(@code,
                 $self->opcode( load_lvar => $self->lvar->{$lvar_name}, symbol => $lvar_name ),
                 $self->opcode( fetch_field_s => $name, line => $node->line ),
                 $self->opcode( or => $skip),
             );
        }
        if($name =~ /~/) {
            $self->_error("Undefined iterator variable $node", $node);
        }
        push(@code, $self->opcode( fetch_s => $name, line => $node->line ));
        @code;
    }
}


no Any::Moose;
__PACKAGE__->meta->make_immutable();

=head1 NAME

Text::Xslate::Compiler::HTP - An Xslate compiler to generate HTML::Template::Pro compatible intermediate code.

=head1 AUTHOR

Shigeki Morimoto E<lt>Shigeki(at)Morimo.toE<gt>

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2011, Shigeki, Morimoto. All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

1;
