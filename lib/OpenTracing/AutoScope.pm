package OpenTracing::AutoScope;

=head1 NAME

OpenTracing::AutoScope - Automagically create and close scoped spans.

=head1 SYNOPSIS

    MyPackage;
    
    use OpenTracing::AutoScope;
    
    sub foo {
        OpenTracing::AutoScope->start_guarded_span;
        
        ...
        
    }

=cut



use OpenTracing::GlobalTracer qw/$TRACER/;

use Scope::Context;



=head1 DESCRIPTION

Using the C<start_guarded_span> class method is just a convenience around things
like:

    use OpenTracing::GlobalTracer qw/$TRACER/;
    
    sub foo {
        my $scope = $TRACER->start_active_span( 'MyPackage::foo' => { options };
        
        my $self = shift;
        
        ... # do stuff
        
        $scope->close
        
        return $foo
    }

OpenTracing provides a instance method for a C<$tracer>, called
C<start_active_span> and returns a scope object. But scope object, according to
the API spec need to be closed by the programmer and it will issue a warning if
not done so.

But that strategy becomes very inconvenient if a programmer wants to do 'return
early' or bail out half way because of some other conditions.

This being Perl, we can do better and use the feaures that would normally come
on the end of scope and could use a C<DESTROY> or C<DEMOLISH> method. But that
would still send out a warning.

This module will make it easy again, and a bit more. It will call C<close> on
the relevant scope it has created automagically.

It will also use the subroutine name as the operation name, that otherwise would
be required.



=head1 CLASS METHODS



=head2 start_guarded_span

Starts a scope guarded span which will automagically gets closed once the proces
runs out of the current scope. And it returns nothing tp prevent programmers to
explicitely close the returned scope.

It does not need an operation_name, it will default to the current subroutine
name. Other than that, it accepts any or all of the options for
C<< $TRACER->start_active_span >>. 

=cut

sub start_guarded_span {
    my $class = shift;
    
    my ( $operation_name, $options ) = _get_operation_name_and_options( @_ )
    
    my $scope = $TRACER->start_active_span( $operation_name, $options );
    
    Scope::Context->up->reap( sub { $scope->close } )
    
    return
}



# _get_operation_name_and_options
#
# Returns a value for the operation_name and a hashref for the options.
#
# if no operation_name is given, it will try tu use subname from the context.
#
sub _get_operation_name_and_options {
    my $operation_name;
    my $options;
    
    if ( scalar @_ == 2 ) {
        # recieved 2 params, assuming they are correct
        $operation_name = shift;
        $options        = shift;
        
    } elsif ( scalar @_ == 1 and !is_ref $_[0] ) {
        # recieved 1 param, non ref, $operation_name
        $operation_name = shift;
        
    } elsif ( scalar @_ == 1 and is_hashref $_[0] ) {
        # recivec 1 param, a hashref, must be the options then
        $options        = shift;
        
    } elsif ( scalar @_ ) {
        # recieved 0 params would have been okay and would used defaults ... BUT
        carp "OpenTracing::AutoScope expected \$operation_name => \\%options";
        
    }
    
    $operation_name //= _context_sub_name;
    $options        //= {};
    
    return $operation_name, $options
    
}


# _context_sub_name
#
# Returns the sub_name of our caller (caller of `start_guarded_span`)
sub _context_sub_name { Scope::Context->up->up->sub_name }



1;
