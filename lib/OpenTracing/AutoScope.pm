package OpenTracing::AutoScope;

use strict;
use warnings;

use OpenTracing::GlobalTracer qw/$TRACER/;

use Carp;
use Scope::Context;


sub start_guarded_span {
    my $class          = shift;
    my $operation_name = scalar @_ % 2 ? shift : _context_sub_name( );
    my %options        = @_;
    
    my $scope = $TRACER->start_active_span( $operation_name, %options );
    
    Scope::Context->up->reap( sub { $scope->close } );
    
    return
}



# _context_sub_name
#
# Returns the sub_name of our caller (caller of `start_guarded_span`)
sub _context_sub_name { Scope::Context->up->up->sub_name }



1;
