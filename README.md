# Perl - OpenTracing AutoScope

Making life easyier with 'auto-closing guarded scopes', instead of keeping track
manually.

## SYNOPSIS

```perl
MyPackage;

use OpenTracing::AutoScope;

sub foo {
    OpenTracing::AutoScope->start_guarded_span;
    
    ...
    
    return $foo
}
```

## DESCRIPTION

Using the C<start_guarded_span> class method is just a convenience around things
like:

```perl
use OpenTracing::GlobalTracer qw/$TRACER/;

sub foo {
    my $scope = $TRACER->start_active_span( 'MyPackage::foo' => { options };
    
    my $self = shift;
    
    ... # do stuff
    
    $scope->close
    
    return $foo
}
```
