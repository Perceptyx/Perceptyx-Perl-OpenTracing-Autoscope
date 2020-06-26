package OpenTracing::WrapScope;
use strict;
use warnings;
use B::Hooks::EndOfScope;
use OpenTracing::GlobalTracer;
use Sub::Info qw/sub_info/;

{  # transparent caller, stolen from Hook::LexWrap
no warnings 'redefine';
*CORE::GLOBAL::caller = sub (;$) {
    my ($height) = ($_[0]||0);
    my $i=1;
    my $name_cache;
    while (1) {
        my @caller = CORE::caller() eq 'DB'
            ? do { package DB; CORE::caller($i++) }
            : CORE::caller($i++);
        return if not @caller;
        $caller[3] = $name_cache if $name_cache;
        $name_cache = $caller[0] eq __PACKAGE__ ? $caller[3] : '';
        next if $name_cache || $height-- != 0;
        return wantarray ? @_ ? @caller : @caller[0..2] : $caller[0];
    }
};
}

sub import {
    my (undef, @subs) = @_;
    my $pkg = caller;
    on_scope_end {
        foreach my $sub (@subs) {
            $sub = "${pkg}::$sub" if $sub !~ /'|::/;
            die "Couldn't find sub: $sub" if not defined &$sub;

            no strict 'refs';
            no warnings 'redefine';
            *$sub = wrapped(\&$sub);
        }
    };
    return;
}


sub wrapped {
    my ($coderef) = @_;
    my $info = sub_info($coderef);

    return sub {
        my $tracer = OpenTracing::GlobalTracer->get_global_tracer; 
        my $scope = $tracer->start_active_span(
            $info->{name},
            tags => {
                package => $info->{package},
                file    => $info->{file},
                line    => $info->{start_line},
            },
        );

        my $result;
        my $wantarray = wantarray;    # eval will have its own
        my $ok = eval {
            if (defined $wantarray) {
                $result = $wantarray ? [&$coderef] : &$coderef;
            }
            else {
                &$coderef;
            }
            1;
        };
        $scope->get_span->add_tag(error => $@) unless $ok;
        $scope->close();

        die $@ unless $ok;
        return if not defined wantarray;
        return wantarray ? @$result : $result;
    };
}

1;
__END__
=pod

=head1 NAME

OpenTracing::WrapScope - automatically add spans to selected subroutines

=head1 SYNOPSIS

  use OpenTracing::WrapScope qw/foo Foo::bar/;
  use Foo;
    
  sub foo { ... }

  package Foo {
      sub bar { ... }
  }

Roughly equivalent to:

  use OpenTracing::AutoScope;

  sub foo {
      OpenTracing::AutoScope->start_guarded_span();
      ...
  }

  package Foo {
      sub bar {
          OpenTracing::AutoScope->start_guarded_span();
          ...
      }
  }

=head1 IMPORT ARGUMENTS

import takes subroutine names as arguments, these need to be fully qualified 
if they are not in the current package. All specified subroutines will have
spans attached to them. Context and caller frames will be preserved.
Additionally, if a wrapped subroutine dies, an additional C<error> tag will
be added to the span.

=head1 CAVEATS

=head2 caller

Because this module overrides caller, it's best to use it as soon as possible,
before caller-using code is compiled. It likely won't work well with other
modules which override caller themselves.

=head2 Exporter

Subroutines exported using L<Exporter> or a similar module could split into
two versions. If the export happens before the span handling is applied to
a subroutine, only the original version will have a span, the exported
version will be unmodified.

In order to wrap subroutines in modules utilising L<Exporter>,
use L<OpenTracing::WrapScope> directly in those modules.

=cut
