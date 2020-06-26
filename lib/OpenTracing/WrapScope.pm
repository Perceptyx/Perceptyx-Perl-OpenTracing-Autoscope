package OpenTracing::WrapScope;
our $VERSION = '0.100.0';
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
